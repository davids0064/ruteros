import 'dart:convert';

import 'package:boulder_cosetter/models/auth.dart';
import 'package:boulder_cosetter/models/enums.dart';
import 'package:boulder_cosetter/models/gym.dart';
import 'package:boulder_cosetter/models/hold.dart';
import 'package:boulder_cosetter/models/route.dart';
import 'package:boulder_cosetter/models/wall.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mapeo de DTOs — 04_COMPONENT_SPECS.md §3.
///
/// La API habla camelCase; los ENUM viajan como los literales de PostgreSQL.
void main() {
  group('ENUMs (04 §3: literales sin transformar)', () {
    test('hold_status_enum', () {
      expect(HoldStatus.inUse.wire, 'in_use');
      expect(HoldStatus.fromWire('in_use'), HoldStatus.inUse);
      expect(HoldStatus.fromWire('maintenance'), HoldStatus.maintenance);
    });

    test('hold_role_enum', () {
      expect(HoldRole.footOnly.wire, 'foot_only');
      expect(HoldRole.fromWire('foot_only'), HoldRole.footOnly);
    });

    test('route_status_enum', () {
      expect(RouteStatus.archivedDismantled.wire, 'archived_dismantled');
      expect(RouteStatus.fromWire('archived_dismantled'),
          RouteStatus.archivedDismantled);
    });

    test('user_role_enum', () {
      expect(UserRole.routeSetter.wire, 'route_setter');
    });

    test('todos los valores de hold_type_enum hacen ida y vuelta', () {
      for (final c in HoldCategory.values) {
        expect(HoldCategory.fromWire(c.wire), c);
      }
    });

    test('in_use no está entre los estados que el cliente puede fijar', () {
      // 04 §2.8: esa transición es potestad exclusiva de los triggers.
      expect(HoldStatus.clientSettable, isNot(contains(HoldStatus.inUse)));
    });
  });

  group('PlacedHoldDTO', () {
    const raw = '''
    {
      "id": "11111111-1111-1111-1111-111111111111",
      "holdId": "22222222-2222-2222-2222-222222222222",
      "xPercent": 35.5,
      "yPercent": 90.0,
      "rotationDeg": 180,
      "role": "foot_only"
    }''';

    test('deserializa `role`, la excepción explícita de §3', () {
      final placed =
          PlacedHold.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      expect(placed.role, HoldRole.footOnly);
      expect(placed.xPercent, 35.5);
      expect(placed.rotationDeg, 180);
    });

    test('serializa como `role`, nunca como `holdRole`', () {
      final json = PlacedHold.fromJson(jsonDecode(raw) as Map<String, dynamic>)
          .toJson();
      expect(json['role'], 'foot_only');
      expect(json.containsKey('holdRole'), isFalse);
      expect(json.containsKey('hold_role'), isFalse);
    });

    test('el `id` no viaja de vuelta: el reemplazo total recrea las filas', () {
      final json = PlacedHold.fromJson(jsonDecode(raw) as Map<String, dynamic>)
          .toJson();
      expect(json.containsKey('id'), isFalse);
    });

    test('copyWith conserva la identidad de la presa', () {
      final placed =
          PlacedHold.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      final moved = placed.copyWith(xPercent: 10, role: HoldRole.top);
      expect(moved.holdId, placed.holdId);
      expect(moved.yPercent, placed.yPercent);
      expect(moved.xPercent, 10);
      expect(moved.role, HoldRole.top);
    });
  });

  group('HoldDTO', () {
    test('boundingBoxData conserva las claves snake_case del JSONB', () {
      final hold = Hold.fromJson({
        'id': 'h1',
        'setId': 's1',
        'imageCropUrl': 'https://bucket/hold_crop/g1/2026/09/a.png',
        'typeCategory': 'crimp',
        'status': 'available',
        'difficultyRatingWeight': 2.5,
        'boundingBoxData': {'width_px': 120, 'height_px': 80},
      });

      expect(hold.boundingBoxData!.widthPx, 120);
      expect(hold.boundingBoxData!.heightPx, 80);
      expect(hold.boundingBoxData!.aspect, 1.5);
      expect(hold.status, HoldStatus.available);
    });

    test('CreateHoldPayload omite `status`: lo pone el default de la BD', () {
      final json = const CreateHoldPayload(
        imageCropUrl: 'https://bucket/hold_crop/g1/2026/09/a.png',
        typeCategory: HoldCategory.sloper,
      ).toJson();

      expect(json.containsKey('status'), isFalse);
      expect(json['typeCategory'], 'sloper');
      expect(json.containsKey('difficultyRatingWeight'), isFalse);
    });
  });

  group('RouteDetailDTO', () {
    final raw = {
      'id': 'r1',
      'wallId': 'w1',
      'title': 'Travesía del amanecer',
      'status': 'active',
      'wallInclineDeg': 25.0,
      'targetGrade': {
        'id': 'g4',
        'systemId': 'sys',
        'levelLabel': 'V4',
        'rankOrdinal': 4,
        'weightFactor': 2.5,
      },
      'calculatedGrade': {
        'id': 'g5',
        'systemId': 'sys',
        'levelLabel': 'V5',
        'rankOrdinal': 5,
        'weightFactor': 3.0,
      },
      'creator': {'id': 'u1', 'username': 'setter1'},
      'holdsCount': 1,
      'createdAt': '2026-08-31T14:03:21.000Z',
      'placedHolds': [
        {
          'id': 'p1',
          'holdId': 'h1',
          'xPercent': 20.0,
          'yPercent': 88.0,
          'rotationDeg': 0,
          'role': 'start',
          'hold': {
            'id': 'h1',
            'setId': 's1',
            'imageCropUrl': 'https://bucket/hold_crop/g1/2026/09/a.png',
            'typeCategory': 'jug',
            'status': 'in_use',
            'difficultyRatingWeight': 1.0,
          },
        },
      ],
    };

    test('embebe el sprite de cada presa: el canvas no hace un segundo viaje',
        () {
      final route = RouteDetail.fromJson(raw);
      expect(route.placedHolds, hasLength(1));
      expect(route.placedHolds.first.hold.typeCategory, HoldCategory.jug);
      expect(route.placedHolds.first.hold.status, HoldStatus.inUse);
      expect(route.placedHolds.first.placement.role, HoldRole.start);
    });

    test('conserva la autoría y ambos grados (US-07)', () {
      final route = RouteDetail.fromJson(raw);
      expect(route.creator.username, 'setter1');
      expect(route.targetGrade.levelLabel, 'V4');
      expect(route.calculatedGrade!.levelLabel, 'V5');
    });

    test('las marcas de tiempo son ISO-8601 UTC', () {
      final route = RouteDetail.fromJson(raw);
      expect(route.createdAt.isUtc, isTrue);
      expect(route.createdAt.year, 2026);
      expect(route.dismantledAt, isNull);
    });
  });

  group('UserProfileDTO', () {
    final raw = {
      'id': 'u1',
      'email': 'setter@test.io',
      'username': 'setter1',
      'role': 'route_setter',
      'memberships': [
        {
          'gymId': 'g1',
          'gymName': 'Boulder Uno',
          'status': 'authorized',
          'isGymAdmin': true,
        },
        {
          'gymId': 'g2',
          'gymName': 'Boulder Dos',
          'status': 'pending',
          'isGymAdmin': false,
        },
      ],
    };

    test('KPI multi-boulder: sólo cuentan las membresías autorizadas', () {
      final user = UserProfile.fromJson(raw);
      expect(user.memberships, hasLength(2));
      expect(user.authorizedGyms, hasLength(1));
      expect(user.authorizedGyms.single.gymId, 'g1');
      expect(user.isAdminOf('g1'), isTrue);
      expect(user.isAdminOf('g2'), isFalse);
    });

    test('sin displayName cae al username', () {
      expect(UserProfile.fromJson(raw).shownName, 'setter1');
    });
  });

  group('BoulderGymDTO y WallDTO', () {
    test('pricingPlans llega como mapa libre (JSONB)', () {
      final gym = BoulderGym.fromJson({
        'id': 'g1',
        'name': 'Boulder Uno',
        'address': 'Calle 1',
        'city': 'Bogotá',
        'country': 'Colombia',
        'pricingPlans': {'mensual': 120000, 'dia': 20000},
      });
      expect(gym.pricingPlans['mensual'], 120000);
      expect(gym.phone, isNull);
    });

    test('el muro expone su relación de aspecto física', () {
      final wall = Wall.fromJson({
        'id': 'w1',
        'gymId': 'g1',
        'name': 'Muro A',
        'photoUrl': 'https://bucket/wall_photo/g1/2026/09/a.png',
        'widthCm': 300.0,
        'heightCm': 400.0,
        'defaultInclineDeg': 25.0,
        'isPublic': false,
        'activeRoutesCount': 3,
      });
      expect(wall.aspectRatio, 0.75);
      expect(wall.activeRoutesCount, 3);
    });
  });

  group('GymSetterDTO', () {
    test('mapea el sello de autorización', () {
      final setter = GymSetter.fromJson({
        'id': 'm1',
        'gymId': 'g1',
        'userId': 'u2',
        'username': 'aspirante',
        'status': 'authorized',
        'isGymAdmin': false,
        'authorizedBy': 'u1',
        'authorizedAt': '2026-08-31T14:03:21.000Z',
        'createdAt': '2026-08-30T10:00:00.000Z',
      });
      expect(setter.status, MembershipStatus.authorized);
      expect(setter.authorizedBy, 'u1');
      expect(setter.authorizedAt!.isUtc, isTrue);
    });
  });
}
