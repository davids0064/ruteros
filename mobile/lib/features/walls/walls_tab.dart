import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/wall.dart';
import '../../state/providers.dart';
import '../../ui/widgets/common.dart';
import 'wall_detail_screen.dart';
import 'wall_form_screen.dart';

final gymWallsProvider = FutureProvider.family<List<Wall>, String>((ref, gymId) {
  return ref.watch(wallsRepositoryProvider).byGym(gymId);
});

/// Muros del boulder — RF-3.1, US-03.
class WallsTab extends ConsumerWidget {
  const WallsTab({super.key, required this.gymId});

  final String gymId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walls = ref.watch(gymWallsProvider(gymId));

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => WallFormScreen(gymId: gymId)),
          );
          if (created ?? false) ref.invalidate(gymWallsProvider(gymId));
        },
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Registrar muro'),
      ),
      body: walls.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'No se pudo cargar',
          message: describeError(error),
        ),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.grid_off_outlined,
                title: 'Sin muros registrados',
                message:
                    'Fotografía el muro y captura su inclinación con el giroscopio.',
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(gymWallsProvider(gymId)),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final wall = list[index];
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => WallDetailScreen(wall: wall),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AspectRatio(
                              aspectRatio: wall.aspectRatio,
                              child: Image.network(
                                wall.photoUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const ColoredBox(
                                  color: Color(0xFF20242B),
                                  child: Center(
                                    child: Icon(Icons.image_not_supported_outlined,
                                        color: Colors.white24),
                                  ),
                                ),
                              ),
                            ),
                            ListTile(
                              title: Text(wall.name),
                              subtitle: Text(
                                '${wall.defaultInclineDeg.toStringAsFixed(1)}° · '
                                '${wall.widthCm.toStringAsFixed(0)}×${wall.heightCm.toStringAsFixed(0)} cm · '
                                '${wall.activeRoutesCount} bloques montados',
                              ),
                              trailing: Icon(wall.isPublic
                                  ? Icons.public
                                  : Icons.lock_outline),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
