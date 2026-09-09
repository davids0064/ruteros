# Component Specifications Document (04_COMPONENT_SPECS.md) — Boulder Co-Setter App

**Versión:** 1.3.0
**Estado:** ESPECIFICACIÓN DE MÓDULOS, API REST & ALGORITMOS
**Enfoque:** SDD / Centralized PostgreSQL Backend / On-Device Image Processing

> **Changelog v1.3.0** — §0.2 se alinea con el cliente ya implementado:
> Riverpod pasa a `2 o 3` (se usa la API `Notifier`, común a ambas), Retrofit
> sale del stack en favor de un cliente Dio escrito a mano, y la fila de
> inferencia distingue la implementación por defecto (`ColorSegmentEngine`,
> Dart puro sobre `image`) de la vía de ampliación (`onnxruntime`). El §1 no
> cambia: `SegmentService` sigue siendo el contrato, y ambas implementaciones
> lo cumplen. Las razones, en `05_DECISIONS.md` D-09 a D-12.
>
> **Changelog v1.2.0** — §0.2: el pin de Flutter pasa de `3.2x` a `3.4x`. Dart 3
> se mantiene sin cambios, de modo que el pin de lenguaje sigue vigente. Motivo:
> el rango 3.2x quedó fuera del soporte de las dependencias de cliente vigentes.
> El resto del documento no cambia.
>
> **Changelog v1.1.0** — Se completa el documento truncado en v1.0.0:
> se añade §0 (stack vinculante), §2 (contrato REST completo), §3 (convenciones
> de serialización), §4 (autenticación y autorización), §5 (pipeline de subida a
> S3), §6 (motor de dificultad) y §7 (estrategia de pruebas).
> El §1 (CVEngine) se conserva sin cambios respecto de v1.0.0.

---

## 0. Stack Tecnológico Vinculante

Decisión de arquitectura que cierra el hueco dejado por `02_ARCHITECTURE.md`
("API Gateway / Business Logic" sin lenguaje declarado).

### 0.1 Backend

| Capa | Tecnología | Justificación anclada en las specs |
| :--- | :--- | :--- |
| Lenguaje | **TypeScript 5.x (Node 20 LTS)** | Los DTOs de `03_DATA_MODELS.md` ya están escritos en TypeScript; reutilizarlos literalmente elimina toda traducción de dominio. |
| Framework | **NestJS 10** | Su modularidad (`@Module`) mapea 1:1 con los Módulos 1–5 del PRD, habilitando el desarrollo incremental exigido por SDD. |
| Acceso a datos | **Kysely** (query builder tipado) | **NO un ORM.** El esquema de `03` incluye ENUMs nativos y dos triggers que son la fuente de verdad del ciclo de vida del inventario (RF-2.3). Un ORM con migraciones generadas (Prisma, TypeORM `synchronize`) reescribiría o ignoraría esos triggers. Kysely consume el esquema; no lo posee. |
| Migraciones | **dbmate** | Ejecuta los `.sql` planos de `db/migrations/` sin transformarlos. El SQL de `03` sigue siendo el artefacto literal desplegado. |
| Validación | **class-validator + class-transformer** | `ValidationPipe` global con `whitelist: true` y `forbidNonWhitelisted: true`. |
| Autenticación | **@nestjs/jwt + Passport (JWT RS256)** | RNF-4. |
| Object Storage | **@aws-sdk/client-s3** (URLs prefirmadas) | Ver §5. |
| Pruebas | **Jest + Supertest + Testcontainers** | Testcontainers levanta PostgreSQL 15 real: los triggers se ejercitan de verdad, nunca contra un mock. |

**Regla de oro del backend:** la lógica de negocio **no** replica las
transiciones `available ⇄ in_use`. Esas viven en los triggers
`trigger_mark_hold_in_use` y `trigger_release_holds_dismantle`. El servicio
inserta en `placed_holds` o actualiza `routes.status` y **relee** el estado.

### 0.2 Cliente

