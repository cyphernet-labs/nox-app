import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/service/local_files_service.dart';

/// A picture from a file on this device, drawn from memory (phase 048,
/// FR-006): what `FileImage` is for a plain file, for the files NOX keeps
/// sealed. The bytes are opened into memory on their way to the decoder, and no
/// plain copy is written anywhere; the person's own file, picked a moment ago,
/// is read as it is.
///
/// Keyed by the path, like `FileImage`: a path names one content for good - an
/// attachment by its file id, a queued copy by its send - so a decoded picture
/// is reused rather than opened again on every rebuild of a scrolling thread.
@immutable
class LocalFileImage extends ImageProvider<LocalFileImage> {
  const LocalFileImage(this.path, {this.scale = 1.0});

  final String path;
  final double scale;

  @override
  Future<LocalFileImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture<LocalFileImage>(this);

  @override
  ImageStreamCompleter loadImage(LocalFileImage key, ImageDecoderCallback decode) {
    // No path in the label: it carries the file's name, and labels reach error
    // reports.
    return MultiFrameImageStreamCompleter(codec: _load(key, decode), scale: key.scale, debugLabel: 'LocalFileImage');
  }

  Future<ui.Codec> _load(LocalFileImage key, ImageDecoderCallback decode) async {
    final Uint8List bytes;
    try {
      bytes = await getIt<LocalFilesService>().read(key.path);
    } on Object {
      // Not kept as an answer: the same file may open a moment later - the
      // bytes still on their way, a key not opened yet.
      PaintingBinding.instance.imageCache.evict(key);
      rethrow;
    }
    if (bytes.isEmpty) {
      PaintingBinding.instance.imageCache.evict(key);
      throw StateError('the file is empty');
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) => other is LocalFileImage && other.path == path && other.scale == scale;

  @override
  int get hashCode => Object.hash(path, scale);

  @override
  String toString() => '${objectRuntimeType(this, 'LocalFileImage')}(scale: $scale)';
}
