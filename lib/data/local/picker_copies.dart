import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:path_provider/path_provider.dart';

/// The plain copies a platform's file picker leaves in the app's own storage
/// (phase 048 review). On Android the picker copies a picked document into
/// `<cache>/<uuid>/<name>`; on iOS it imports the file into
/// `<tmp>/<bundle id>-Inbox/`. Neither deletes it, so a file NOX seals in its
/// queue would otherwise stay readable in plain beside it, logouts included.
///
/// Only those two places are ever touched. Everywhere else - Windows, Linux,
/// macOS, and any other path on a phone - a picked path is the person's own
/// file, which is never NOX's to delete.
abstract final class PickerCopies {
  static final RegExp _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  /// Which platform a test means, and where its folders are.
  @visibleForTesting
  static bool? debugAndroid;
  @visibleForTesting
  static bool? debugIos;
  @visibleForTesting
  static String? debugCache;
  @visibleForTesting
  static String? debugTemp;

  static bool get _android => debugAndroid ?? Platform.isAndroid;
  static bool get _ios => debugIos ?? Platform.isIOS;

  /// Where the picker puts its copies, its links resolved: the cache folder
  /// on Android; the container's own tmp on iOS - what NSTemporaryDirectory
  /// answers, through TMPDIR, and NOT path_provider's "temporary" folder,
  /// which is Library/Caches there. Null anywhere else.
  static Future<String?> _root() async {
    final String dir;
    if (_android) {
      dir = debugCache ?? (await getApplicationCacheDirectory()).path;
    } else if (_ios) {
      dir = debugTemp ?? Directory.systemTemp.path;
    } else {
      return null;
    }
    try {
      return Directory(dir).resolveSymbolicLinksSync();
    } on FileSystemException {
      return null;
    }
  }

  /// Whether [name] is a folder the picker makes: a uuid on Android, an
  /// inbox on iOS.
  static bool _isHolder(String name) => _android ? _uuid.hasMatch(name) : name.endsWith('-Inbox');

  /// The folder of the picker's copy at [path] - the uuid folder on Android,
  /// the inbox on iOS - or null when [path] is no copy of the picker's. Paths
  /// are compared with their links resolved: on a device the picker answers
  /// /private/var where the system folders say /var.
  static Future<Directory?> _holderOf(String path) async {
    final root = await _root();
    if (root == null) return null;
    final holder = File(path).parent;
    try {
      if (holder.parent.resolveSymbolicLinksSync() != root) return null;
    } on FileSystemException {
      return null;
    }
    final name = holder.uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => '');
    return _isHolder(name) ? holder : null;
  }

  /// Deletes the picker's copy at [path] - once the queue sealed its own, or
  /// the draft it was picked for is dropped. A path that is no copy of the
  /// picker's is left alone. Best effort, like every delete of a wipe.
  static Future<void> release(String path) async {
    try {
      final holder = await _holderOf(path);
      if (holder == null) return;
      final file = File(path);
      if (file.existsSync()) await file.delete();
      // The uuid folder holds the one copy; an inbox may hold others.
      if (_android && holder.existsSync() && holder.listSync().isEmpty) await holder.delete();
    } catch (error) {
      logRepository.error(target: PickerCopies, error: error.runtimeType);
    }
  }

  /// Deletes every copy of the picker's but those in [keep] - a logout, which
  /// keeps none, or a launch, which keeps what the queue still sends from.
  /// An inbox holds many copies: only the files kept stay in it.
  static Future<void> clear({Set<String> keep = const <String>{}}) async {
    try {
      final root = await _root();
      if (root == null) return;
      final kept = <String>{
        for (final path in keep)
          if (await _holderOf(path) != null && File(path).existsSync()) File(path).resolveSymbolicLinksSync(),
      };
      for (final entry in Directory(root).listSync()) {
        if (entry is! Directory) continue;
        final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => '');
        if (!_isHolder(name)) continue;
        final inside = entry.listSync(recursive: true).whereType<File>().toList();
        if (!inside.any((f) => kept.contains(f.resolveSymbolicLinksSync()))) {
          await entry.delete(recursive: true);
          continue;
        }
        for (final file in inside) {
          if (!kept.contains(file.resolveSymbolicLinksSync())) await file.delete();
        }
      }
    } catch (error) {
      logRepository.error(target: PickerCopies, error: error.runtimeType);
    }
  }
}