| Capa | Tecnología | Justificación |
| :--- | :--- | :--- |
| Framework | **Flutter 3.4x / Dart 3** | Cliente único iOS + Android. Versión de referencia verificada: 3.47.2 (Dart 3.13.2). |
| Estado | **Riverpod 2 o 3** | Se programa contra la API `Notifier`/`AsyncNotifier`, común a ambas mayores. Separación explícita entre estado volátil del canvas (RAM) y estado remoto. |
| HTTP | **Dio** con cliente tipado escrito a mano | Interceptor que inyecta `Authorization: Bearer` en toda petición (RNF-4) y renueva el token una sola vez ante un 401. Sin Retrofit: ver D-10. |
| Canvas 2D | **`CustomPainter` + `RepaintBoundary`** | RNF-2: 60 FPS. El árbol de widgets no se reconstruye durante el arrastre; solo repinta la capa de presas. |
| Sensores | **`sensors_plus`** | Lectura de inclinación θ vía acelerómetro (RF-3.1). |
| Inferencia | **`ColorSegmentEngine`** (Dart puro sobre `image`) | Implementación por defecto de `SegmentService` (§1.1): segmentación por el `colorHex` del set, que la propia §1.1 declara como entrada. Ver D-11. |
| Inferencia (ampliación) | **`onnxruntime`** (ONNX Runtime Mobile) | YOLOv8-seg exportado a ONNX, como segunda implementación de `SegmentService`. Requiere embarcar el modelo entrenado; ver §1 y D-11. |
| Imagen | **`image`** | Decodificación, máscara alpha y encode PNG, todo en un isolate. |
| Cámara | **`image_picker`** | Captura de la foto del set y del muro. |
| Secretos | **`flutter_secure_storage`** | Único almacenamiento en disco del cliente (RNF-1). |

**Regla de oro del cliente (RNF-1):** no existe base de datos local. Se permite
únicamente caché **efímera en RAM** y almacenamiento seguro del refresh token
(`flutter_secure_storage`). Ningún muro, ruta o presa se persiste en disco.

---

## 1. Módulo 1: Visión por Computador e Inferencia (CVEngine)

Este componente se ejecuta en la capa de infraestructura del cliente móvil para aislar presas y enviarlas en formato PNG transparente al Backend.

### 1.1 Contrato del Servicio (`SegmentService`)
* **Propósito:** Recibir una fotografía de un set de presas y retornar una lista de *sprites* cortados con fondo transparente y sus metadatos en memoria RAM.
* **Entrada:** `ImageFile` (JPG/PNG), `ColorHex` (Filtro por color del set).

### 1.2 Algoritmo de Segmentación e Inferencia (Pseudocódigo / Pipeline)
```typescript
interface SegmentedHoldResult {
  imageBytesPNG: Uint8Array; // Imagen recortada con canal Alpha (Transparente)
  boundingBoxPx: { width: number; height: number };
  suggestedCategory: 'crimp' | 'sloper' | 'jug' | 'pinch' | 'foothold' | 'volume';
}

class SegmentEngine {
  async processSetImage(imagePath: string): Promise<SegmentedHoldResult[]> {
    // 1. Redimensionar imagen a 640x640 manteniendo aspect ratio
    const tensorInput = await OpenCV.preprocess(imagePath, 640, 640);

    // 2. Inferencia ONNX / TFLite (YOLOv8-seg)
    const inferenceOutput = await YOLOEngine.runInference(tensorInput);

    // 3. Extracción de Máscaras y Cropping
    const holds: SegmentedHoldResult[] = [];
    for (const detection of inferenceOutput.detections) {
      if (detection.confidence > 0.75) {
        const croppedPNG = await OpenCV.extractAlphaMask(imagePath, detection.mask);
        holds.push({
          imageBytesPNG: croppedPNG,
          boundingBoxPx: detection.bounds,
          suggestedCategory: this.heuristicCategory(detection.bounds)
        });
      }
    }
    return holds;
  }
}
```

### 1.3 Contrato de Salida hacia el Backend

`SegmentedHoldResult` **no** se envía tal cual. El cliente lo traduce al DTO
canónico tras subir el PNG a S3 (§5):

| Campo `SegmentedHoldResult` | Destino en `holds` (03_DATA_MODELS.md) |
| :--- | :--- |
| `imageBytesPNG` | Se sube a S3 → la URL resultante va a `image_crop_url` |
| `boundingBoxPx` | `bounding_box_data` como `{ "width_px": N, "height_px": M }` |
| `suggestedCategory` | `type_category` (`hold_type_enum`) |
| — | `status` se omite: la BD aplica el default `'available'` |

