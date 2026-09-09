import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/api/token_store.dart';
import '../cv/color_segment_engine.dart';
import '../cv/segment_service.dart';
import '../data/auth_repository.dart';
import '../data/grades_repository.dart';
import '../data/gyms_repository.dart';
import '../data/inventory_repository.dart';
import '../data/routes_repository.dart';
import '../data/uploads_repository.dart';
import '../data/walls_repository.dart';
import 'session_controller.dart';

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    tokens: ref.watch(tokenStoreProvider),
    // Refresh token muerto: la sesión se cierra sin pedir permiso.
    onSessionExpired: () => ref.read(sessionProvider.notifier).forceLogout(),
  );
});

final authRepositoryProvider =
    Provider((ref) => AuthRepository(ref.watch(apiClientProvider)));
final gymsRepositoryProvider =
    Provider((ref) => GymsRepository(ref.watch(apiClientProvider)));
final gradesRepositoryProvider =
    Provider((ref) => GradesRepository(ref.watch(apiClientProvider)));
final wallsRepositoryProvider =
    Provider((ref) => WallsRepository(ref.watch(apiClientProvider)));
final inventoryRepositoryProvider =
    Provider((ref) => InventoryRepository(ref.watch(apiClientProvider)));
final routesRepositoryProvider =
    Provider((ref) => RoutesRepository(ref.watch(apiClientProvider)));
final uploadsRepositoryProvider =
    Provider((ref) => UploadsRepository(ref.watch(apiClientProvider)));

/// Motor de visión por computador en el dispositivo (04 §1).
final segmentServiceProvider =
    Provider<SegmentService>((ref) => const ColorSegmentEngine());
