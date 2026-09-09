import 'dart:io';

import 'package:boulder_cosetter/core/api/api_client.dart';
import 'package:boulder_cosetter/core/api/token_store.dart';
import 'package:boulder_cosetter/data/auth_repository.dart';
import 'package:boulder_cosetter/data/grades_repository.dart';
import 'package:boulder_cosetter/data/gyms_repository.dart';
import 'package:boulder_cosetter/data/inventory_repository.dart';
import 'package:boulder_cosetter/data/routes_repository.dart';
import 'package:boulder_cosetter/data/uploads_repository.dart';
import 'package:boulder_cosetter/data/walls_repository.dart';
import 'package:boulder_cosetter/models/enums.dart';
import 'package:boulder_cosetter/models/hold.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Flujo completo del cliente contra la API real — US-01 a US-07.
///
/// Requiere el backend levantado y su PostgreSQL detrás:
/// ```
/// cd backend && node dist/main.js
/// flutter test test_integration --dart-define=API_BASE_URL=http://localhost:3000/api/v1
/// ```
/// Vive fuera de `test/` a propósito: `flutter test` no la recoge, porque
/// exige una API en pie.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // El binding de pruebas instala un HttpOverrides que corta todo tráfico real
  // devolviendo 400. Aquí queremos justo lo contrario: hablar con la API.
  HttpOverrides.global = null;

  // flutter_secure_storage habla por platform channel: en test se sustituye por
  // un mapa en memoria. Es exactamente lo único que la app guarda en disco.
  final storage = <String, String>{};
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => switch (call.method) {
        'write' => storage[call.arguments['key'] as String] =
            call.arguments['value'] as String,
        'read' => storage[call.arguments['key'] as String],
        'delete' => storage.remove(call.arguments['key'] as String),
        'readAll' => Map<String, String>.from(storage),
        'deleteAll' => storage.clear(),
        _ => null,
      },
    );
  });

  late ApiClient api;
  late String suffix;

  setUp(() {
    api = ApiClient(tokens: TokenStore());
    suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  });

  test('de la cuenta al bloque publicado y desmontado', () async {
    final auth = AuthRepository(api);
    final gyms = GymsRepository(api);
    final grades = GradesRepository(api);
    final walls = WallsRepository(api);
    final inventory = InventoryRepository(api);
    final uploads = UploadsRepository(api);
    final routes = RoutesRepository(api);

    // --- US-04: alta del setter ---------------------------------------------
    final session = await auth.register(
      email: 'flow_$suffix@test.io',
      password: 'contrasena-larga-1',
      username: 'flow_$suffix',
      displayName: 'Setter de prueba',
    );
    await api.tokens.save(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );
    expect(session.user.role, UserRole.climber);
    expect(session.user.memberships, isEmpty);

    // --- US-01: registro del boulder ----------------------------------------
    final gym = await gyms.create(
      name: 'Boulder Flow $suffix',
      address: 'Calle 1 # 2-3',
      city: 'Bogotá',
      country: 'Colombia',
      pricingPlans: {'mensual': 120000},
    );
    expect(gym.pricingPlans['mensual'], 120000);

    // El token vigente aún no lleva la membresía: se renueva.
    final renewed = await auth.me();
    expect(renewed.authorizedGyms.map((m) => m.gymId), contains(gym.id));
    expect(renewed.isAdminOf(gym.id), isTrue);

    // --- RF-3.2: escalas de grado -------------------------------------------
    final systems = await grades.systems(gymId: gym.id);
    final vScale = systems.firstWhere((s) => s.name == 'V-Scale');
    final v4 = vScale.values.firstWhere((v) => v.levelLabel == 'V4');
    expect(v4.weightFactor, 2.5);

    // --- US-03: registro del muro -------------------------------------------
    final wallPhoto = await uploads.presign(
      scope: UploadScope.wallPhoto,
      contentType: 'image/jpeg',
      gymId: gym.id,
    );
    final wall = await walls.create(
      gym.id,
      name: 'Muro Flow',
      photoUrl: wallPhoto.uploads.single.publicUrl,
      widthCm: 300,
      heightCm: 400,
      defaultInclineDeg: 25,
      defaultGradeSystemId: vScale.id,
    );
    expect(wall.activeRoutesCount, 0);
    expect(wall.aspectRatio, 0.75);

    // --- US-02: catalogación del set ----------------------------------------
    final set = await inventory.createSet(
      gym.id,
      name: 'Set Flow',
      colorHex: '#FFD700',
    );

    // Se piden las URLs prefirmadas de golpe, como hace la pantalla de
    // segmentación (04 §5). Sin credenciales de S3 no se sube el binario, pero
    // el contrato de metadatos es el mismo.
    final presigned = await uploads.presign(
      scope: UploadScope.holdCrop,
      contentType: 'image/png',
      gymId: gym.id,
      count: 6,
    );
    final slots = presigned.uploads;
    expect(slots, hasLength(6));
    expect(presigned.maxObjectBytes, greaterThan(0));
    expect(slots.first.objectKey, startsWith('hold_crop/${gym.id}/'));

    final holds = await inventory.createHolds(set.id, [
      for (var i = 0; i < slots.length; i++)
        CreateHoldPayload(
          imageCropUrl: slots[i].publicUrl,
          typeCategory: i.isEven ? HoldCategory.crimp : HoldCategory.jug,
          difficultyRatingWeight: i.isEven ? 4.0 : 1.0,
          boundingBoxData: const BoundingBox(widthPx: 120, heightPx: 80),
        ),
    ]);
    expect(holds, hasLength(6));
    expect(holds.every((h) => h.status == HoldStatus.available), isTrue);

    // RNF-3: el inventario que alimenta el editor.
    final available = await inventory.available(gym.id, setIds: [set.id]);
    expect(available, hasLength(6));

    // --- RF-4.1: propuesta del generador ------------------------------------
    final proposal = await routes.generate(
      wallId: wall.id,
      gradeSystemId: vScale.id,
      targetGradeId: v4.id,
      wallInclineDeg: 25,
      enabledSetIds: [set.id],
    );
    expect(proposal.placedHolds.length, greaterThanOrEqualTo(2));
    expect(proposal.placedHolds.last.role, HoldRole.top);
    expect(proposal.rationale, isNotEmpty);
    // No persiste nada.
    expect(await routes.byWall(wall.id), isEmpty);

    // --- US-05: publicación con autoría -------------------------------------
    final published = await routes.publish(
      wallId: wall.id,
      creatorId: session.user.id,
      title: 'Bloque Flow',
      targetGradeId: v4.id,
      wallInclineDeg: 25,
      placedHolds: proposal.placedHolds,
    );
    expect(published.creator.id, session.user.id);
    expect(published.status, RouteStatus.active);
    expect(published.calculatedGrade, isNotNull);
    expect(
      published.placedHolds.every((p) => p.hold.status == HoldStatus.inUse),
      isTrue,
      reason: 'RF-2.3: colocar una presa la marca in_use',
    );

    // --- US-07: catálogo del muro con su autoría ----------------------------
    final catalog = await routes.byWall(wall.id, status: RouteStatus.active);
    expect(catalog, hasLength(1));
    expect(catalog.single.creator.username, 'flow_$suffix');
    expect(catalog.single.targetGrade.levelLabel, 'V4');

    // --- RF-4.2: edición del lienzo -----------------------------------------
    final trimmed = published.placedHolds
        .take(2)
        .map((p) => p.placement.copyWith(rotationDeg: 45))
        .toList();
    final edited = await routes.update(published.id, placedHolds: trimmed);
    expect(edited.holdsCount, 2);
    expect(edited.placedHolds.every((p) => p.placement.rotationDeg == 45), isTrue);

    // Las presas retiradas del lienzo vuelven al inventario (migración 007).
    final afterEdit = await inventory.available(gym.id, setIds: [set.id]);
    expect(afterEdit, hasLength(4));

    // --- RF-2.3: desmontaje y liberación ------------------------------------
    final dismantled = await routes.dismantle(published.id);
    expect(dismantled.status, RouteStatus.archivedDismantled);
    expect(dismantled.dismantledAt, isNotNull);
    // La autoría sobrevive al desmontaje.
    expect(dismantled.creator.id, session.user.id);

    final afterDismantle = await inventory.available(gym.id, setIds: [set.id]);
    expect(afterDismantle, hasLength(6));
  });

  test('un no-miembro no ve el inventario ajeno (403 NOT_GYM_MEMBER)', () async {
    final auth = AuthRepository(api);
    final gyms = GymsRepository(api);
    final inventory = InventoryRepository(api);

    final owner = await auth.register(
      email: 'owner_$suffix@test.io',
      password: 'contrasena-larga-1',
      username: 'owner_$suffix',
    );
    await api.tokens.save(
      accessToken: owner.accessToken,
      refreshToken: owner.refreshToken,
    );
    final gym = await gyms.create(
      name: 'Boulder Privado $suffix',
      address: 'Calle 9',
      city: 'Medellín',
      country: 'Colombia',
    );

    final intruder = ApiClient(tokens: TokenStore());
    final intruderAuth = AuthRepository(intruder);
    final session = await intruderAuth.register(
      email: 'curioso_$suffix@test.io',
      password: 'contrasena-larga-1',
      username: 'curioso_$suffix',
    );
    await intruder.tokens.save(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );

    expect(
      () => InventoryRepository(intruder).available(gym.id),
      throwsA(isA<Object>()),
    );
    // El dueño sí lo ve.
    expect(await inventory.available(gym.id), isEmpty);
  });
}