### 1.4 Heurística de Categoría (`heuristicCategory`)

Clasificación provisional en cliente, **siempre editable por el usuario** antes
de confirmar el alta. Basada en el área y la relación de aspecto del bounding box:

```
area_cm2  = (width_px * height_px) * (scale_cm_per_px ^ 2)
aspect    = width_px / height_px

area_cm2 > 400                     -> 'volume'
area_cm2 < 25                      -> 'foothold'
aspect   > 2.5 && height_px < 40   -> 'crimp'
aspect   < 0.6                     -> 'pinch'
area_cm2 > 150                     -> 'jug'
otro                               -> 'sloper'
```

---

## 2. Módulo 2: Contrato de la API REST

### 2.1 Convenciones Transversales

* **Base URL:** `https://<host>/api/v1`
* **Content-Type:** `application/json; charset=utf-8` en todo endpoint.
  **No existen endpoints `multipart/form-data`** — los binarios van directos a
  S3 vía URL prefirmada (§5).
* **Autorización:** `Authorization: Bearer <access_token>` obligatorio salvo en
  `/auth/register`, `/auth/login` y `/auth/refresh` (RNF-4).
* **Paginación:** query `?page=1&pageSize=25` (máx. 100). Respuesta envuelta:
  `{ "data": [...], "meta": { "page": 1, "pageSize": 25, "total": 137 } }`.
* **Idempotencia:** `POST /routes` y `POST /holds/batch` aceptan la cabecera
  opcional `Idempotency-Key: <uuid>`.

### 2.2 Modelo de Error Único

Toda respuesta ≥ 400 usa exactamente esta forma:

```typescript
export interface ApiErrorResponse {
  statusCode: number;      // Espejo del status HTTP
  errorCode: string;       // Constante estable, ver tabla
  message: string;         // Texto legible (es-CO)
  details?: unknown;       // Errores de validación campo a campo
  timestamp: string;       // ISO-8601
  path: string;
}
```

| `errorCode` | HTTP | Disparador |
| :--- | :--- | :--- |
| `VALIDATION_FAILED` | 400 | `ValidationPipe` rechaza el payload |
| `UNAUTHENTICATED` | 401 | JWT ausente, expirado o inválido |
| `NOT_GYM_MEMBER` | 403 | El usuario no es `gym_setters.status = 'authorized'` del gym |
| `NOT_GYM_ADMIN` | 403 | Se exige `gym_setters.is_gym_admin = true` |
| `NOT_ROUTE_AUTHOR` | 403 | Se intenta mutar una ruta ajena (`routes.creator_id`) |
| `RESOURCE_NOT_FOUND` | 404 | El UUID no existe o queda fuera del alcance del solicitante |
| `HOLD_NOT_AVAILABLE` | 409 | Una presa del payload no está en `status = 'available'` |
| `DUPLICATE_HOLD_IN_ROUTE` | 409 | Viola `unique_hold_per_active_route` |
| `ROUTE_ALREADY_DISMANTLED` | 409 | La ruta ya está `archived_dismantled` |
| `AUTHOR_HAS_ROUTES` | 409 | Borrado bloqueado por `ON DELETE RESTRICT` |
| `EMAIL_ALREADY_REGISTERED` | 409 | Viola `users.email UNIQUE` |
| `GRADE_SYSTEM_MISMATCH` | 422 | `target_grade_id` no pertenece al sistema del muro |
| `INTERNAL_ERROR` | 500 | Fallo no clasificado |

### 2.3 Módulo Auth (`/auth`)

| Verbo | Ruta | Body | 2xx | Notas |
| :--- | :--- | :--- | :--- | :--- |
| POST | `/auth/register` | `RegisterPayload` | 201 `AuthSessionDTO` | Crea `users`; `role` por defecto `'climber'` |
| POST | `/auth/login` | `{ email, password }` | 200 `AuthSessionDTO` | |
| POST | `/auth/refresh` | `{ refreshToken }` | 200 `AuthSessionDTO` | Rotación de refresh token |
| GET | `/auth/me` | — | 200 `UserProfileDTO` | Incluye `memberships[]` |
| PATCH | `/auth/me` | `UpdateProfilePayload` | 200 `UserProfileDTO` | `username`, `displayName`, `avatarUrl` |

