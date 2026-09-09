# Registro de Decisiones (05_DECISIONS.md) — Boulder Co-Setter App

**Versión:** 1.0.0
**Estado:** DECISIONES TOMADAS DURANTE LA IMPLEMENTACIÓN DEL BACKEND
**Alcance:** huecos detectados al contrastar `01`–`04` con el código, y cómo se cerraron.

> Este documento no reemplaza a `01`–`04`: los complementa. Cada decisión cita
> el punto de la especificación que la origina y el artefacto que la implementa.

---

## D-01 — Fuga de inventario al editar o borrar una ruta

**Hueco.** `04 §2.9` define `PATCH /routes/:id` como "reemplazo total del set" de
`placedHolds`, y `routes.wall_id` es `ON DELETE CASCADE`. Ninguno de los dos
triggers de `03` reacciona al `DELETE` de `placed_holds`: la presa retirada del
lienzo quedaba `in_use` de forma permanente. Rompe RF-2.3.

**Decisión.** Nuevo trigger `AFTER DELETE ON placed_holds`
(`db/migrations/007_inventory_lifecycle_hardening.sql`). La presa vuelve a
`available` sólo si estaba `in_use` y no queda colocada en ninguna otra ruta
viva (`draft` o `active`); las rutas `archived_dismantled` conservan sus
`placed_holds` como registro histórico sin retener inventario.

**Consecuencia de contrato.** El reemplazo total debe ejecutar el `DELETE` de
las presas salientes ANTES del `INSERT` de las entrantes. Al revés, una presa
que permanece en la ruta chocaría contra `unique_hold_per_active_route`.
Implementado así en `RoutesService.update`.

**Pruebas.** `db/tests/003_placement_removal.test.sql` (H1, H2) y
`backend/test/routes.e2e-spec.ts` ("PATCH /routes/:id reemplaza el set…").

---

## D-02 — Los triggers pisaban `maintenance` y `retired`

**Hueco.** `release_holds_on_route_dismantle` ponía `'available'` sin condición:
una presa retirada por rotura mientras la ruta vivía volvía a estar disponible
al desmontar. Y `mark_hold_as_in_use` no comprobaba el estado de partida.

**Decisión.** Ambas funciones se endurecen en la migración `007`:

* la liberación filtra por `status = 'in_use'`;
* la ocupación aborta con `SQLSTATE 55006` (`object_in_use`) si la presa no
  está `available`.

`AllExceptionsFilter` traduce `55006` a `409 HOLD_NOT_AVAILABLE`, el código que
ya fijaba `04 §2.2`. Es defensa en profundidad: `RoutesService` sigue haciendo
el `SELECT … FOR UPDATE` del paso 3 de `04 §2.9.1`.

**Pruebas.** `db/tests/003_placement_removal.test.sql` (H3).

---

## D-03 — `GRADE_SYSTEM_MISMATCH` con `walls.default_grade_system_id` nulo

**Hueco.** `04 §2.9.1` exige que `target_grade_id` pertenezca "al sistema del
muro", pero esa columna es nullable y la especificación no dice qué ocurre
entonces.

**Decisión** (`GradesService.assertGradeBelongsToWallSystem`):

| Muro | Regla |
| :--- | :--- |
| Con `default_grade_system_id` | El grado debe pertenecer a ese sistema exacto. |
| Sin `default_grade_system_id` | Se acepta cualquier grado de un sistema global o del propio gym del muro. Nunca la escala privada de otro boulder. |

La misma regla gobierna qué sistema puede asignarse como defecto de un muro
(`WallsService`), y qué escala alimenta el motor de dificultad
(`RoutesService.scaleForWall`).

---

## D-04 — Invalidación de refresh tokens

**Hueco.** `04 §4.1` exige que "un cambio de membresía invalida los refresh
tokens del usuario". Un JWT firmado no se puede retirar sin estado en servidor.

**Decisión.** `users.token_version` (`db/migrations/008_refresh_token_version.sql`),
embebido como claim `tv` del refresh token.

Se incrementa **sólo cuando se recortan privilegios**: salir de `authorized`,
perder `is_gym_admin`, o borrar la membresía. Las concesiones (alta, aprobación
de una autopostulación, ascenso a admin) quedan fuera a propósito: un permiso
nuevo nunca deja un token vigente sobre-privilegiado, y cerrarle la sesión a
alguien en el momento de autorizarlo — o al fundador justo después de crear su
boulder — sería un efecto colateral absurdo.

