import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/enums.dart';
import '../../models/hold.dart';
import '../../state/providers.dart';
import '../../ui/widgets/common.dart';

final setHoldsProvider =
    FutureProvider.family<List<Hold>, String>((ref, setId) {
  return ref.watch(inventoryRepositoryProvider).holdsOfSet(setId);
});

/// Presas de un set, con su estado de reutilización (RF-2.3).
class SetHoldsScreen extends ConsumerWidget {
  const SetHoldsScreen({super.key, required this.set});

  final HoldSet set;

  Future<void> _editHold(
      BuildContext context, WidgetRef ref, Hold hold) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      builder: (_) => _HoldSheet(hold: hold),
    );
    if (changed ?? false) ref.invalidate(setHoldsProvider(set.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holds = ref.watch(setHoldsProvider(set.id));

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ColorDot(colorHex: set.colorHex),
            const SizedBox(width: 8),
            Expanded(child: Text(set.name, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
      body: holds.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'No se pudo cargar',
          message: describeError(error),
        ),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.crop_free,
                title: 'Set sin presas',
                message: 'Catalógalo con la cámara desde el listado.',
              )
            : GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 150,
                  childAspectRatio: 0.78,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final hold = list[index];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _editHold(context, ref, hold),
                      child: Column(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Image.network(
                                hold.imageCropUrl,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.image_not_supported_outlined),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(hold.typeCategory.label,
                                    style:
                                        Theme.of(context).textTheme.labelLarge),
                                Text(
                                  hold.status.label,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: hold.status == HoldStatus.inUse
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                            : Theme.of(context)
                                                .colorScheme
                                                .outline,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _HoldSheet extends ConsumerStatefulWidget {
  const _HoldSheet({required this.hold});

  final Hold hold;

  @override
  ConsumerState<_HoldSheet> createState() => _HoldSheetState();
}

class _HoldSheetState extends ConsumerState<_HoldSheet> {
  late HoldCategory _category = widget.hold.typeCategory;
  late HoldStatus _status = widget.hold.status;
  late double _weight = widget.hold.difficultyRatingWeight;
  bool _saving = false;

  bool get _locked => widget.hold.status == HoldStatus.inUse;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(inventoryRepositoryProvider).updateHold(
            widget.hold.id,
            typeCategory: _category,
            difficultyRatingWeight: _weight,
            // RF-2.3: si está montada, su estado lo libera el desmontaje.
            status: _locked ? null : _status,
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
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Editar presa', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          DropdownButtonFormField<HoldCategory>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Tipo de agarre'),
            items: [
              for (final c in HoldCategory.values)
                DropdownMenuItem(value: c, child: Text(c.label)),
            ],
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          const SizedBox(height: 16),
          Text('Peso de dificultad: ${_weight.toStringAsFixed(1)}'),
          Slider(
            value: _weight.clamp(0.5, 5.0),
            min: 0.5,
            max: 5,
            divisions: 45,
            onChanged: (v) => setState(() => _weight = v),
          ),
          const SizedBox(height: 8),
          if (_locked)
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.lock_outline),
              title: Text('Presa montada'),
              subtitle: Text(
                  'Volverá a estar disponible al desmontar el bloque que la usa.'),
            )
          else
            DropdownButtonFormField<HoldStatus>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Estado'),
              items: [
                for (final s in HoldStatus.clientSettable)
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: (v) => setState(() => _status = v ?? _status),
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}