```typescript
export interface RegisterPayload {
  email: string;
  password: string;      // mín. 10 chars
  username: string;      // ^[a-z0-9_]{3,60}$
  displayName?: string;
}

export interface AuthSessionDTO {
  accessToken: string;   // JWT RS256, TTL 900 s
  refreshToken: string;  // TTL 30 d
  expiresIn: number;
  user: UserProfileDTO;
}

export interface GymMembershipDTO {
  gymId: string;
  gymName: string;
  status: 'pending' | 'authorized' | 'revoked';
  isGymAdmin: boolean;
}

export interface UserProfileDTO {
  id: string;
  email: string;
  username: string;
  displayName?: string;
  avatarUrl?: string;
  role: 'climber' | 'route_setter' | 'admin';
  memberships: GymMembershipDTO[];   // Habilita el KPI multi-boulder
}
```

### 2.4 Módulo Boulder Gyms (`/gyms`) — RF-1.1, RF-1.2

| Verbo | Ruta | Body | 2xx | Autorización |
| :--- | :--- | :--- | :--- | :--- |
| POST | `/gyms` | `CreateGymPayload` | 201 `BoulderGymDTO` | Autenticado; el creador queda `authorized` + `is_gym_admin` |
| GET | `/gyms` | — | 200 `BoulderGymDTO[]` | Filtros `?city=&country=&q=` |
| GET | `/gyms/:gymId` | — | 200 `BoulderGymDTO` | Público |
| PATCH | `/gyms/:gymId` | `Partial<CreateGymPayload>` | 200 `BoulderGymDTO` | `NOT_GYM_ADMIN` |

`BoulderGymDTO` es el definido en `03_DATA_MODELS.md`, sin alteraciones.

```typescript
export interface CreateGymPayload {
  name: string;
  address: string;
  city: string;
  country: string;
  phone?: string;
  email?: string;
  pricingPlans?: Record<string, any>;  // -> boulder_gyms.pricing_plans (JSONB)
  logoUrl?: string;
}
```

### 2.5 Módulo Membresías (`/gyms/:gymId/setters`) — US-01, US-04

| Verbo | Ruta | Body | 2xx | Autorización |
| :--- | :--- | :--- | :--- | :--- |
| POST | `/gyms/:gymId/setters` | `{ userId? }` | 201 `GymSetterDTO` | Sin `userId` = autopostulación → `pending`. Con `userId` = alta directa por admin → `authorized` |
| GET | `/gyms/:gymId/setters` | — | 200 `GymSetterDTO[]` | Miembro; `?status=` |
| PATCH | `/gyms/:gymId/setters/:setterId` | `{ status, isGymAdmin? }` | 200 `GymSetterDTO` | `NOT_GYM_ADMIN`. Sella `authorized_by`/`authorized_at` |

### 2.6 Módulo Sistemas de Grado (`/grade-systems`) — RF-3.2

| Verbo | Ruta | Body | 2xx | Autorización |
| :--- | :--- | :--- | :--- | :--- |
| GET | `/grade-systems` | — | 200 `GradeSystemDTO[]` | Globales + los del gym en `?gymId=` |
| POST | `/gyms/:gymId/grade-systems` | `CreateGradeSystemPayload` | 201 `GradeSystemDTO` | `NOT_GYM_ADMIN`. Escala personalizada |
| GET | `/grade-systems/:systemId/values` | — | 200 `GradeValueDTO[]` | Ordenado por `rank_ordinal` ASC |

```typescript
export interface GradeValueDTO {
  id: string;
  systemId: string;
  levelLabel: string;    // "V4", "6A"
  rankOrdinal: number;
  weightFactor: number;
}

export interface GradeSystemDTO {
  id: string;
  gymId?: string;        // null => sistema global
  name: string;
  description?: string;
  values: GradeValueDTO[];
}

export interface CreateGradeSystemPayload {
  name: string;
  description?: string;
  values: Array<Omit<GradeValueDTO, 'id' | 'systemId'>>;  // mín. 2, rankOrdinal único
}
```

### 2.7 Módulo Muros (`/walls`) — RF-3.1, US-03

