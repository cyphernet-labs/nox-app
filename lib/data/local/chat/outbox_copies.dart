import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/local/app_data_root.dart';
import 'package:nox_app/di/global_aliases.dart';

/// The outgoing queue's own copies of the files it sends (phase 043).
///
/// A file is copied here the moment its message is sent, and the queue uploads
/// from the copy. The file the person picked can stop being readable long
/// before its bytes are all on the server: the macOS sandbox lets the app read
/// a picked file only while the process that picked it lives, the iOS picker's
/// copy sits in a directory the system may empty while the app is not running,
/// and on any desktop the original can be moved or changed. An upload that is
/// to go on after a restart needs bytes the app can always read - and the same
/// bytes every time, or what reaches the server is half of one file and half
/// of another.
///
/// One folder per send, named by its `client_message_id`, holding the file
/// under its own name: the upload declares the name of the file it reads.
/// The app's data folder (phase 048: `AppDataRoot`), not the cache: nothing
/// may empty it before the bytes are on the server.
@lazySingleton
class OutboxCopies {
  static const String folder = AppDataRoot.outboxFolder;

  static final String _sep = Platform.pathSeparator;

  String? _root;

  Future<String> _rootPath() async => _root ??= await AppDataRoot.pathOf(folder);

  /// Copies [source] for the send [key] and returns the copy's path - or null
  /// when no copy can be made, and the queue then sends from [source] as it
  /// did before copies existed.
  Future<String?> keep({required String key, required String source}) async {
    final dir = Directory('${await _rootPath()}$_sep$key');
    try {
      await dir.create(recursive: true);
      final copy = await File(source).copy('${dir.path}$_sep${source.split(_sep).last}');
      return copy.path;
    } on FileSystemException catch (error) {
      // The type only: the message carries the path, and the path the name.
      logRepository.error(target: this, error: error.runtimeType);
      await _delete(dir);
      return null;
    }
  }

  /// Whether [path] is the copy made for the send [key]. Nothing else is ever
  /// moved or deleted here: an entry queued before copies existed names the
  /// person's own file, and only a folder named by this send's own fresh key
  /// can be this app's.
  bool isCopy({required String key, required String path}) => path.contains(_marker(key));

  /// [path] as it is on this run when it is the copy made for [key], anything
  /// else as it is: iOS moves an app's container on every update, so a stored
  /// path keeps its tail and loses its head.
  Future<String> current({required String key, required String path}) async {
    final marker = _marker(key);
    final at = path.lastIndexOf(marker);
    if (at < 0) return path;
    return '${await _rootPath()}$_sep$key$_sep${path.substring(at + marker.length)}';
  }

  static String _marker(String key) => '$_sep$folder$_sep$key$_sep';

  /// Moves the copy of the send [key], at [path], to [destination] and lets
  /// its folder go. True once the bytes are at [destination] - moved now, or
  /// on an earlier pass that did not live to say so.
  Future<bool> moveTo({required String key, required String path, required String destination}) async {
    if (!isCopy(key: key, path: path)) return false;
    final target = File(destination);
    try {
      if (!target.existsSync()) {
        final copy = File(await current(key: key, path: path));
        if (!copy.existsSync()) return false;
        await target.parent.create(recursive: true);
        try {
          await copy.rename(destination);
        } on FileSystemException {
          // Another volume: rename cannot cross one.
          await copy.copy(destination);
        }
      }
    } on FileSystemException catch (error) {
      logRepository.error(target: this, error: error.runtimeType);
      return false;
    }
    await drop(key);
    return true;
  }

  /// Deletes the copy of the send [key], if it has one.
  Future<void> drop(String key) async => _delete(Directory('${await _rootPath()}$_sep$key'));

  /// Deletes every copy (logout, a change of server): the files are what the
  /// person was sending, on a device being handed back to nobody in particular.
  Future<void> clear() async => _delete(Directory(await _rootPath()));

  /// Best-effort, like every delete of a wipe: a folder that will not go is
  /// not worth failing what called it.
  Future<void> _delete(Directory dir) async {
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } on FileSystemException catch (error) {
      logRepository.error(target: this, error: error.runtimeType);
    }
  }
}
