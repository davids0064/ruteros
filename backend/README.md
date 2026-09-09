# Boulder Co-Setter — Backend API

Implementación de `.specs/04_COMPONENT_SPECS.md §0.1`:
**TypeScript 5 / Node 20 · NestJS 10 · Kysely · dbmate · JWT RS256 · S3 prefirmado**.

Kysely **consume** el esquema de `db/`; no lo posee. Las transiciones
`available ⇄ in_use` viven en los triggers de PostgreSQL, nunca aquí.

## Puesta en marcha

```bash
npm install
npm run keys:generate          # par RS256 en ./keys (RNF-4)
cp .env.example .env

# PostgreSQL 15 local
docker run -d --name boulder-db -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=boulder_dev -p 55432:5432 postgres:15

npm run db:up                  # dbmate aplica db/migrations/*.sql sin transformarlos
npm run db:seed                # V-Scale y Fontainebleau globales
npm run start:dev              # http://localhost:3000/api/v1
```

Sin `JWT_*_KEY_PATH` la app genera un par RS256 efímero en memoria: sirve para
arrancar en frío, pero invalida todas las sesiones en cada reinicio.

## Despliegue en Railway

El servicio vive en `backend/`, así que en Railway hay que fijar
**Settings -> Root Directory = `backend`**; a partir de ahí Nixpacks detecta
Node 20 y `railway.json` fija build, arranque y healthcheck.

```
Postgres (plugin)  ->  DATABASE_URL   (usa la URL interna *.railway.internal:
                                       red privada, sin SSL)
Servicio API       ->  variables de .env.example
```

Variables que **no** puedes dejar en blanco:

| Variable | Valor |
| :--- | :--- |
| `NODE_ENV` | `production` |
| `DATABASE_URL` | referencia al plugin de Postgres |
| `JWT_PRIVATE_KEY`, `JWT_PUBLIC_KEY` | el PEM, o su base64 |
| `S3_ENDPOINT`, `S3_BUCKET`, `S3_REGION`, `S3_PUBLIC_BASE_URL` | bucket S3-compatible |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | token de API del bucket |

`PORT` lo inyecta Railway; no lo definas a mano.

### Claves JWT sin disco

Railway no monta disco persistente, así que el PEM va en la variable:

```bash
base64 -i keys/jwt-private.pem | tr -d '\n' | pbcopy   # -> JWT_PRIVATE_KEY
base64 -i keys/jwt-public.pem  | tr -d '\n' | pbcopy   # -> JWT_PUBLIC_KEY
```

`KeyProvider` acepta el PEM tal cual, con `\n` escapados o en base64. Con
`NODE_ENV=production` y ninguna de las dos vías configuradas **el arranque
falla**: un par efímero cerraría la sesión de todos los usuarios en cada
despliegue, y eso no puede degradarse a un warning.

### Almacenamiento

Cualquier backend S3-compatible sirve; `S3_ENDPOINT` activa el modo
path-style. Con Cloudflare R2, `S3_REGION=auto` y `S3_PUBLIC_BASE_URL` apunta
al dominio público del bucket. **El bucket necesita CORS** que permita `PUT`
con la cabecera `Content-Type` desde el origen de la app: el binario va del
cliente al bucket, nunca por la API.

La URL prefirmada no fija `Content-Length` —firmarlo lo convierte en un valor
exacto exigido, y el cliente sube el tamaño real del fichero—, así que el tope
de `S3_MAX_OBJECT_BYTES` viaja en `PresignResponse.maxObjectBytes` y lo aplica
el cliente, más una política de tamaño en el propio bucket.

### Migraciones

`dbmate` es un binario externo, no una dependencia npm: las migraciones se
aplican desde tu máquina contra la URL **pública** de Postgres antes de
promover la versión.

```bash
DATABASE_URL='<url-publica-de-railway>' npm run db:up
DATABASE_URL='<url-publica-de-railway>' npm run db:seed
```

### Healthcheck

`GET /api/v1/health` es público y hace `select 1` contra el pool: un proceso
vivo que no habla con Postgres devuelve 500 y Railway no le manda tráfico.

## Pruebas

```bash
npm run test         # todo
npm run test:unit    # motor de dificultad (§6)
npm run test:e2e     # contrato REST contra PostgreSQL real (Testcontainers)
```

Las pruebas de integración levantan **PostgreSQL 15 real** vía Testcontainers
(requiere Docker): los triggers se ejercitan de verdad, nunca contra un mock.
Cubren los diez casos obligatorios de `04 §7`.

El esquema tiene además su propia suite pgTAP en `db/tests/`:

```bash
pg_prove -d boulder_dev ../db/tests/*.test.sql
```

## Mapa de módulos

Cada `@Module` mapea 1:1 con un módulo del PRD.

| Módulo | Rutas | Especificación |
| :--- | :--- | :--- |
| `auth` | `/auth/*` | §2.3 · RF-4.1, RF-4.2 |
| `gyms` | `/gyms` | §2.4 · RF-1.1, RF-1.2 |
| `memberships` | `/gyms/:gymId/setters` | §2.5 · US-01, US-04 |
| `grades` | `/grade-systems`, `/gyms/:gymId/grade-systems` | §2.6 · RF-3.2 |
| `walls` | `/gyms/:gymId/walls`, `/walls/:wallId` | §2.7 · RF-3.1, US-03 |
| `inventory` | `/hold-sets`, `/holds` | §2.8 · RF-2.1 – RF-2.3 |
| `routes` | `/routes`, `/walls/:wallId/routes` | §2.9 · RF-4.2, RF-4.3, US-05, US-07 |
| `uploads` | `/uploads/presign` | §2.10 · §5 |

## Invariantes que no se negocian

* **Autoría (RF-4.3).** `routes.creator_id` se escribe una sola vez desde
  `JWT.sub`. El `creatorId` del payload es informativo; si difiere → `403
  NOT_ROUTE_AUTHOR`.
* **Inventario (RF-2.3).** La API nunca escribe `holds.status = 'in_use'` ni
  saca una presa de ese estado. Lo hacen los triggers; el servicio relee.
* **Concurrencia.** `POST /routes` bloquea las presas con `SELECT … FOR UPDATE`
  antes de insertarlas: dos setters simultáneos no pueden reservar la misma.
* **Sin binarios en la API.** No hay endpoints `multipart/form-data`. Los PNG
  van del cliente a S3 con URL prefirmada (§5); la API sólo ve metadatos.

## Decisiones de diseño

Los huecos encontrados en `01`–`04` y cómo se cerraron están en
[`.specs/05_DECISIONS.md`](../.specs/05_DECISIONS.md).
