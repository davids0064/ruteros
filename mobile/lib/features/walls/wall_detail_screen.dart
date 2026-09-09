import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/enums.dart';
import '../../models/route.dart';
import '../../models/wall.dart';
import '../../state/providers.dart';
import '../../state/session_controller.dart';
import '../../ui/widgets/common.dart';
import '../routes/route_detail_screen.dart';
import '../routes/route_editor_screen.dart';

typedef _CatalogKey = ({String wallId, RouteStatus? status});

/// Catálogo de bloques de un muro — US-07.
final wallRoutesProvider =
    FutureProvider.family<List<RouteSummary>, _CatalogKey>((ref, key) {
  return ref.watch(routesRepositoryProvider).byWall(key.wallId, status: key.status);
});

class WallDetailScreen extends ConsumerStatefulWidget {
  const WallDetailScreen({super.key, required this.wall});

  final Wall wall;

  @override
  ConsumerState<WallDetailScreen> createState() => _WallDetailScreenState();
}

class _WallDetailScreenState extends ConsumerState<WallDetailScreen> {
  RouteStatus? _filter = RouteStatus.active;

  _CatalogKey get _key => (wallId: widget.wall.id, status: _filter);

  @override
  Widget build(BuildContext context) {
    final routes = ref.watch(wallRoutesProvider(_key));
    final user = ref.watch(currentUserProvider);
    final canSet = user != null;

    return Scaffold(
      appBar: AppBar(title: Text(widget.wall.name)),
      floatingActionButton: !canSet
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                final published = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => RouteEditorScreen(wall: widget.wall),
                  ),
                );
                if (published ?? false) ref.invalidate(wallRoutesProvider(_key));
              },
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Nuevo bloque'),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.wall.defaultInclineDeg.toStringAsFixed(1)}° · '
                    '${widget.wall.activeRoutesCount} montados',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                SegmentedButton<RouteStatus?>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                        value: RouteStatus.active, label: Text('Montados')),
                    ButtonSegment(value: null, label: Text('Todos')),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (v) => setState(() => _filter = v.first),
                ),
              ],
            ),
          ),
          Expanded(
            child: routes.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'No se pudo cargar',
                message: describeError(error),
              ),
              data: (list) => list.isEmpty
                  ? const EmptyState(
                      icon: Icons.route_outlined,
                      title: 'Sin bloques todavía',
                      message: 'Crea el primero con la ayuda del generador.',
                    )
                  : RefreshIndicator(
                      onRefresh: () async =>
                          ref.invalidate(wallRoutesProvider(_key)),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) => _RouteTile(
                          route: list[index],
                          wall: widget.wall,
                          onChanged: () =>
                              ref.invalidate(wallRoutesProvider(_key)),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteTile extends StatelessWidget {
  const _RouteTile({
    required this.route,
    required this.wall,
    required this.onChanged,
  });

  final RouteSummary route;
  final Wall wall;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dismantled = route.status == RouteStatus.archivedDismantled;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: dismantled
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.primaryContainer,
          child: Text(
            route.targetGrade.levelLabel,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: dismantled
                  ? theme.colorScheme.outline
                  : theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        title: Text(route.title),
        subtitle: Text(
          // US-07: quién lo diseñó siempre a la vista.
          'por ${route.creator.username} · ${route.holdsCount} presas'
          '${route.calculatedGrade == null ? '' : ' · estimado ${route.calculatedGrade!.levelLabel}'}',
        ),
        trailing: dismantled
            ? const Chip(label: Text('Desmontado'))
            : const Icon(Icons.chevron_right),
        onTap: () async {
          final changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => RouteDetailScreen(routeId: route.id, wall: wall),
            ),
          );
          if (changed ?? false) onChanged();
        },
      ),
    );
  }
}
