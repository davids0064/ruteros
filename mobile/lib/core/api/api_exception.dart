/// Espejo de `ApiErrorResponse` — 04 §2.2.
///
/// `errorCode` es una constante estable del contrato: la UI decide en función
/// de él, nunca del texto del mensaje.
class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.errorCode,
    required this.message,
    this.details,
  });

  final int statusCode;
  final String errorCode;
  final String message;
  final Object? details;

  bool get isUnauthenticated => errorCode == 'UNAUTHENTICATED';
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => errorCode == 'RESOURCE_NOT_FOUND';
  bool get isHoldConflict =>
      errorCode == 'HOLD_NOT_AVAILABLE' || errorCode == 'DUPLICATE_HOLD_IN_ROUTE';

  factory ApiException.fromResponse(int? status, Object? body) {
    if (body is Map && body['errorCode'] is String) {
      return ApiException(
        statusCode: (body['statusCode'] as num?)?.toInt() ?? status ?? 0,
        errorCode: body['errorCode'] as String,
        message: body['message'] as String? ?? 'Error inesperado.',
        details: body['details'],
      );
    }
    return ApiException(
      statusCode: status ?? 0,
      errorCode: 'INTERNAL_ERROR',
      message: status == null
          ? 'No hay conexión con el servidor.'
          : 'Error inesperado del servidor ($status).',
    );
  }

  /// Errores de validación campo a campo, tal como los emite el ValidationPipe.
  List<String> get fieldMessages {
    final d = details;
    if (d is! List) return const [];
    return d
        .whereType<Map>()
        .expand((e) => (e['constraints'] as Map?)?.values ?? const [])
        .map((e) => e.toString())
        .toList();
  }

  @override
  String toString() => '$errorCode ($statusCode): $message';
}
