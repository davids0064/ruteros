import 'package:flutter/foundation.dart';

import '../../models/enums.dart';
import '../../models/hold.dart';
import '../../models/route.dart';

/// Una presa colocada en el lienzo, junto al sprite que la representa.
class EditablePlacement {
  EditablePlacement({required this.hold, required this.placement});

  final Hold hold;

  /// Mutable a propósito: durante el arrastre se reasigna en cada frame sin
  /// reconstruir la lista ni el árbol de widgets (RNF-2).
  PlacedHold placement;
  String get holdId => hold.id;
  double get xPercent => placement.xPercent;
  double get yPercent => placement.yPercent;
  int get rotationDeg => placement.rotationDeg;
  HoldRole get role => placement.role;
}

/// Estado volátil del editor de canvas — RNF-2.
///
/// Es un [ChangeNotifier] y NO un provider de Riverpod a propósito: se pasa
/// como `repaint:` al [CustomPainter], de modo que un arrastre repinta la capa
/// de presas sin reconstruir un solo widget. El estado remoto (la ruta ya
/// publicada) sí vive en Riverpod; este objeto es la mitad en RAM.
class RouteCanvasController extends ChangeNotifier {
  RouteCanvasController({List<EditablePlacement>? initial})
      : _placements = [...?initial];

  final List<EditablePlacement> _placements;
  int _selectedIndex = -1;
  bool _dirty = false;

  List<EditablePlacement> get placements => List.unmodifiable(_placements);
  int get selectedIndex => _selectedIndex;
  EditablePlacement? get selected =>
      _selectedIndex >= 0 && _selectedIndex < _placements.length
          ? _placements[_selectedIndex]
          : null;

  /// Hay cambios sin publicar.
  bool get isDirty => _dirty;
  bool get isEmpty => _placements.isEmpty;
  int get length => _placements.length;

  Set<String> get usedHoldIds => {for (final p in _placements) p.holdId};

  /// Reemplaza el contenido completo — al cargar una ruta o aceptar una
  /// propuesta de la IA.
  void replaceAll(List<EditablePlacement> placements, {bool markDirty = true}) {
    _placements
      ..clear()
      ..addAll(placements);
    _selectedIndex = -1;
    _dirty = markDirty;
    notifyListeners();
  }

  void add(Hold hold, {double xPercent = 50, double yPercent = 50}) {
    if (usedHoldIds.contains(hold.id)) return; // unique_hold_per_active_route
    _placements.add(EditablePlacement(
      hold: hold,
      placement: PlacedHold(
        holdId: hold.id,
        xPercent: xPercent,
        yPercent: yPercent,
        rotationDeg: 0,
        role: hold.typeCategory == HoldCategory.foothold
            ? HoldRole.footOnly
            : HoldRole.hand,
      ),
    ));
    _selectedIndex = _placements.length - 1;
    _dirty = true;
    notifyListeners();
  }

  void removeSelected() {
    if (_selectedIndex < 0) return;
    _placements.removeAt(_selectedIndex);
    _selectedIndex = -1;
    _dirty = true;
    notifyListeners();
  }

  void select(int index) {
    if (index == _selectedIndex) return;
    _selectedIndex = index;
    notifyListeners();
  }

  /// Presa más cercana al punto, en coordenadas porcentuales.
  /// [radius] también va en porcentaje, para que el objetivo táctil no dependa
  /// del tamaño del lienzo.
  int hitTest(double xPercent, double yPercent, {double radius = 6}) {
    var best = -1;
    var bestDistance = radius;
    // De la última a la primera: gana la pintada encima.
    for (var i = _placements.length - 1; i >= 0; i--) {
      final p = _placements[i];
      final dx = p.xPercent - xPercent;
      final dy = p.yPercent - yPercent;
      final d = (dx * dx + dy * dy);
      if (d <= bestDistance * bestDistance && (best == -1 || d < bestDistance)) {
        best = i;
        bestDistance = d <= 0 ? 0 : d;
      }
    }
    return best;
  }

  /// Arrastre (RF-4.2). Se llama en cada frame del gesto: sólo muta el modelo y
  /// notifica al painter.
  void moveSelected(double dxPercent, double dyPercent) {
    final current = selected;
    if (current == null) return;
    current.placement = current.placement.copyWith(
      xPercent: (current.xPercent + dxPercent).clamp(0.0, 100.0),
      yPercent: (current.yPercent + dyPercent).clamp(0.0, 100.0),
    );
    _dirty = true;
    notifyListeners();
  }

  /// Giro de 0° a 359° (RF-4.2).
  void rotateSelected(int degrees) {
    final current = selected;
    if (current == null) return;
    current.placement = current.placement.copyWith(rotationDeg: degrees % 360);
    _dirty = true;
    notifyListeners();
  }

  /// Reasignación de función (RF-4.2).
  void setRoleOfSelected(HoldRole role) {
    final current = selected;
    if (current == null) return;
    current.placement = current.placement.copyWith(role: role);
    _dirty = true;
    notifyListeners();
  }

  /// Payload para `POST /routes` o `PATCH /routes/:id`.
  List<PlacedHold> toPayload() => [for (final p in _placements) p.placement];

  void markClean() {
    _dirty = false;
    notifyListeners();
  }
}