---

## D-05 — La rotación de refresh token no rotaba

**Hueco.** `04 §2.3` describe `POST /auth/refresh` como "rotación de refresh
token". Con claims deterministas (`sub`, `tv`, `typ`) el token reemitido salía
byte a byte idéntico al entregado, y el viejo seguía vivo 30 días.

**Decisión.** El canje es de un solo uso: incrementa `token_version` en el mismo
`UPDATE … WHERE token_version = $tv`, condición que además hace atómica la
carrera entre dos canjes simultáneos. Reusar un refresh token ya canjeado
responde `401 UNAUTHENTICATED`.

**Coste aceptado.** Una sesión por dispositivo: canjear en el móvil invalida el
refresh token que tuviera abierto la web. Es el comportamiento estándar de la
rotación estricta.

---

## D-06 — Resolución de membresía: claim primero, base de datos como respaldo

**Contexto.** `04 §4.1` embebe `memberships` en el access token para evitar un
`SELECT` por petición (RNF-3), asumiendo un desfase de hasta 900 s.

**Decisión.** Los guards consultan el claim primero y **sólo** consultan
`gym_setters` cuando el claim NO concede el permiso (`MembershipService`). La
asimetría es deliberada:

* el camino feliz sigue sin tocar la base de datos (RNF-3 intacto);
* una membresía recién creada funciona sin esperar a la renovación — necesario
  para que `POST /gyms` deje operativo a su fundador;
* un usuario sin el claim jamás obtiene acceso que la base de datos no
  confirme.

El coste es un `SELECT` indexado únicamente en peticiones que iban a fallar.

**Lo que esto NO hace.** Una revocación sigue teniendo el desfase que `§4.1`
acepta: mientras el access token ya emitido conserve el claim, los guards ni
siquiera llegan al respaldo. Lo que sí es inmediato es la imposibilidad de
renovar (D-04), de modo que la ventana se cierra al expirar el token
(≤ 900 s). Hacer inmediata la revocación exigiría consultar la base de datos
en **todas** las peticiones, que es justo lo que `§4.1` descarta.

**Alcance.** La regla vive en `MembershipService` y la usan tanto los guards
(`:gymId` en la URL) como los controladores que deben resolver el boulder
dueño del recurso — inventario bajo `:setId`/`:holdId` y `POST
/uploads/presign`. Tenerla en dos sitios con dos criterios distintos era un
error real: el fundador de un boulder no podía firmar subidas ni catalogar
presas hasta que su token expirara.

---

## D-07 — `POST /uploads/presign` y el `{gymId}` de la clave

**Contexto.** `04 §5` fija `objectKey = {scope}/{gymId}/{yyyy}/{MM}/{uuid}.{ext}`,
pero `PresignRequest` (`04 §2.10`) no lleva `gymId`.

**Decisión.** Los scopes de boulder (`hold_crop`, `wall_photo`, `gym_logo`) lo
toman de `?gymId=`, exigiendo membresía autorizada. `user_avatar` no pertenece a
ningún boulder: usa el `sub` del JWT, de modo que la clave queda bajo
`user_avatar/{userId}/`. El alta de metadatos valida el prefijo
(`UploadsService.assertUrlInScope`), como exige `04 §5`.

---

## D-08 — Motor de propuesta de bloques (`POST /routes/generate`)

**Contexto.** `01 §1.2` habla de "motor de IA/reglas biomecánicas"; `04 §2.9`
define el contrato pero no el algoritmo.

**Decisión (MVP).** Generador determinista basado en reglas, que invierte el
motor de dificultad de `04 §6` para que la propuesta caiga sobre el grado
objetivo por construcción:

1. El número de presas crece con el `rankOrdinal` del grado.
2. Se eligen las presas cuyo `difficulty_rating_weight` acerca `hold_factor` al
   peso del grado, descontando el desplome del muro.
3. La separación media se despeja de `span_factor`.
4. Trazado en zigzag ascendente: alternar el lado fuerza cruces de mano y evita
   la escalera vertical.

Devuelve `rationale` en lenguaje natural (RF-4.2). No persiste nada. Sustituir
esto por un modelo entrenado no cambia el contrato REST.

---

## D-09 — Riverpod 3 en lugar de Riverpod 2

