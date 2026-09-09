import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/enums.dart';
import '../../models/route.dart';
import '../../models/wall.dart';
import '../../state/providers.dart';
import '../../state/session_controller.dart';
import '../../ui/canvas/route_canvas.dart';
import '../../ui/canvas/route_canvas_controller.dart';
import '../../ui/canvas/sprite_cache.dart';
import '../../ui/widgets/common.dart';
import 'route_editor_screen.dart';

final routeDetailProvider =
    FutureProvider.family<RouteDetail, String>((ref, routeId) {
  return ref.watch(routesRepositoryProvider).detail(routeId);
});

/// Ficha de un bloque — US-07: diseño, grado y autoría.
class RouteDetailScreen extends ConsumerStatefulWidget {
  const RouteDetailScreen({super.key, required this.routeId, required this.wall});

  final String routeId;
  final Wall wall;

  @override
  ConsumerState<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends ConsumerState<RouteDetailScreen> {
  final _sprites = SpriteCache();
  RouteCanvasController? _controller;
  String? _renderedRevision;
  bool _busy = false;
  bool _changed = false;

  @override
  void dispose() {
    _controller?.dispose();
    _sprites.dispose();
    super.dispose();
  }

  /// Prepara el lienzo de sólo lectura una vez por versión de la ruta.
  Future<void> _prepare(RouteDetail route) async {
    final revision = '${route.id}:${route.holdsCount}:${route.status.wire}';
    if (_renderedRevision == revision) return;
    _renderedRevision = revision;

    await _sprites.preload(
        [for (final p in route.placedHolds) p.hold.imageCropUrl]);

    final controller = RouteCanvasController(
      initial: [
        for (final p in route.placedHolds)
          EditablePlacement(hold: p.hold, placement: p.placement),
      ],
    );
    if (!mounted) {
      controller.dispose();
      return;
    }
    setState(() {
      _controller?.dispose();
      _controller = controller;
    });
  }

  Future<void> _dismantle(RouteDetail route) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Desmontar el bloque?'),
        content: const Text(
          'Las presas volverán al inventario como disponibles y el bloque '
          'quedará archivado con su autoría intacta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Desmontar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(routesRepositoryProvider).dismantle(route.id);
      _changed = true;
      ref.invalidate(routeDetailProvider(route.id));
      if (mounted) showInfo(context, 'Bloque desmontado. Presas liberadas.');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(routeDetailProvider(widget.routeId));
    final user = ref.watch(currentUserProvider);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {},
      child: Scaffold(
        appBar: AppBar(
          title: Text(async.value?.title ?? 'Bloque'),
          leading: BackButton(
            onPressed: () => Navigator.of(context).pop(_changed),
          ),
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'No se pudo cargar',
            message: describeError(error),
          ),
          data: (route) {
            _prepare(route);
            final isAuthor = user != null && user.id == route.creator.id;
            final active = route.status != RouteStatus.archivedDismantled;
            final controller = _controller;

            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
              children: [
                if (controller == null)
                  const AspectRatio(
                    aspectRatio: 1,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  RouteCanvas(
                    controller: controller,
                    sprites: _sprites,
                    wallPhotoUrl: widget.wall.photoUrl,
                    wallAspectRatio: widget.wall.aspectRatio,
                    readOnly: true,
                  ),
                const SizedBox(height: 16),
                _InfoCard(route: route),
                const SizedBox(height: 12),
                _Legend(),
                if (isAuthor && active) ...[
                  const SizedBox(height: 20),
                  FilledButton.tonalIcon(
                    onPressed: _busy
                        ? null
                        : () async {
                            final saved =
                                await Navigator.of(context).push<bool>(
                              MaterialPageRoute(
                                builder: (_) => RouteEditorScreen(
                                  wall: widget.wall,
                                  existing: route,
                                ),
                              ),
                            );
                            if (saved ?? false) {
                              _changed = true;
                              _renderedRevision = null;
                              ref.invalidate(routeDetailProvider(route.id));
                            }
                          },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar en el lienzo'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _dismantle(route),
                    icon: const Icon(Icons.layers_clear_outlined),
                    label: const Text('Desmontar y liberar presas'),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.route});

  final RouteDetail route;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(route.targetGrade.levelLabel),
                  avatar: const Icon(Icons.flag_outlined, size: 16),
                ),
                const SizedBox(width: 8),
                if (route.calculatedGrade != null)
                  Chip(
                    label: Text('estimado ${route.calculatedGrade!.levelLabel}'),
                    avatar: const Icon(Icons.calculate_outlined, size: 16),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // RF-4.3 / US-07: la autoría es inmutable y siempre visible.
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(route.creator.username),
              subtitle: const Text('Route setter'),
            ),
            Text(
              '${route.holdsCount} presas · ${route.wallInclineDeg.toStringAsFixed(1)}° · '
              '${route.status.label}',
              style: theme.textTheme.bodyMedium,
            ),
            if (route.dismantledAt != null)
              Text(
                'Desmontado el ${route.dismantledAt!.toLocal().toString().split(' ').first}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        for (final role in HoldRole.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: roleColors[role]!, width: 3),
                ),
              ),
              const SizedBox(width: 6),
              Text(role.label, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
      ],
    );
  }
}
