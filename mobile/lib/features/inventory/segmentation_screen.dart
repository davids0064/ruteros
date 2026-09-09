import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../cv/heuristic_category.dart';
import '../../cv/segment_service.dart';
import '../../models/enums.dart';
import '../../models/hold.dart';
import '../../state/providers.dart';
import '../../ui/widgets/common.dart';

/// Presa segmentada mientras el usuario la revisa. Vive en RAM (RNF-1).
class _Candidate {
  _Candidate(this.segmented)
      : category = segmented.suggestedCategory,
        weight = suggestedWeight(segmented.suggestedCategory);

  final SegmentedHold segmented;
  HoldCategory category;
  double weight;
  bool keep = true;

  Uint8List get png => segmented.imageBytesPNG;
}

/// Catalogación de un set con la cámara — RF-2.1, US-02.
///
/// Pipeline completo: foto → segmentación en el dispositivo → revisión humana →
/// subida en paralelo a S3 → alta masiva transaccional.
class SegmentationScreen extends ConsumerStatefulWidget {
  const SegmentationScreen({super.key, required this.set});

  final HoldSet set;

  @override
  ConsumerState<SegmentationScreen> createState() => _SegmentationScreenState();
}

class _SegmentationScreenState extends ConsumerState<SegmentationScreen> {
  List<_Candidate> _candidates = [];
  bool _processing = false;
  bool _uploading = false;
  Duration? _lastSegmentation;

  int get _kept => _candidates.where((c) => c.keep).length;

  Future<void> _capture(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 92);
    if (picked == null) return;

    setState(() => _processing = true);
    final started = DateTime.now();
    try {
      final bytes = await picked.readAsBytes();
      final results =
          await ref.read(segmentServiceProvider).processSetImage(
                imageBytes: bytes,
                colorHex: widget.set.colorHex,
              );

      if (!mounted) return;
      setState(() {
        _candidates = [for (final r in results) _Candidate(r)];
        _lastSegmentation = DateTime.now().difference(started);
      });

      if (results.isEmpty && mounted) {
        showInfo(context,
            'No se detectaron presas del color del set. Prueba con más luz o un fondo liso.');
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  /// KPI: 10 presas catalogadas y subidas en menos de 15 segundos. Se consigue
  /// subiendo los N PNG en paralelo a S3 y cerrando con un solo alta masiva.
  Future<void> _publish() async {
    final selected = _candidates.where((c) => c.keep).toList();
    if (selected.isEmpty) return;

    setState(() => _uploading = true);
    final started = DateTime.now();
    try {
      final urls = await ref.read(uploadsRepositoryProvider).uploadAll(
            scope: UploadScope.holdCrop,
            files: [for (final c in selected) c.png],
            contentType: 'image/png',
            gymId: widget.set.gymId,
          );

      await ref.read(inventoryRepositoryProvider).createHolds(
            widget.set.id,
            [
              for (var i = 0; i < selected.length; i++)
                CreateHoldPayload(
                  imageCropUrl: urls[i],
                  typeCategory: selected[i].category,
                  difficultyRatingWeight: selected[i].weight,
                  boundingBoxData: BoundingBox(
                    widthPx: selected[i].segmented.boundingBoxPx.width,
                    heightPx: selected[i].segmented.boundingBoxPx.height,
                  ),
                ),
            ],
          );

      final elapsed = DateTime.now().difference(started);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showInfo(context,
          '${selected.length} presas catalogadas en ${(elapsed.inMilliseconds / 1000).toStringAsFixed(1)} s.');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ColorDot(colorHex: widget.set.colorHex),
            const SizedBox(width: 8),
            const Expanded(child: Text('Catalogar presas')),
          ],
        ),
      ),
      bottomNavigationBar: _candidates.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _uploading || _kept == 0 ? null : _publish,
                  icon: _uploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Icon(Icons.cloud_upload_outlined),
                  label: Text(_uploading
                      ? 'Subiendo…'
                      : 'Añadir $_kept presas al inventario'),
                ),
              ),
            ),
      body: _processing
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Segmentando presas…'),
                ],
              ),
            )
          : _candidates.isEmpty
              ? EmptyState(
                  icon: Icons.document_scanner_outlined,
                  title: 'Fotografía el set completo',
                  message:
                      'Extiende las presas sobre un fondo liso y contrastado. '
                      'La app recorta cada una por su color y la deja con fondo transparente.',
                  action: Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _capture(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Cámara'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => _capture(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Galería'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_candidates.length} detectadas'
                              '${_lastSegmentation == null ? '' : ' en ${(_lastSegmentation!.inMilliseconds / 1000).toStringAsFixed(1)} s'}'
                              ' · revisa el tipo antes de subir',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.outline),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _capture(ImageSource.camera),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Otra foto'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 170,
                          childAspectRatio: 0.68,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: _candidates.length,
                        itemBuilder: (context, index) =>
                            _CandidateCard(candidate: _candidates[index], onChanged: () => setState(() {})),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({required this.candidate, required this.onChanged});

  final _Candidate candidate;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Opacity(
        opacity: candidate.keep ? 1 : 0.4,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Image.memory(candidate.png, fit: BoxFit.contain),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Checkbox(
                      value: candidate.keep,
                      onChanged: (v) {
                        candidate.keep = v ?? true;
                        onChanged();
                      },
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: DropdownButton<HoldCategory>(
                value: candidate.category,
                isDense: true,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: [
                  for (final c in HoldCategory.values)
                    DropdownMenuItem(
                      value: c,
                      child: Text(c.label,
                          style: Theme.of(context).textTheme.labelMedium),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  candidate.category = v;
                  // La sugerencia de peso acompaña al tipo mientras el usuario
                  // no la haya tocado a mano.
                  candidate.weight = suggestedWeight(v);
                  onChanged();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
