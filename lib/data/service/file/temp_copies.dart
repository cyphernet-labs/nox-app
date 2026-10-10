import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/local/sealed_file.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:path_provider/path_provider.dart';

/// The plain copies of sealed files (phase 048, FR-007): a video for the
/// player, a file for another app.
///
/// `<temp>/nox_open/<a folder of its own>/<name>`. Each copy gets a folder
/// made the way a temporary folder is - on Linux and macOS only this user may
/// enter it - because the temporary folder of a desktop is shared with every
/// other user of it, and the copy is the one plain file NOX writes. The copy
/// keeps the file's name: a player picks its decoder by the extension, and
/// another app shows the name.
///
/// A copy lives as long as it is needed: the video's until its player closes
/// ([release]); one handed to another app - which may still be reading it -
/// until the next launch or logout ([clear]), which take every copy left.
@lazySingleton
class TempCopies {
  static const String folder = 'nox_open';

  static final String _sep = Platform.pathSeparator;

  Future<Directory> _root() async => Directory('${(await getTemporaryDirectory()).path}$_sep$folder');

  /// A plain copy of [source], named [name]. A copy that cannot be made in
  /// full - no room on the disk, a chunk that does not open - leaves nothing
  /// behind and throws.
  Future<String> make({required String source, required String name}) async {
    final root = await _root();
    await root.create(recursive: true);
    final dir = await root.createTemp('c');
    try {
      final copy = File('${dir.path}$_sep${safeName(name)}');
      await SealedFile.writePlain(from: File(source), to: copy);
      return copy.path;
    } on Object {
      await _delete(dir);
      rethrow;
    }
  }

  /// Deletes [copy] with its folder - when it is one of these, and only then.
  Future<void> release(String copy) async {
    final root = '${(await _root()).path}$_sep';
    if (!copy.startsWith(root)) return;
    final own = copy.substring(root.length).split(_sep).first;
    if (own.isEmpty || own == '..') return;
    await _delete(Directory('$root$own'));
  }

  /// Deletes every copy (a launch, a logout).
  Future<void> clear() async => _delete(await _root());

  /// [name] as a file name and nothing more: the name of an attachment comes
  /// from another device, and a separator or `..` in it must not put the copy
  /// anywhere but its own folder.
  static String safeName(String name) {
    final last = name.split(RegExp(r'[\\/]')).last.trim();
    final cleaned = last.replaceAll(RegExp(r'[\x00-\x1F:*?"<>|]'), '_');
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') return 'file';
    return cleaned;
  }

  /// Best effort: a copy that will not go now goes at the next launch.
  Future<void> _delete(Directory dir) async {
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } on FileSystemException catch (error) {
      // The type only: the message carries the path, and the path the name.
      logRepository.error(target: this, error: error.runtimeType);
    }
  }
}
