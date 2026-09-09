import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/gym.dart';
import '../../state/providers.dart';
import '../../state/session_controller.dart';
import '../../ui/widgets/common.dart';

/// Búsqueda pública de boulders y autopostulación como setter (US-01, US-04).
final gymSearchProvider =
    FutureProvider.family<List<BoulderGym>, String>((ref, query) {
  return ref.watch(gymsRepositoryProvider).search(q: query.isEmpty ? null : query);
});

class GymSearchScreen extends ConsumerStatefulWidget {
  const GymSearchScreen({super.key});

  @override
  ConsumerState<GymSearchScreen> createState() => _GymSearchScreenState();
}

class _GymSearchScreenState extends ConsumerState<GymSearchScreen> {
  String _query = '';
  String? _joining;

  Future<void> _requestAccess(BoulderGym gym) async {
    setState(() => _joining = gym.id);
    try {
      await ref.read(gymsRepositoryProvider).requestMembership(gym.id);
      await ref.read(sessionProvider.notifier).reload();
      if (!mounted) return;
      showInfo(context,
          'Solicitud enviada. Un administrador de ${gym.name} debe autorizarte.');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _joining = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final results = ref.watch(gymSearchProvider(_query));
    final known = {for (final m in user?.memberships ?? const []) m.gymId};

    return Scaffold(
      appBar: AppBar(title: const Text('Buscar boulders')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Nombre del boulder',
                prefixIcon: Icon(Icons.search),
              ),
              onSubmitted: (value) => setState(() => _query = value.trim()),
            ),
          ),
          Expanded(
            child: results.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'No se pudo buscar',
                message: describeError(error),
              ),
              data: (gyms) => gyms.isEmpty
                  ? const EmptyState(
                      icon: Icons.travel_explore_outlined,
                      title: 'Sin resultados',
                      message: 'Prueba con otro nombre.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: gyms.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final gym = gyms[index];
                        final alreadyLinked = known.contains(gym.id);
                        return Card(
                          child: ListTile(
                            title: Text(gym.name),
                            subtitle: Text('${gym.city}, ${gym.country}'),
                            trailing: alreadyLinked
                                ? const Chip(label: Text('Vinculado'))
                                : _joining == gym.id
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2.5),
                                      )
                                    : TextButton(
                                        onPressed: () => _requestAccess(gym),
                                        child: const Text('Pedir acceso'),
                                      ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