| Verbo | Ruta | Body | 2xx | Autorización |
| :--- | :--- | :--- | :--- | :--- |
| POST | `/gyms/:gymId/walls` | `CreateWallPayload` | 201 `WallDTO` | Miembro autorizado |
| GET | `/gyms/:gymId/walls` | — | 200 `WallDTO[]` | Miembro, o solo `isPublic` si no lo es |
| GET | `/walls/:wallId` | — | 200 `WallDTO` | |
| PATCH | `/walls/:wallId` | `Partial<CreateWallPayload>` | 200 `WallDTO` | Creador o admin del gym |

```typescript
export interface CreateWallPayload {
  name: string;
  photoUrl: string;             // Devuelta por POST /uploads/presign
  widthCm: number;              // > 0
  heightCm: number;             // > 0
  defaultInclineDeg: number;    // -90..90, leído del giroscopio
  defaultGradeSystemId?: string;
  isPublic?: boolean;
}

export interface WallDTO extends CreateWallPayload {
  id: string;
  gymId: string;
  creatorId?: string;
  activeRoutesCount: number;    // COUNT(routes WHERE status='active')
}
```

### 2.8 Módulo Inventario (`/hold-sets`, `/holds`) — RF-2.1, RF-2.2, RF-2.3

| Verbo | Ruta | Body | 2xx | Notas |
| :--- | :--- | :--- | :--- | :--- |
| POST | `/gyms/:gymId/hold-sets` | `CreateHoldSetPayload` | 201 `HoldSetDTO` | `creatorId` = usuario del JWT |
| GET | `/gyms/:gymId/hold-sets` | — | 200 `HoldSetDTO[]` | `?colorHex=` |
| POST | `/hold-sets/:setId/holds/batch` | `{ holds: CreateHoldPayload[] }` | 201 `HoldDTO[]` | **Transaccional.** Alta masiva post-segmentación (KPI: 10 presas < 15 s) |
| GET | `/hold-sets/:setId/holds` | — | 200 `HoldDTO[]` | `?status=` |
| GET | `/gyms/:gymId/holds/available` | — | 200 `HoldDTO[]` | **RNF-3: < 500 ms.** Alimenta el editor. `?setIds=a,b,c` |
| PATCH | `/holds/:holdId` | `UpdateHoldPayload` | 200 `HoldDTO` | Solo `typeCategory`, `difficultyRatingWeight` y `status` ∈ {`maintenance`,`retired`,`available`} |

```typescript
export interface CreateHoldSetPayload {
  name: string;         // "Set Regletas Amarillas Cheeta"
  colorHex: string;     // ^#[0-9A-Fa-f]{6}$
}

export interface HoldSetDTO extends CreateHoldSetPayload {
  id: string;
  gymId: string;
  creatorId?: string;
  holdsCount: number;
  availableCount: number;
}

export interface CreateHoldPayload {
  imageCropUrl: string;                  // URL S3 del PNG con alpha
  typeCategory: HoldCategory;
  difficultyRatingWeight?: number;       // default 1.0
  boundingBoxData?: { width_px: number; height_px: number };
}

export interface HoldDTO {
  id: string;
  setId: string;
  imageCropUrl: string;
  typeCategory: HoldCategory;
  status: HoldStatus;                    // NUNCA lo fija el cliente al crear
  difficultyRatingWeight: number;
  boundingBoxData?: { width_px: number; height_px: number };
}
```

> **Restricción de negocio (RF-2.3):** `status` es de solo lectura frente a
> `'in_use'`. La API **rechaza** con `VALIDATION_FAILED` cualquier intento de
> escribir `'in_use'` o de sacar de `'in_use'` una presa por vía directa: esa
> transición es potestad exclusiva de los triggers.

### 2.9 Módulo Rutas (`/routes`) — RF-4.2, RF-4.3, US-05, US-07

| Verbo | Ruta | Body | 2xx | Autorización |
| :--- | :--- | :--- | :--- | :--- |
| POST | `/routes/generate` | `GenerateRouteRequest` | 200 `GenerateRouteProposal` | **No persiste nada.** Propuesta en RAM (RF-4.1) |
| POST | `/routes` | `RouteCreatePayload` | 201 `RouteDetailDTO` | Miembro autorizado del gym del muro |
| GET | `/walls/:wallId/routes` | — | 200 `RouteSummaryDTO[]` | `?status=active&creatorId=&gradeId=` (US-07) |
| GET | `/routes/:routeId` | — | 200 `RouteDetailDTO` | Incluye `placedHolds[]` y `creator` |
| PATCH | `/routes/:routeId` | `UpdateRoutePayload` | 200 `RouteDetailDTO` | `NOT_ROUTE_AUTHOR`. `creatorId` **inmutable** |
| POST | `/routes/:routeId/dismantle` | — | 200 `RouteDetailDTO` | Autor o admin. Libera las presas vía trigger |

