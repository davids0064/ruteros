import 'package:boulder_cosetter/models/enums.dart';
import 'package:boulder_cosetter/models/hold.dart';
import 'package:boulder_cosetter/models/route.dart';
import 'package:boulder_cosetter/ui/canvas/route_canvas_controller.dart';
import 'package:flutter_test/flutter_test.dart';

Hold _hold(String id, {HoldCategory category = HoldCategory.crimp}) => Hold(
      id: id,
      setId: 's1',
      imageCropUrl: 'https://bucket/hold_crop/g1/2026/09/$id.png',
      typeCategory: category,
      status: HoldStatus.available,
      difficultyRatingWeight: 1.0,
    );

EditablePlacement _at(String id, double x, double y,
        {HoldRole role = HoldRole.hand}) =>
    EditablePlacement(
      hold: _hold(id),
      placement: PlacedHold(
        holdId: id,
        xPercent: x,
        yPercent: y,
        rotationDeg: 0,
        role: role,
      ),
    );

/// Lógica del editor de canvas — RF-4.2 y RNF-2.
void main() {
  group('selección y hit test', () {
    test('acierta la presa bajo el dedo', () {
      final c = RouteCanvasController(
        initial: [_at('a', 20, 80), _at('b', 70, 30)],
      );
      expect(c.hitTest(21, 81), 0);
      expect(c.hitTest(69, 29), 1);
    });

    test('devuelve -1 si se toca lejos de toda presa', () {
      final c = RouteCanvasController(initial: [_at('a', 20, 80)]);
      expect(c.hitTest(90, 10), -1);
    });

    test('el radio se expresa en porcentaje, no en píxeles', () {
      final c = RouteCanvasController(initial: [_at('a', 50, 50)]);
      expect(c.hitTest(54, 50, radius: 6), 0);
      expect(c.hitTest(58, 50, radius: 6), -1);
    });

    test('con presas superpuestas gana la pintada encima', () {
      final c = RouteCanvasController(
        initial: [_at('abajo', 50, 50), _at('arriba', 50, 50)],
      );
      expect(c.hitTest(50, 50), 1);
    });
  });

  group('arrastre (RF-4.2)', () {
    test('mueve la presa seleccionada por deltas porcentuales', () {
      final c = RouteCanvasController(initial: [_at('a', 50, 50)]);
      c.select(0);
      c.moveSelected(10, -5);
      expect(c.selected!.xPercent, 60);
      expect(c.selected!.yPercent, 45);
    });

    test('no deja salirse del muro: coordenadas acotadas a [0, 100]', () {
      final c = RouteCanvasController(initial: [_at('a', 5, 95)]);
      c.select(0);
      c.moveSelected(-30, 30);
      expect(c.selected!.xPercent, 0);
      expect(c.selected!.yPercent, 100);
    });

    test('sin selección el arrastre no hace nada', () {
      final c = RouteCanvasController(initial: [_at('a', 50, 50)]);
      c.moveSelected(10, 10);
      expect(c.placements.first.xPercent, 50);
    });

    test('notifica en cada movimiento: es lo que repinta el painter', () {
      final c = RouteCanvasController(initial: [_at('a', 50, 50)]);
      var notifications = 0;
      c.addListener(() => notifications++);

      c.select(0);
      c.moveSelected(1, 1);
      c.moveSelected(1, 1);
      c.moveSelected(1, 1);

      // 1 selección + 3 movimientos
      expect(notifications, 4);
    });
  });

  group('giro (RF-4.2: 360°)', () {
    test('normaliza el ángulo dentro de [0, 359]', () {
      final c = RouteCanvasController(initial: [_at('a', 50, 50)]);
      c.select(0);

      c.rotateSelected(90);
      expect(c.selected!.rotationDeg, 90);

      c.rotateSelected(360);
      expect(c.selected!.rotationDeg, 0);

      c.rotateSelected(450);
      expect(c.selected!.rotationDeg, 90);
    });
  });

  group('funciones de presa (RF-4.2)', () {
    test('reasigna la función de la presa seleccionada', () {
      final c = RouteCanvasController(initial: [_at('a', 50, 50)]);
      c.select(0);
      c.setRoleOfSelected(HoldRole.top);
      expect(c.selected!.role, HoldRole.top);
    });

    test('una presa de pie entra como foot_only', () {
      final c = RouteCanvasController();
      c.add(_hold('pie', category: HoldCategory.foothold));
      expect(c.placements.single.role, HoldRole.footOnly);
    });

    test('el resto entra como mano', () {
      final c = RouteCanvasController();
      c.add(_hold('regleta'));
      expect(c.placements.single.role, HoldRole.hand);
    });
  });

  group('integridad del bloque', () {
    test('no admite la misma presa dos veces (unique_hold_per_active_route)',
        () {
      final c = RouteCanvasController();
      c.add(_hold('a'));
      c.add(_hold('a'));
      expect(c.length, 1);
    });

    test('quitar la presa seleccionada la elimina y limpia la selección', () {
      final c = RouteCanvasController(initial: [_at('a', 20, 80), _at('b', 70, 30)]);
      c.select(0);
      c.removeSelected();
      expect(c.length, 1);
      expect(c.placements.single.holdId, 'b');
      expect(c.selected, isNull);
    });

    test('usedHoldIds refleja lo que ya está en el lienzo', () {
      final c = RouteCanvasController(initial: [_at('a', 20, 80)]);
      expect(c.usedHoldIds, {'a'});
      c.add(_hold('b'));
      expect(c.usedHoldIds, {'a', 'b'});
    });
  });

  group('payload hacia la API', () {
    test('produce PlacedHoldDTO en el orden del lienzo', () {
      final c = RouteCanvasController(
        initial: [
          _at('a', 20, 88, role: HoldRole.start),
          _at('b', 70, 12, role: HoldRole.top),
        ],
      );

      final payload = c.toPayload();
      expect(payload, hasLength(2));
      expect(payload.first.toJson()['role'], 'start');
      expect(payload.last.toJson()['role'], 'top');
      expect(payload.first.toJson()['holdId'], 'a');
    });
  });

  group('estado sin publicar', () {
    test('una ruta cargada del servidor arranca limpia', () {
      final c = RouteCanvasController();
      c.replaceAll([_at('a', 20, 80)], markDirty: false);
      expect(c.isDirty, isFalse);
    });

    test('cualquier edición la ensucia, y publicar la limpia', () {
      final c = RouteCanvasController();
      c.replaceAll([_at('a', 20, 80)], markDirty: false);

      c.select(0);
      c.rotateSelected(45);
      expect(c.isDirty, isTrue);

      c.markClean();
      expect(c.isDirty, isFalse);
    });

    test('aceptar una propuesta del generador deja cambios sin publicar', () {
      final c = RouteCanvasController();
      c.replaceAll([_at('a', 20, 80), _at('b', 70, 30)]);
      expect(c.isDirty, isTrue);
      expect(c.length, 2);
    });
  });
}
