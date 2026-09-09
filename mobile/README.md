# Boulder Co-Setter — Cliente móvil

Implementación de `.specs/04_COMPONENT_SPECS.md §0.2`:
**Flutter 3.4x / Dart 3 · Riverpod · Dio · CustomPainter · sensors_plus**.

**Regla de oro (RNF-1):** no existe base de datos local. Lo único que toca el
disco es el par de tokens en `flutter_secure_storage`. Muros, rutas, presas y
perfil se rehidratan del backend en cada arranque; el editor trabaja en RAM.

## Puesta en marcha

```bash
flutter pub get

# El backend debe estar en pie (ver ../backend/README.md)
flutter run --dart-define=API_BASE_URL=http://localhost:3000/api/v1
```

En el emulador de Android la máquina anfitriona es `10.0.2.2`, no `localhost`.

Plataformas generadas: iOS, Android y macOS. Para compilar Android hace falta
instalar el SDK correspondiente (`flutter doctor` lo indica); iOS y macOS
funcionan con el Xcode ya presente.

## Builds de release

`API_BASE_URL` se inyecta en tiempo de compilación; no hay valor de producción
en el código. El arranque lo valida (`AppConfig.assertUsableInRelease`): un
release con el valor por defecto, sobre HTTP plano o apuntando a `localhost`
**falla al abrir** en vez de morir después con timeouts opacos, porque ni ATS
en iOS ni Android 9+ dejan pasar tráfico en claro.

```bash
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://<tu-app>.up.railway.app/api/v1
```

### Android — firma

`android/app/build.gradle.kts` lee las credenciales de `android/key.properties`
(fuera del repo). Sin ese fichero el release se firma con la clave de debug:
sirve para `flutter run --release`, **no es publicable**.

```bash
keytool -genkey -v -keystore ~/boulder-cosetter-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload

cp android/key.properties.example android/key.properties   # y rellenar
```

El `.jks` va fuera del repo y con copia de seguridad: si se pierde, Play deja
de aceptar actualizaciones de la app.

### iOS — permisos

`Info.plist` declara `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`
y `NSMotionUsageDescription`. Son obligatorios: sin ellos App Store rechaza el
binario y la app se cierra al abrir la cámara o leer el acelerómetro.

## Pruebas

```bash
flutter test              # unitarias y de mapeo (no necesitan red)
flutter analyze

# Flujo completo contra una API real, fuera de la suite por defecto:
flutter test test_integration --dart-define=API_BASE_URL=http://localhost:3000/api/v1
```

`test_integration/backend_flow_test.dart` recorre US-01 → US-07 de punta a
punta: alta de cuenta, registro del boulder, muro, catalogación del set,
propuesta del generador, publicación firmada, edición del lienzo y desmontaje
con liberación de inventario.

## Mapa del código

```
lib/
  core/
    api/          Dio + interceptor de Bearer, rotación de token, ApiException
    sensors/      Inclinómetro (RF-3.1)
  cv/             CVEngine: SegmentService, motor por color, heurística §1.4
  models/         DTOs del contrato REST (04 §2 y §3)
  data/           Un repositorio por módulo de la API
  state/          Proveedores Riverpod y sesión
  ui/canvas/      Lienzo 2D: controlador, painter y caché de sprites
  features/       Pantallas por historia de usuario
```

## Las tres piezas que sostienen los requisitos no funcionales

**RNF-2 — 60 FPS en el editor.** `RouteCanvasController` es un `ChangeNotifier`
que se pasa como `repaint:` al `CustomPainter`. Arrastrar una presa muta el
modelo y notifica: repinta la capa de presas dentro de un `RepaintBoundary`,
sin `setState` y sin reconstruir un solo widget. Los sprites se decodifican una
vez en `SpriteCache` antes de pintar; el bucle de `paint` sólo dibuja.

**KPI 10 presas en menos de 15 s.** `POST /uploads/presign` devuelve las N URLs
en una llamada, los PNG suben a S3 **en paralelo** sin pasar por el backend, y
el alta se cierra con un único `POST /hold-sets/:id/holds/batch` transaccional.

**RF-2.3 — reutilización de presas.** El cliente nunca escribe
`holds.status = 'in_use'`; esa transición vive en los triggers de PostgreSQL.
La UI se limita a reflejar lo que el servidor devuelve, y bloquea la edición de
estado de una presa montada.

## Flujo de co-creación (US-05)

1. El setter elige muro, sistema de grados, grado objetivo, inclinación y sets
   habilitados (RF-4.1).
2. `POST /routes/generate` devuelve una propuesta **que no persiste nada**,
   junto a la explicación de por qué es esa (`rationale`).
3. El setter arrastra, gira 0-359° y reasigna funciones (`start`, `hand`,
   `foot_only`, `top`) sobre el lienzo (RF-4.2).
4. Al publicar, la ruta queda firmada con su autoría inmutable y el servidor
   calcula el grado sugerido sin tocar el grado objetivo (RF-4.3).

## Decisiones de diseño

Las desviaciones respecto de `04 §0.2` y sus motivos están en
[`.specs/05_DECISIONS.md`](../.specs/05_DECISIONS.md), D-09 a D-12.