`RouteCreatePayload` y `PlacedHoldDTO` son los de `03_DATA_MODELS.md`, sin
alteraciones. `creatorId` viaja en el payload por contrato, pero **el servidor
ignora su valor y usa el `sub` del JWT**; si difieren responde `403
NOT_ROUTE_AUTHOR`.

```typescript
export interface GenerateRouteRequest {
  wallId: string;
  gradeSystemId: string;
  targetGradeId: string;
  wallInclineDeg: number;
  enabledSetIds: string[];       // RF-4.1: sets habilitados
  holdCount?: number;            // default: derivado del grado
}

export interface GenerateRouteProposal {
  placedHolds: PlacedHoldDTO[];  // Sin `id`: aún no persistidas
  estimatedGradeId: string;
  rationale: string;             // Explicación human-in-the-loop
}

export interface RouteSummaryDTO {
  id: string;
  wallId: string;
  title: string;
  status: 'draft' | 'active' | 'archived_dismantled';
  wallInclineDeg: number;
  targetGrade: GradeValueDTO;
  calculatedGrade?: GradeValueDTO;
  creator: { id: string; username: string; avatarUrl?: string };  // US-07: autoría visible
  holdsCount: number;
  createdAt: string;
  dismantledAt?: string;
}

export interface RouteDetailDTO extends RouteSummaryDTO {
  placedHolds: Array<PlacedHoldDTO & { hold: HoldDTO }>;  // hold embebido: el canvas necesita el sprite
}

export interface UpdateRoutePayload {
  title?: string;
  targetGradeId?: string;
  status?: 'draft' | 'active';   // 'archived_dismantled' solo vía /dismantle
  placedHolds?: PlacedHoldDTO[]; // Reemplazo total del set
}
```

#### 2.9.1 Algoritmo de `POST /routes` (transaccional)

```
BEGIN;
  1. Verificar que wall_id existe y el JWT.sub es miembro authorized del gym.
  2. Verificar que target_grade_id pertenece al sistema del muro
     -> si no: 422 GRADE_SYSTEM_MISMATCH.
  3. SELECT ... FROM holds WHERE id = ANY($holdIds) FOR UPDATE;
     - Toda presa debe estar 'available' -> si no: 409 HOLD_NOT_AVAILABLE.
     - Toda presa debe pertenecer a un hold_set del mismo gym que el muro.
  4. INSERT INTO routes (...) con creator_id = JWT.sub.
  5. INSERT INTO placed_holds (...) en lote.
     -> trigger_mark_hold_in_use marca cada presa 'in_use' automáticamente.
  6. Calcular calculated_grade_id (§6) y UPDATE routes.
  7. RELEER el estado y construir RouteDetailDTO.
COMMIT;
```

`SELECT ... FOR UPDATE` en el paso 3 es obligatorio: sin él, dos setters
concurrentes podrían reservar la misma presa (RF-2.3).

#### 2.9.2 Algoritmo de `POST /routes/:routeId/dismantle`

```
1. Si routes.status = 'archived_dismantled' -> 409 ROUTE_ALREADY_DISMANTLED.
2. UPDATE routes SET status = 'archived_dismantled' WHERE id = $1;
   -> trigger_release_holds_dismantle devuelve las presas a 'available'
      Y sella dismantled_at. El servicio NO escribe esas columnas.
3. Releer y devolver RouteDetailDTO.
```

### 2.10 Módulo Uploads (`/uploads`)

| Verbo | Ruta | Body | 2xx |
| :--- | :--- | :--- | :--- |
| POST | `/uploads/presign` | `PresignRequest` | 201 `PresignResponse` |

```typescript
export interface PresignRequest {
  scope: 'hold_crop' | 'wall_photo' | 'gym_logo' | 'user_avatar';
  contentType: 'image/png' | 'image/jpeg';
  count?: number;              // 1..50 — un lote de presas en una sola llamada
}

export interface PresignResponse {
  uploads: Array<{
    uploadUrl: string;         // PUT prefirmado, TTL 300 s
    publicUrl: string;         // Valor a enviar luego en imageCropUrl / photoUrl
    objectKey: string;
  }>;
}
```

