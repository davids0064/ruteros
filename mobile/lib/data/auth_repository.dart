import '../core/api/api_client.dart';
import '../models/auth.dart';

/// Módulo Auth — 04 §2.3.
class AuthRepository {
  const AuthRepository(this._api);

  final ApiClient _api;

  Future<AuthSession> register({
    required String email,
    required String password,
    required String username,
    String? displayName,
  }) =>
      _api.post(
        '/auth/register',
        (b) => AuthSession.fromJson(asMap(b)),
        authenticated: false,
        body: {
          'email': email,
          'password': password,
          'username': username,
          if (displayName != null && displayName.isNotEmpty)
            'displayName': displayName,
        },
      );

  Future<AuthSession> login({required String email, required String password}) =>
      _api.post(
        '/auth/login',
        (b) => AuthSession.fromJson(asMap(b)),
        authenticated: false,
        body: {'email': email, 'password': password},
      );

  Future<UserProfile> me() =>
      _api.get('/auth/me', (b) => UserProfile.fromJson(asMap(b)));

  Future<UserProfile> updateProfile({
    String? username,
    String? displayName,
    String? avatarUrl,
  }) =>
      _api.patch('/auth/me', (b) => UserProfile.fromJson(asMap(b)), body: {
        'username': ?username,
        'displayName': ?displayName,
        'avatarUrl': ?avatarUrl,
      });
}
