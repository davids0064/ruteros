import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/enums.dart';
import '../../models/grade.dart';
import '../../models/hold.dart';
import '../../models/route.dart';
import '../../models/wall.dart';
import '../../state/providers.dart';
import '../../state/session_controller.dart';
import '../../ui/canvas/route_canvas.dart';
import '../../ui/canvas/route_canvas_controller.dart';
import '../../ui/canvas/sprite_cache.dart';
import '../../ui/widgets/common.dart';

/// Editor de bloques — RF-4.1, RF-4.2, RF-4.3, US-05.
///
/// Es el corazón de la co-creación: la IA propone y el setter dispone. Todo el
/// trabajo ocurre en RAM hasta que se pulsa «Publicar».
class RouteEditorScreen extends ConsumerStatefulWidget {
  const RouteEditorScreen({super.key, required this.wall, this.existing});

  final Wall wall;

  /// Si viene, se edita un bloque ya publicado en lugar de crear uno nuevo.
  final RouteDetail? existing;

  @override
  ConsumerState<RouteEditorScreen> createState() => _RouteEditorScreenState();
}

class _RouteEditorScreenState extends ConsumerState<RouteEditorScreen> {
  final _controller = RouteCanvasController();
  final _sprites = SpriteCache();

  List<Hold> _availableHolds = [];
  List<GradeSystem> _systems = [];
  Set<String> _enabledSetIds = {};

  GradeSystem? _system;
  GradeValue? _targetGrade;
  late double _incline = widget.wall.defaultInclineDeg;

  bool _loading = true;
  bool _generating = false;
  bool _publishing = false;
  String? _rationale;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _controller.dispose();
    _sprites.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final inventory = ref.read(inventoryRepositoryProvider);
      final grades = ref.read(gradesRepositoryProvider);

      final results = await Future.wait([
        inventory.available(widget.wall.gymId),
        grades.systems(gymId: widget.wall.gymId),
      ]);

      final holds = results[0] as List<Hold>;
      final systems = results[1] as List<GradeSystem>;

      // El sistema del muro manda; si no tiene, el primero disponible.
      final system = systems.firstWhere(
        (s) => s.id == widget.wall.defaultGradeSystemId,
        orElse: () => systems.isEmpty
            ? const GradeSystem(id: '', name: '', values: [])
            : systems.first,
      );

      final existing = widget.existing;
      if (existing != null) {
        _controller.replaceAll(
          [
            for (final p in existing.placedHolds)
              EditablePlacement(hold: p.hold, placement: p.placement),
          ],
          markDirty: false,
        );
        await _sprites.preload(
            [for (final p in existing.placedHolds) p.hold.imageCropUrl]);
      }

      if (!mounted) return;
      setState(() {
        _availableHolds = holds;
        _systems = systems;
        _system = system.id.isEmpty ? null : system;
        _targetGrade = existing == null
            ? null
            : system.values
                .where((v) => v.id == existing.targetGrade.id)
                .firstOrNull;
        _incline = existing?.wallInclineDeg ?? widget.wall.defaultInclineDeg;
        _enabledSetIds = {for (final h in holds) h.setId};
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      showError(context, error);
    }
  }

  Hold? _holdById(String id) {
    for (final h in _availableHolds) {
      if (h.id == id) return h;
    }
    for (final p in widget.existing?.placedHolds ?? const []) {
      if (p.hold.id == id) return p.hold;
    }
    return null;
  }