---

## 3. Convenciones de Serialización (Vinculante)

**La API habla camelCase; PostgreSQL habla snake_case.** La traducción ocurre en
una única capa de mapeo del backend. Ningún nombre de columna de
`03_DATA_MODELS.md` se altera jamás.

| Columna PostgreSQL | Campo DTO | Módulo |
| :--- | :--- | :--- |
| `pricing_plans` | `pricingPlans` | gyms |
| `logo_url` | `logoUrl` | gyms |
| `color_hex` | `colorHex` | hold_sets |
| `image_crop_url` | `imageCropUrl` | holds |
| `type_category` | `typeCategory` | holds |
| `difficulty_rating_weight` | `difficultyRatingWeight` | holds |
| `bounding_box_data` | `boundingBoxData` | holds |
| `wall_incline_deg` | `wallInclineDeg` | routes |
| `target_grade_id` | `targetGradeId` | routes |
| `calculated_grade_id` | `calculatedGradeId` | routes |
| `dismantled_at` | `dismantledAt` | routes |
| `x_percent` / `y_percent` | `xPercent` / `yPercent` | placed_holds |
| `rotation_deg` | `rotationDeg` | placed_holds |
| `hold_role` | **`role`** | placed_holds |

> ⚠️ **Excepción explícita:** `placed_holds.hold_role` se serializa como `role`,
> **no** como `holdRole`. Así lo fija `PlacedHoldDTO` en `03_DATA_MODELS.md`.

Los valores de los ENUM viajan como los `string` literales de PostgreSQL, sin
transformar (`foot_only`, `archived_dismantled`, `in_use`).

Los `TIMESTAMP WITH TIME ZONE` se serializan en ISO-8601 UTC
(`2026-08-31T14:03:21.000Z`). `FLOAT` viaja como `number` JSON.

---

## 4. Autenticación y Autorización

### 4.1 Payload del JWT

```typescript
export interface JwtPayload {
  sub: string;                    // users.id — única fuente de autoría
  email: string;
  role: 'climber' | 'route_setter' | 'admin';
  memberships: Array<{ gymId: string; isGymAdmin: boolean }>;  // solo 'authorized'
  iat: number;
  exp: number;
}
```

`memberships` se embebe para evitar un `SELECT` por petición (RNF-3). Como
consecuencia, revocar una membresía surte efecto al renovar el access token
(≤ 900 s). Un cambio de membresía invalida los refresh tokens del usuario.

### 4.2 Guards de NestJS

| Guard | Regla | Error |
| :--- | :--- | :--- |
| `JwtAuthGuard` | Token válido y no expirado | `UNAUTHENTICATED` |
| `GymMemberGuard` | `:gymId` ∈ `memberships` | `NOT_GYM_MEMBER` |
| `GymAdminGuard` | `:gymId` ∈ `memberships` con `isGymAdmin` | `NOT_GYM_ADMIN` |
| `RouteAuthorGuard` | `routes.creator_id = JWT.sub`, o admin del gym | `NOT_ROUTE_AUTHOR` |

**Invariante de autoría (RF-4.3):** `routes.creator_id` se escribe **una sola
vez**, desde `JWT.sub`, y ningún endpoint lo modifica. Se apoya en el
`ON DELETE RESTRICT` de la FK.

---

## 5. Pipeline de Subida a Object Storage

Subida directa cliente → S3. El backend nunca proxea binarios: es lo que hace
alcanzable el KPI de **10 presas en < 15 s**, porque las N subidas van en
paralelo sin pasar por la capa de negocio.

```
Cliente                       API                         S3
  │                            │                           │
  ├─ 1. Segmenta N presas      │                           │
  │     (CVEngine, en RAM)     │                           │
  │                            │                           │
  ├─ 2. POST /uploads/presign ─>│                          │
  │      { scope:'hold_crop',  │                           │
  │        count: N }          │                           │
  │<─── N × {uploadUrl,        │                           │
  │          publicUrl} ───────┤                           │
  │                            │                           │
  ├─ 3. PUT uploadUrl (×N, en paralelo) ──────────────────>│
  │<────────────────────── 200 OK ─────────────────────────┤
  │                            │                           │
  ├─ 4. POST /hold-sets/:id/holds/batch ─>│                │
  │      { holds:[{ imageCropUrl: publicUrl, ... }] }      │
  │<─── 201 HoldDTO[] ─────────┤                           │
```

