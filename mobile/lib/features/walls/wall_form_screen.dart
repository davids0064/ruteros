import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/sensors/inclinometer.dart';
import '../../models/enums.dart';
import '../../state/providers.dart';
import '../../ui/widgets/common.dart';

/// Registro de un muro — RF-3.1, US-03.
///
/// Captura la foto, lee el ángulo con el giroscopio/acelerómetro y sube la
/// imagen directamente a S3 con URL prefirmada (§5) antes de crear el muro.
class WallFormScreen extends ConsumerStatefulWidget {
  const WallFormScreen({super.key, required this.gymId});

  final String gymId;

  @override
  ConsumerState<WallFormScreen> createState() => _WallFormScreenState();
}

class _WallFormScreenState extends ConsumerState<WallFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _width = TextEditingController(text: '300');
  final _height = TextEditingController(text: '400');

  Uint8List? _photo;
  double _incline = 0;
  bool _isPublic = false;
  bool _saving = false;
  bool _reading = false;

  @override
  void dispose() {
    _name.dispose();
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 88);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (mounted) setState(() => _photo = bytes);
  }

  /// Toma la lectura del sensor durante un instante y se queda con el valor ya
  /// estabilizado por la media móvil.
  Future<void> _captureIncline() async {
    setState(() => _reading = true);
    try {
      final angle = await Inclinometer()
          .angleStream
          .take(30)
          .last
          .timeout(const Duration(seconds: 3));
      if (mounted) setState(() => _incline = angle);
    } catch (_) {
      if (mounted) {
        showInfo(context,
            'No se pudo leer el sensor. Ajusta el ángulo manualmente.');
      }
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_photo == null) {
      showInfo(context, 'Añade una foto del muro: es el lienzo del editor.');
      return;
    }

    setState(() => _saving = true);
    try {
      final urls = await ref.read(uploadsRepositoryProvider).uploadAll(
            scope: UploadScope.wallPhoto,
            files: [_photo!],
            contentType: 'image/jpeg',
            gymId: widget.gymId,
          );

      await ref.read(wallsRepositoryProvider).create(
            widget.gymId,
            name: _name.text.trim(),
            photoUrl: urls.single,
            widthCm: double.parse(_width.text.trim()),
            heightCm: double.parse(_height.text.trim()),
            defaultInclineDeg: _incline,
            isPublic: _isPublic,
          );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Registrar muro')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: _photo == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add_a_photo_outlined, size: 40),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              children: [
                                FilledButton.tonalIcon(
                                  onPressed: () =>
                                      _pickPhoto(ImageSource.camera),
                                  icon: const Icon(Icons.photo_camera_outlined),
                                  label: const Text('Cámara'),
                                ),
                                FilledButton.tonalIcon(
                                  onPressed: () =>
                                      _pickPhoto(ImageSource.gallery),
                                  icon: const Icon(Icons.photo_library_outlined),
                                  label: const Text('Galería'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(_photo!, fit: BoxFit.cover),
                          Positioned(
                            right: 8,
                            top: 8,
                            child: IconButton.filledTonal(
                              icon: const Icon(Icons.refresh),
                              onPressed: () => setState(() => _photo = null),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nombre del muro *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _width,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Ancho (cm) *'),
                    validator: _positive,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _height,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Alto (cm) *'),
                    validator: _positive,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Inclinación',
                              style: theme.textTheme.titleSmall),
                        ),
                        Text('${_incline.toStringAsFixed(1)}°',
                            style: theme.textTheme.headlineSmall),
                      ],
                    ),
                    Text(
                      'Apoya el teléfono contra el muro, con la pantalla hacia fuera. '
                      'Desplome positivo, placa tumbada negativa.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                    Slider(
                      value: _incline,
                      min: -90,
                      max: 90,
                      divisions: 180,
                      label: '${_incline.toStringAsFixed(0)}°',
                      onChanged: (v) => setState(() => _incline = v),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _reading ? null : _captureIncline,
                      icon: _reading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.screen_rotation_alt_outlined),
                      label: const Text('Leer del sensor'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _isPublic,
              onChanged: (v) => setState(() => _isPublic = v),
              title: const Text('Muro público'),
              subtitle: const Text('Visible para cualquiera, sin sesión.'),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('Registrar muro'),
            ),
          ],
        ),
      ),
    );
  }

  static String? _positive(String? v) {
    final parsed = double.tryParse(v?.trim() ?? '');
    if (parsed == null || parsed <= 0) return 'Debe ser mayor que cero';
    return null;
  }
}
