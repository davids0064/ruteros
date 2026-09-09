import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/enums.dart';
import 'route_canvas_controller.dart';
import 'sprite_cache.dart';

/// Colores por función de presa (RF-4.2).
const roleColors = {
  HoldRole.start: Color(0xFF2ECC71),
  HoldRole.hand: Color(0xFF3498DB),
  HoldRole.footOnly: Color(0xFFF1C40F),
  HoldRole.top: Color(0xFFE74C3C),
};

/// Lienzo 2D del editor — RNF-2 (60 FPS).
///
/// La clave del rendimiento está en tres decisiones:
///
///  1. el [CustomPainter] recibe el controlador como `repaint:`, así que
///     `notifyListeners()` durante un arrastre repinta **sin** llamar a
///     `setState` ni reconstruir el árbol de widgets;
///  2. todo se envuelve en un [RepaintBoundary], de modo que el repintado no
///     sube más allá de esta capa;
///  3. los sprites se decodifican UNA vez en [SpriteCache] antes de pintar: el
///     bucle de `paint` sólo hace `drawImageRect`.
class RouteCanvas extends StatelessWidget {
  const RouteCanvas({
    super.key,
    required this.controller,
    required this.sprites,
    required this.wallPhotoUrl,
    required this.wallAspectRatio,
    this.readOnly = false,
  });

  final RouteCanvasController controller;
  final SpriteCache sprites;
  final String wallPhotoUrl;
  final double wallAspectRatio;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: wallAspectRatio,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return Stack(
            fit: StackFit.expand,
            children: [
              // La foto del muro es el fondo estático: nunca se repinta durante
              // la edición.
              RepaintBoundary(
                child: Image.network(
                  wallPhotoUrl,
                  fit: BoxFit.fill,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: Color(0xFF20242B),
                    child: Center(
                      child: Icon(Icons.image_not_supported_outlined,
                          color: Colors.white24, size: 48),
                    ),
                  ),
                ),
              ),
              if (readOnly)
                RepaintBoundary(
                  child: CustomPaint(
                    painter: _PlacementsPainter(
                      controller: controller,
                      sprites: sprites,
                      showSelection: false,
                    ),
                  ),
                )
              else
                _EditableLayer(
                  controller: controller,
                  sprites: sprites,
                  size: size,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _EditableLayer extends StatelessWidget {
  const _EditableLayer({
    required this.controller,
    required this.sprites,
    required this.size,
  });

  final RouteCanvasController controller;
  final SpriteCache sprites;
  final Size size;

  double _toPercentX(double dx) => (dx / size.width) * 100;
  double _toPercentY(double dy) => (dy / size.height) * 100;

  void _onTapDown(TapDownDetails details) {
    final index = controller.hitTest(
      _toPercentX(details.localPosition.dx),
      _toPercentY(details.localPosition.dy),
    );
    controller.select(index);
  }

  void _onPanStart(DragStartDetails details) {
    final index = controller.hitTest(
      _toPercentX(details.localPosition.dx),
      _toPercentY(details.localPosition.dy),
    );
    if (index >= 0) controller.select(index);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    // Un solo `notifyListeners` por frame de gesto: sin `setState`, sin
    // reconstrucción de widgets.
    controller.moveSelected(
      _toPercentX(details.delta.dx),
      _toPercentY(details.delta.dy),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _onTapDown,
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _PlacementsPainter(
            controller: controller,
            sprites: sprites,
            showSelection: true,
          ),
        ),
      ),
    );
  }
}

class _PlacementsPainter extends CustomPainter {
  _PlacementsPainter({
    required this.controller,
    required this.sprites,
    required this.showSelection,
  }) : super(repaint: controller);

  final RouteCanvasController controller;
  final SpriteCache sprites;
  final bool showSelection;

  /// Lado del sprite como fracción del ancho del lienzo. Mantiene las presas
  /// proporcionadas al muro sea cual sea el tamaño de la pantalla.
  static const _spriteWidthFactor = 0.11;

  @override
  void paint(Canvas canvas, Size size) {
    final placements = controller.placements;
    final selectedIndex = controller.selectedIndex;
    final baseWidth = size.width * _spriteWidthFactor;

    for (var i = 0; i < placements.length; i++) {
      final p = placements[i];
      final center = Offset(
        size.width * p.xPercent / 100,
        size.height * p.yPercent / 100,
      );

      final image = sprites[p.hold.imageCropUrl];
      final aspect = p.hold.boundingBoxData?.aspect ??
          (image == null ? 1.0 : image.width / image.height);
      final spriteSize = Size(baseWidth, baseWidth / (aspect <= 0 ? 1 : aspect));

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(p.rotationDeg * math.pi / 180);

      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: spriteSize.width,
        height: spriteSize.height,
      );

      if (image != null) {
        _drawSprite(canvas, image, rect);
      } else {
        // Todavía sin decodificar: se dibuja un marcador con el color del rol
        // para que el bloque siga siendo legible.
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          Paint()..color = roleColors[p.role]!.withValues(alpha: 0.35),
        );
      }
      canvas.restore();

      _drawRoleRing(
        canvas,
        center,
        math.max(spriteSize.width, spriteSize.height) / 2 + 4,
        p.role,
        selected: showSelection && i == selectedIndex,
      );
    }
  }

  void _drawSprite(Canvas canvas, ui.Image image, Rect rect) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  void _drawRoleRing(
    Canvas canvas,
    Offset center,
    double radius,
    HoldRole role, {
    required bool selected,
  }) {
    final color = roleColors[role]!;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 4 : 2.5
        ..color = color,
    );

    if (selected) {
      canvas.drawCircle(
        center,
        radius + 5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: 0.9),
      );
    }

    // La salida y el top se marcan siempre: son los que definen el bloque.
    if (role == HoldRole.start || role == HoldRole.top) {
      final painter = TextPainter(
        text: TextSpan(
          text: role == HoldRole.start ? 'S' : 'TOP',
          style: TextStyle(
            color: Colors.white,
            fontSize: radius * 0.6,
            fontWeight: FontWeight.w800,
            shadows: const [Shadow(blurRadius: 3, color: Colors.black87)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        center + Offset(radius * 0.7, -radius - painter.height * 0.5),
      );
    }
  }

  /// El repintado lo dispara el `repaint:` del constructor. Devolver `false`
  /// evita repintados redundantes cuando Flutter recrea el painter.
  @override
  bool shouldRepaint(_PlacementsPainter oldDelegate) =>
      oldDelegate.controller != controller ||
      oldDelegate.sprites != sprites ||
      oldDelegate.showSelection != showSelection;
}
