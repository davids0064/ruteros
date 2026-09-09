import 'dart:typed_data';

import '../core/api/api_client.dart';
import '../core/api/api_exception.dart';
import '../models/enums.dart';

/// `PresignResponse.uploads[i]` — 04 §2.10.
class PresignResult {
  const PresignResult({required this.uploads, required this.maxObjectBytes});

  final List<PresignedUpload> uploads;

  /// `S3_MAX_OBJECT_BYTES` del servidor. La URL prefirmada no puede exigir el
  /// tamaño —firmar `Content-Length` obligaría a subir exactamente ese número
  /// de bytes—, así que el tope se aplica aquí, antes del PUT.
  final int maxObjectBytes;

  factory PresignResult.fromJson(Map<String, dynamic> json) => PresignResult(
        uploads: parseList(
            json['uploads'] as List<dynamic>, PresignedUpload.fromJson),
        maxObjectBytes: (json['maxObjectBytes'] as num?)?.toInt() ?? 8 * 1024 * 1024,
      );
}

class PresignedUpload {
  const PresignedUpload({
    required this.uploadUrl,
    required this.publicUrl,
    required this.objectKey,
  });

  final String uploadUrl;
  final String publicUrl;
  final String objectKey;

  factory PresignedUpload.fromJson(Map<String, dynamic> json) => PresignedUpload(
        uploadUrl: json['uploadUrl'] as String,
        publicUrl: json['publicUrl'] as String,
        objectKey: json['objectKey'] as String,
      );
}

/// Módulo Uploads — 04 §2.10 y §5.
///
/// El backend nunca proxea binarios: los PNG van del cliente a S3 en paralelo.
/// Es lo que hace alcanzable el KPI de 10 presas en menos de 15 segundos.
class UploadsRepository {
  const UploadsRepository(this._api);

  final ApiClient _api;

  Future<PresignResult> presign({
    required UploadScope scope,
    required String contentType,
    String? gymId,
    int count = 1,
  }) =>
      _api.post(
        '/uploads/presign',
        (b) => PresignResult.fromJson(asMap(b)),
        query: {'gymId': gymId},
        body: {
          'scope': scope.wire,
          'contentType': contentType,
          if (count != 1) 'count': count,
        },
      );

  /// Sube N objetos EN PARALELO y devuelve sus URLs públicas, en el mismo orden
  /// que los bytes recibidos.
  Future<List<String>> uploadAll({
    required UploadScope scope,
    required List<Uint8List> files,
    required String contentType,
    String? gymId,
  }) async {
    if (files.isEmpty) return const [];

    final result = await presign(
      scope: scope,
      contentType: contentType,
      gymId: gymId,
      count: files.length,
    );

    // Se comprueba el lote entero antes de subir nada: mejor fallar sin haber
    // escrito que dejar la mitad de las presas en el almacenamiento.
    final oversized = files.where((f) => f.length > result.maxObjectBytes).length;
    if (oversized > 0) {
      final limitMb = (result.maxObjectBytes / (1024 * 1024)).toStringAsFixed(1);
      throw ApiException(
        statusCode: 0,
        errorCode: 'UPLOAD_TOO_LARGE',
        message: oversized == 1
            ? 'Una imagen supera el límite de $limitMb MB.'
            : '$oversized imágenes superan el límite de $limitMb MB.',
      );
    }

    final slots = result.uploads;
    await Future.wait([
      for (var i = 0; i < files.length; i++)
        _api.putPresigned(slots[i].uploadUrl, files[i], contentType),
    ]);

    return [for (final slot in slots) slot.publicUrl];
  }
}
