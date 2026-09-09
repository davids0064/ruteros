import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Caché de sprites decodificados, viva sólo mientras dura la edición.
///
/// RNF-1: es caché **efímera en RAM**. Nada se escribe en disco por nuestra
/// cuenta; el único almacenamiento es el caché HTTP del propio motor de imagen.
class SpriteCache {
  final Map<String, ui.Image> _images = {};
  final Map<String, Future<ui.Image>> _inFlight = {};

  ui.Image? operator [](String url) => _images[url];

  bool get isEmpty => _images.isEmpty;

  /// Decodifica las N imágenes en paralelo. Se llama UNA vez, antes de pintar:
  /// durante el arrastre el painter sólo lee de [_images] (RNF-2).
  Future<void> preload(Iterable<String> urls) async {
    await Future.wait([
      for (final url in urls.toSet())
        if (!_images.containsKey(url)) _load(url),
    ]);
  }

  Future<ui.Image> _load(String url) {
    return _inFlight.putIfAbsent(url, () async {
      final completer = Completer<ui.Image>();
      final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          stream.removeListener(listener);
          if (!completer.isCompleted) completer.complete(info.image);
        },
        onError: (error, stack) {
          stream.removeListener(listener);
          if (!completer.isCompleted) completer.completeError(error, stack);
        },
      );
      stream.addListener(listener);

      try {
        final image = await completer.future;
        _images[url] = image;
        return image;
      } finally {
        _inFlight.remove(url);
      }
    });
  }

  void dispose() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
  }
}
