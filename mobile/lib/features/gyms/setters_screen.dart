import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/enums.dart';
import '../../models/gym.dart';
import '../../state/providers.dart';
import '../../ui/widgets/common.dart';

/// Setters del boulder — 04 §2.5 (US-01: "routers autorizados por el boulder").
final gymSettersProvider =
    FutureProvider.family<List<GymSetter>, String>((ref, gymId) {
  return ref.watch(gymsRepositoryProvider).setters(gymId);
});

class SettersTab extends ConsumerWidget {
  const SettersTab({super.key, required this.gymId, required this.isAdmin});

  final String gymId;
  final bool isAdmin;

  Future<void> _update(
    BuildContext context,
    WidgetRef ref,
    GymSetter setter, {
    MembershipStatus? status,
    bool? isGymAdmin,
  }) async {
    try {
      await ref.read(gymsRepositoryProvider).updateMembership(
            gymId,
            setter.id,
            status: status,
            isGymAdmin: isGymAdmin,
          );
      ref.invalidate(gymSettersProvider(gymId));
      if (context.mounted) showInfo(context, 'Membresía actualizada.');
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setters = ref.watch(gymSettersProvider(gymId));

    return setters.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'No se pudo cargar',
        message: describeError(error),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyState(
            icon: Icons.groups_outlined,
            title: 'Sin setters todavía',
            message: 'Cuando alguien pida acceso aparecerá aquí.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(gymSettersProvider(gymId)),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final setter = list[index];
              return Card(
                child: ListTile(
                  title: Text(setter.shownName),
                  subtitle: Wrap(
                    spacing: 6,
                    children: [
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(setter.status.label),
                      ),
                      if (setter.isGymAdmin)
                        const Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text('Admin'),
                        ),
                    ],
                  ),
                  trailing: !isAdmin
                      ? null
                      : PopupMenuButton<String>(
                          onSelected: (action) => switch (action) {
                            'authorize' => _update(context, ref, setter,
                                status: MembershipStatus.authorized),
                            'revoke' => _update(context, ref, setter,
                                status: MembershipStatus.revoked),
                            'admin' => _update(context, ref, setter,
                                isGymAdmin: !setter.isGymAdmin),
                            _ => null,
                          },
                          itemBuilder: (context) => [
                            if (setter.status != MembershipStatus.authorized)
                              const PopupMenuItem(
                                value: 'authorize',
                                child: Text('Autorizar'),
                              ),
                            if (setter.status == MembershipStatus.authorized)
                              const PopupMenuItem(
                                value: 'revoke',
                                child: Text('Revocar'),
                              ),
                            PopupMenuItem(
                              value: 'admin',
                              child: Text(setter.isGymAdmin
                                  ? 'Quitar administrador'
                                  : 'Hacer administrador'),
                            ),
                          ],
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
