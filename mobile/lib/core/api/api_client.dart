import 'dart:async';

import 'package:dio/dio.dart';

import '../config.dart';
import 'api_exception.dart';
import 'token_store.dart';

/// Cliente HTTP contra la API — 04 §2.1.
///
/// Responsabilidades del interceptor:
///  * inyectar `Authorization: Bearer` en toda petición (RNF-4);
///  * renovar el access token una sola vez ante un 401 y reintentar;
///  * traducir cualquier error a [ApiException] con su `errorCode` de contrato.
class ApiClient {
  ApiClient({required this.tokens, Dio? dio, this.onSessionExpired})
      : _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = AppConfig.apiBaseUrl
      ..connectTimeout = AppConfig.connectTimeout
      ..receiveTimeout = AppConfig.receiveTimeout
      ..contentType = 'application/json; charset=utf-8'
      // Los 4xx los clasificamos nosotros, no Dio.
      ..validateStatus = (status) => status != null && status < 500;

    _dio.interceptors.add(
      InterceptorsWrapper(onRequest: _onRequest, onResponse: _onResponse),
    );
  }

  final Dio _dio;
  final TokenStore tokens;

  /// Se invoca cuando el refresh token deja de valer: la sesión está muerta.
  final void Function()? onSessionExpired;

  /// La rotación de refresh token es de un solo uso (04 §2.3 / D-05): dos
  /// renovaciones en paralelo matarían la sesión. Este cerrojo las serializa.
  Future<bool>? _refreshing;

  Dio get raw => _dio;

  void _onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = tokens.accessToken;
    if (token != null && options.extra['skipAuth'] != true) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  void _onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) =>
      handler.next(response);

  Future<T> _send<T>(
    Future<Response<dynamic>> Function() call,
    T Function(dynamic body) parse, {
    bool allowRetry = true,
  }) async {
    late Response<dynamic> response;
    try {
      response = await call();
    } on DioException catch (e) {
      if (e.response != null) {
        response = e.response!;
      } else {
        throw ApiException.fromResponse(null, null);
      }
    }

    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) return parse(response.data);

    final error = ApiException.fromResponse(status, response.data);

    // Un 401 con refresh token vivo merece exactamente un reintento.
    if (error.isUnauthenticated && allowRetry && tokens.refreshToken != null) {
      final renewed = await _refreshOnce();
      if (renewed) return _send(call, parse, allowRetry: false);
    }

    if (error.isUnauthenticated) onSessionExpired?.call();
    throw error;
  }

  Future<bool> _refreshOnce() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    final refreshToken = tokens.refreshToken;
    if (refreshToken == null) return false;
    try {
      final res = await _dio.post<dynamic>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
        options: Options(extra: {'skipAuth': true}),
      );
      if (res.statusCode != 200) return false;
      final body = res.data as Map<String, dynamic>;
      await tokens.save(
        accessToken: body['accessToken'] as String,
        refreshToken: body['refreshToken'] as String,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<T> get<T>(
    String path,
    T Function(dynamic body) parse, {
    Map<String, dynamic>? query,
    bool authenticated = true,
  }) =>
      _send(
        () => _dio.get<dynamic>(
          path,
          queryParameters: _clean(query),
          options: Options(extra: {'skipAuth': !authenticated}),
        ),
        parse,
      );

  Future<T> post<T>(
    String path,
    T Function(dynamic body) parse, {
    Object? body,
    Map<String, dynamic>? query,
    bool authenticated = true,
  }) =>
      _send(
        () => _dio.post<dynamic>(
          path,
          data: body,
          queryParameters: _clean(query),
          options: Options(extra: {'skipAuth': !authenticated}),
        ),
        parse,
      );

  Future<T> patch<T>(
    String path,
    T Function(dynamic body) parse, {
    Object? body,
  }) =>
      _send(() => _dio.patch<dynamic>(path, data: body), parse);

  /// Subida directa a S3 con URL prefirmada (04 §5). Va fuera de `baseUrl` y
  /// SIN cabecera de autorización: la firma ya autoriza el PUT.
  Future<void> putPresigned(String uploadUrl, List<int> bytes, String contentType) async {
    final res = await Dio().put<dynamic>(
      uploadUrl,
      data: Stream.fromIterable([bytes]),
      options: Options(
        headers: {
          'Content-Type': contentType,
          'Content-Length': bytes.length,
        },
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw ApiException(
        statusCode: status,
        errorCode: 'UPLOAD_FAILED',
        message: 'La subida del archivo al almacenamiento falló ($status).',
      );
    }
  }

  static Map<String, dynamic>? _clean(Map<String, dynamic>? query) {
    if (query == null) return null;
    final entries = query.entries.where((e) => e.value != null);
    return entries.isEmpty ? null : Map.fromEntries(entries);
  }
}

/// Helpers de parseo compartidos por los repositorios.
List<T> parseList<T>(dynamic body, T Function(Map<String, dynamic>) fromJson) =>
    (body as List<dynamic>)
        .map((e) => fromJson(e as Map<String, dynamic>))
        .toList();

Map<String, dynamic> asMap(dynamic body) => body as Map<String, dynamic>;