**Convención de `objectKey`:**
`{scope}/{gymId}/{yyyy}/{MM}/{uuid}.{ext}`

**Reglas:**
* TTL de la URL prefirmada: **300 s**.
* Tamaño máximo por objeto: **8 MB** (aplicado en la política de la firma).
* El paso 4 valida que cada `imageCropUrl` pertenece al bucket y al prefijo
  `{scope}/{gymId}/`; si no, `VALIDATION_FAILED`.
* Los objetos huérfanos (paso 3 sin paso 4) los recoge un job de limpieza a las
  24 h.

---

## 6. Motor de Dificultad (`calculated_grade_id`)

Alimenta `routes.calculated_grade_id` a partir de `grade_values.weight_factor`
(RF-3.2) y `holds.difficulty_rating_weight`.

```
Entradas:
  P      = placed_holds de la ruta, excluyendo hold_role = 'foot_only'
  theta  = routes.wall_incline_deg
  S      = grade_values del sistema del muro, ordenados por rank_ordinal

1. Dificultad intrínseca de agarres:
     hold_factor = avg(h.difficulty_rating_weight for h in P)

2. Penalización por inclinación (theta en grados, desplome = positivo):
     incline_factor = 1 + (max(theta, 0) / 90) * 0.8

3. Factor de separación (distancia euclídea en % entre presas consecutivas,
   ordenadas por y_percent descendente = de abajo hacia arriba):
     avg_span   = avg(dist(p_i, p_i+1))
     span_factor = 1 + (avg_span - 18) / 60      -- 18% ~ separación cómoda
     span_factor = clamp(span_factor, 0.75, 1.6)

4. Índice compuesto:
     score = hold_factor * incline_factor * span_factor

5. Mapeo a la escala: elegir el grade_value cuyo weight_factor sea el más
   cercano a `score` dentro de S. Empate -> el rank_ordinal menor.
```

**Contrato:** el resultado es una **sugerencia**. `target_grade_id` (elección
del setter) nunca se sobrescribe — es la mitad humana del *human-in-the-loop*.
Las constantes 0.8, 18 y 60 son parámetros calibrables, no verdades del dominio.

---

## 7. Estrategia de Pruebas (TDD)

Orden obligatorio por módulo: **contrato → prueba → implementación**.

| Nivel | Herramienta | Alcance |
| :--- | :--- | :--- |
| Esquema | pgTAP (`db/tests/`) | Columnas, ENUMs, FKs, triggers |
| Unitario | Jest | Servicios con repositorios en doble de prueba. Cubre el motor de dificultad (§6) y la heurística de categoría (§1.4) |
| Integración | Jest + Testcontainers | Servicios contra PostgreSQL 15 real. **Obligatorio** en todo lo que toque `holds.status` |
| Contrato | Supertest | Verbo, status, forma del DTO y `errorCode` de cada endpoint de §2 |
| Cliente | `flutter_test` | Lógica del canvas y mapeo de DTOs |

**Casos que no pueden faltar (derivados de las reglas de negocio):**

1. `POST /routes` con una presa `in_use` → `409 HOLD_NOT_AVAILABLE`.
2. `POST /routes` deja todas sus presas `in_use` (verifica el trigger).
3. `POST /routes/:id/dismantle` devuelve todas sus presas a `available` y sella
   `dismantled_at`.
4. `POST /routes` con la misma presa dos veces → `409 DUPLICATE_HOLD_IN_ROUTE`.
5. `PATCH /routes/:id` con un `creatorId` distinto → `403 NOT_ROUTE_AUTHOR`.
6. `PATCH /holds/:id` con `status: 'in_use'` → `400 VALIDATION_FAILED`.
7. Dos `POST /routes` concurrentes sobre la misma presa: exactamente uno gana.
8. `POST /routes` con un `targetGradeId` de otro sistema → `422 GRADE_SYSTEM_MISMATCH`.
9. `GET /gyms/:id/holds/available` con 500 presas responde en < 500 ms (RNF-3).
10. Cualquier endpoint sin `Authorization` → `401 UNAUTHENTICATED`.
