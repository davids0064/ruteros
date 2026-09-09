import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/hold.dart';
import '../../state/providers.dart';
import '../../ui/widgets/common.dart';
import 'segmentation_screen.dart';
import 'set_holds_screen.dart';

final holdSetsProvider =
    FutureProvider.family<List<HoldSet>, String>((ref, gymId) {
  return ref.watch(inventoryRepositoryProvider).sets(gymId);
});

/// Inventario del boulder — RF-2.1, RF-2.2, RF-2.3.
class HoldSetsTab extends ConsumerWidget {
  const HoldSetsTab({super.key, required this.gymId});

  final String gymId;

  Future<void> _createSet(BuildContext context, WidgetRef ref) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewSetSheet(gymId: gymId),
    );
    if (created ?? false) ref.invalidate(holdSetsProvider(gymId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sets = ref.watch(holdSetsProvider(gymId));

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createSet(context, ref),
        icon: const Icon(Icons.palette_outlined),
        label: const Text('Nuevo set'),
      ),
      body: sets.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'No se pudo cargar',
          message: describeError(error),
        ),
        data: (list) => list.isEmpty
            ? EmptyState(
                icon: Icons.category_outlined,
                title: 'Inventario vacío',
                message:
                    'Crea un set por color y catalógalo con la cámara: la app recorta cada presa.',
                action: FilledButton.tonalIcon(
                  onPressed: () => _createSet(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('Nuevo set'),
                ),
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(holdSetsProvider(gymId)),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final set = list[index];
                    final inUse = set.holdsCount - set.availableCount;
                    return Card(
                      child: ListTile(
                        leading: ColorDot(colorHex: set.colorHex, size: 28),
                        title: Text(set.name),
                        subtitle: Text(
                          '${set.holdsCount} presas · ${set.availableCount} disponibles'
                          '${inUse > 0 ? ' · $inUse montadas' : ''}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Catalogar con la cámara',
                          icon: const Icon(Icons.document_scanner_outlined),
                          onPressed: () async {
                            final added = await Navigator.of(context).push<bool>(
                              MaterialPageRoute(
                                builder: (_) => SegmentationScreen(set: set),
                              ),
                            );
                            if (added ?? false) {
                              ref.invalidate(holdSetsProvider(gymId));
                            }
                          },
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SetHoldsScreen(set: set),
                          ),
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

class _NewSetSheet extends ConsumerStatefulWidget {
  const _NewSetSheet({required this.gymId});

  final String gymId;

  @override
  ConsumerState<_NewSetSheet> createState() => _NewSetSheetState();
}

class _NewSetSheetState extends ConsumerState<_NewSetSheet> {
  final _name = TextEditingController();
  String _colorHex = '#FFD700';
  bool _saving = false;

  /// Paleta habitual de sets comerciales.
  static const _palette = [
    '#E74C3C', '#E67E22', '#FFD700', '#2ECC71',
    '#1ABC9C', '#3498DB', '#9B59B6', '#EC407A',
    '#000000', '#FFFFFF', '#795548', '#95A5A6',
  ];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(inventoryRepositoryProvider).createSet(
            widget.gymId,
            name: _name.text.trim(),
            colorHex: _colorHex,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Nuevo set de presas',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nombre',
              hintText: 'Set Regletas Amarillas Cheeta',
            ),
          ),
          const SizedBox(height: 16),
          const Text('Color del set'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final hex in _palette)
                GestureDetector(
                  onTap: () => setState(() => _colorHex = hex),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: ColorDot.parse(hex),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _colorHex == hex
                            ? Theme.of(context).colorScheme.primary
                            : Colors.black26,
                        width: _colorHex == hex ? 3 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('Crear set'),
          ),
        ],
      ),
    );
  }
}
