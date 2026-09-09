import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Almacenamiento del par de tokens.
///
/// RNF-1: es lo ÚNICO que este cliente persiste en disco. Ningún muro, ruta ni
/// presa toca el almacenamiento local; todo lo demás vive en RAM.
class TokenStore {
  TokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _accessKey = 'boulder.accessToken';
  static const _refreshKey = 'boulder.refreshToken';

  final FlutterSecureStorage _storage;

  String? _accessToken;
  String? _refreshToken;

  /// Cachea en memoria para no tocar el keychain en cada petición.
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;

  Future<void> load() async {
    _accessToken = await _storage.read(key: _accessKey);
    _refreshToken = await _storage.read(key: _refreshKey);
  }

  Future<void> save({required String accessToken, required String refreshToken}) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}
