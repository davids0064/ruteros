import 'package:flutter/foundation.dart';

/// Configuración de entorno.
///
/// Se inyecta en tiempo de compilación:
/// `flutter build apk --release --dart-define=API_BASE_URL=https://api.midominio.com/api/v1`
class AppConfig {
  const AppConfig._();

  /// Por defecto apunta al backend local. En Android el emulador ve la máquina
  /// anfitriona en 10.0.2.2, no en localhost.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000/api/v1',
  );

  static const connectTimeout = Duration(seconds: 10);
  static const receiveTimeout = Duration(seconds: 20);

  /// 04 §5: TTL de la URL prefirmada. Si la subida no arranca antes, se vuelve
  /// a firmar en lugar de reintentar contra una URL caducada.
  static const presignTtl = Duration(seconds: 300);

  /// Un release que se lleve el valor por defecto no habla con nadie: en el
  /// móvil no hay «localhost». Y sobre HTTP plano las plataformas bloquean el
  /// tráfico (ATS en iOS, cleartext en Android 9+), así que el fallo llegaría
  /// como un timeout opaco en producción en vez de aquí.
  static void assertUsableInRelease() {
    if (kDebugMode || kProfileMode) return;

    final uri = Uri.tryParse(apiBaseUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError('API_BASE_URL no es una URL válida: «$apiBaseUrl».');
    }
    if (uri.scheme != 'https') {
      throw StateError(
        'API_BASE_URL debe ser https en release; recibido «$apiBaseUrl». '
        'Compila con --dart-define=API_BASE_URL=https://<tu-app>.up.railway.app/api/v1',
      );
    }
    if (uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '10.0.2.2') {
      throw StateError(
        'API_BASE_URL apunta a la máquina de desarrollo («${uri.host}»), '
        'inalcanzable desde un dispositivo. Pásalo con --dart-define.',
      );
    }
  }
}