  /// RF-4.1: la propuesta base no persiste nada; llega y se pinta en el lienzo.
  Future<void> _generate() async {
    final system = _system;
    final grade = _targetGrade;
    if (system == null || grade == null) {
      showInfo(context, 'Elige el sistema y el grado objetivo.');
      return;
    }
    if (_enabledSetIds.isEmpty) {
      showInfo(context, 'Habilita al menos un set de presas.');
      return;
    }

    setState(() => _generating = true);
    try {
      final proposal = await ref.read(routesRepositoryProvider).generate(
            wallId: widget.wall.id,
            gradeSystemId: system.id,
            targetGradeId: grade.id,
            wallInclineDeg: _incline,
            enabledSetIds: _enabledSetIds.toList(),
          );

      final placements = <EditablePlacement>[];
      for (final p in proposal.placedHolds) {
        final hold = _holdById(p.holdId);
        if (hold != null) {
          placements.add(EditablePlacement(hold: hold, placement: p));
        }
      }

      await _sprites.preload([for (final p in placements) p.hold.imageCropUrl]);
      _controller.replaceAll(placements);

      if (!mounted) return;
      setState(() => _rationale = proposal.rationale);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _addHold(Hold hold) async {
    await _sprites.preload([hold.imageCropUrl]);
    _controller.add(hold);
  }

  /// RF-4.3: la ruta se firma con la autoría del setter autenticado.
  Future<void> _publish() async {
    final grade = _targetGrade;
    if (grade == null) {
      showInfo(context, 'Elige el grado objetivo antes de publicar.');
      return;
    }
    if (_controller.length < 2) {
      showInfo(context, 'Un bloque necesita al menos dos presas.');
      return;
    }

    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final title = await _askTitle();
    if (title == null) return;

    setState(() => _publishing = true);
    try {
      final repo = ref.read(routesRepositoryProvider);
      final existing = widget.existing;

      if (existing == null) {
        await repo.publish(
          wallId: widget.wall.id,
          creatorId: user.id,
          title: title,
          targetGradeId: grade.id,
          wallInclineDeg: _incline,
          placedHolds: _controller.toPayload(),
        );
      } else {
        await repo.update(
          existing.id,
          title: title,
          targetGradeId: grade.id,
          placedHolds: _controller.toPayload(),
        );
      }

      if (!mounted) return;
      _controller.markClean();
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<String?> _askTitle() {
    final controller =
        TextEditingController(text: widget.existing?.title ?? '');
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nombre del bloque'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Travesía del amanecer'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.of(context).pop(value);
            },
            child: const Text('Publicar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Nuevo bloque' : 'Editar bloque'),
        actions: [
          IconButton(
            tooltip: 'Generar propuesta',
            icon: _generating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Icon(Icons.auto_awesome),
            onPressed: _generating ? null : _generate,
          ),
        ],
      ),
      body: Column(
        children: [
          _SetupBar(
            systems: _systems,
            system: _system,
            targetGrade: _targetGrade,
            incline: _incline,
            onSystemChanged: (s) => setState(() {
              _system = s;
              _targetGrade = null;
            }),
            onGradeChanged: (g) => setState(() => _targetGrade = g),
            onInclineChanged: (v) => setState(() => _incline = v),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: RouteCanvas(
                      controller: _controller,
                      sprites: _sprites,
                      wallPhotoUrl: widget.wall.photoUrl,
                      wallAspectRatio: widget.wall.aspectRatio,
                    ),
                  ),
                  if (_rationale != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Card(
                        color: Theme.of(context).colorScheme.surfaceContainerHigh,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.auto_awesome, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _rationale!,
                                  style:
                                      Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  _SelectionBar(controller: _controller),
                  _HoldPalette(
                    holds: _availableHolds,
                    controller: _controller,
                    onPick: _addHold,
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => FilledButton.icon(
              onPressed: _publishing ? null : _publish,
              icon: _publishing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Icon(Icons.publish_outlined),
              label: Text(widget.existing == null
                  ? 'Publicar bloque (${_controller.length} presas)'
                  : 'Guardar cambios (${_controller.length} presas)'),
            ),
          ),
        ),
      ),
    );
  }
}

/// Filtros de la sesión de armado — RF-4.1.
class _SetupBar extends StatelessWidget {
  const _SetupBar({
    required this.systems,
    required this.system,
    required this.targetGrade,
    required this.incline,
    required this.onSystemChanged,
    required this.onGradeChanged,
    required this.onInclineChanged,
  });

  final List<GradeSystem> systems;
  final GradeSystem? system;
  final GradeValue? targetGrade;
  final double incline;
  final ValueChanged<GradeSystem?> onSystemChanged;
  final ValueChanged<GradeValue?> onGradeChanged;
  final ValueChanged<double> onInclineChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<GradeSystem>(
                  initialValue: system,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Sistema'),
                  items: [
                    for (final s in systems)
                      DropdownMenuItem(
                          value: s,
                          child: Text(s.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: onSystemChanged,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<GradeValue>(
                  initialValue: targetGrade,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Grado'),
                  items: [
                    for (final v in system?.values ?? const <GradeValue>[])
                      DropdownMenuItem(value: v, child: Text(v.levelLabel)),
                  ],
                  onChanged: onGradeChanged,
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.architecture, size: 18),
              const SizedBox(width: 8),
              Text('${incline.toStringAsFixed(0)}°'),
              Expanded(
                child: Slider(
                  value: incline,
                  min: -90,
                  max: 90,
                  divisions: 180,
                  onChanged: onInclineChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Acciones sobre la presa seleccionada — RF-4.2 (arrastrar, girar, reasignar).
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.controller});

  final RouteCanvasController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final selected = controller.selected;
        if (selected == null) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              'Toca una presa del lienzo para girarla o cambiarle la función.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          );
        }

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(selected.hold.typeCategory.label,
                          style: Theme.of(context).textTheme.titleSmall),
                    ),
                    IconButton(
                      tooltip: 'Quitar del bloque',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: controller.removeSelected,
                    ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final role in HoldRole.values)
                      ChoiceChip(
                        label: Text(role.label),
                        selected: selected.role == role,
                        onSelected: (_) => controller.setRoleOfSelected(role),
                      ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.rotate_right, size: 18),
                    Expanded(
                      child: Slider(
                        value: selected.rotationDeg.toDouble(),
                        max: 359,
                        divisions: 359,
                        label: '${selected.rotationDeg}°',
                        onChanged: (v) =>
                            controller.rotateSelected(v.round()),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text('${selected.rotationDeg}°',
                          textAlign: TextAlign.end),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Inventario disponible del boulder, listo para arrastrar al lienzo.
class _HoldPalette extends StatelessWidget {
  const _HoldPalette({
    required this.holds,
    required this.controller,
    required this.onPick,
  });

  final List<Hold> holds;
  final RouteCanvasController controller;
  final ValueChanged<Hold> onPick;

  @override
  Widget build(BuildContext context) {
    if (holds.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No hay presas disponibles en este boulder.'),
      );
    }

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final used = controller.usedHoldIds;
        return SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: holds.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final hold = holds[index];
              final alreadyUsed = used.contains(hold.id);
              return Opacity(
                opacity: alreadyUsed ? 0.3 : 1,
                child: InkWell(
                  onTap: alreadyUsed ? null : () => onPick(hold),
                  child: Container(
                    width: 80,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Image.network(
                      hold.imageCropUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.image_not_supported_outlined),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