`04 §0.2` fijaba «Riverpod 2»; la resolución de dependencias entrega hoy
Riverpod 3.x. El cliente se programa contra la API `Notifier` / `AsyncNotifier`
/ `FutureProvider`, presente en ambas mayores con la misma forma, de modo que
el pin deja de ser una restricción real. Se descartaron `StateNotifier` y
`ChangeNotifierProvider`, que sí divergen entre versiones.

---

## D-10 — Cliente Dio escrito a mano, sin Retrofit

`04 §0.2` proponía «Dio + Retrofit (dart)». Retrofit para Dart es un generador
de código: exige `build_runner` y deja artefactos `.g.dart` en el árbol.

Se descartó por una razón concreta del dominio, no por comodidad: `04 §3` fija
una excepción de serialización — `placed_holds.hold_role` viaja como `role`, no
como `holdRole` — y hay más asimetrías del mismo tipo (`bounding_box_data`
conserva claves snake_case dentro del JSONB; `status` se omite al crear una
presa). Un mapeo generado esconde precisamente esas irregularidades detrás de
anotaciones; escrito a mano son visibles, comentadas y verificables con una
prueba que falla si alguien las «arregla».

Dio sigue siendo el transporte, con su interceptor de `Authorization` (RNF-4).

---

## D-11 — CVEngine: segmentación por color como implementación por defecto

`04 §1.2` describe el pipeline con YOLOv8-seg sobre ONNX Runtime. Ese camino
exige un modelo entrenado y etiquetado sobre presas de escalada, que no existe
todavía en el proyecto: sin pesos, el pipeline no es ejecutable ni testeable.

**Decisión.** `SegmentService` (§1.1) queda como el contrato, y la
implementación por defecto es `ColorSegmentEngine`: Dart puro sobre `image`,
que sigue los cinco pasos de §1.2 —redimensionado a 640, máscara, componentes
conexas, recorte con alpha, heurística de §1.4— usando como criterio de
detección el `colorHex` del set, que §1.1 ya declara como entrada y que US-02
pone en el centro del flujo ("fotos de mis sets **por color**"). Corre en un
isolate, de modo que la UI no pierde un fotograma (RNF-2).

**Lo que gana:** funciona hoy, sin descargas ni modelo embarcado, y está
cubierto por pruebas que segmentan imágenes sintéticas y verifican el canal
alpha, el filtrado de ruido y la escala del bounding box.

**Lo que cuesta:** exige un fondo contrastado y no separa colores vecinos
(naranja contra amarillo). Por eso la revisión humana previa al alta no es
opcional — que es justo lo que §1.4 ya exigía al llamar a la categoría
"siempre editable por el usuario".

**Ampliación.** Añadir `onnxruntime` y el modelo entrenado es escribir otra
clase que implemente `SegmentService` y cambiar un proveedor. Ni el contrato
REST ni la UI se enteran.

---

## D-12 — Umbral de color: la distancia debía ser una distancia

La métrica ponderada de Riemersma devuelve una suma de cuadrados. Normalizarla
sin extraer la raíz apelmaza todo el rango útil cerca de cero: con ella, un
fondo gris claro quedaba a 0.21 de un amarillo saturado, por debajo de
cualquier tolerancia razonable, y la máscara se tragaba la fotografía entera.

`colorDistance` extrae ahora la raíz y normaliza contra el máximo real del
ponderado (~649 730). Con la tolerancia por defecto de 0.25: un fondo blanco o
gris queda fuera (≈ 0.44-0.46), una presa del color del set en penumbra entra
(≈ 0.23), y los colores vecinos del círculo cromático siguen solapándose — el
límite documentado en D-11.

Lo detectó la prueba que segmenta una foto sintética de tres presas y esperaba
tres recortes: devolvía uno solo, del tamaño de la imagen completa.

---

## Pendiente de ratificación

`users`, `gym_setters`, `grade_systems`, `grade_values` y `walls` aparecen en el
ERD de `03_DATA_MODELS.md` pero su DDL sólo vive en `db/migrations/`, marcado
`[PROPUESTA — PENDIENTE DE APROBACIÓN]`. `04_COMPONENT_SPECS.md` ya las da por
buenas (guards, DTOs, endpoints) y el backend depende de ellas. Conviene
promoverlas a canónicas dentro de `03`.
