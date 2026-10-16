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

  /// The folder of the picker's copy at [path] - the uuid folder on Android,
  /// the inbox on iOS - or null when [path] is no copy of the picker's.
  static Future<Directory?> _holderOf(String path) async {
    final sep = Platform.pathSeparator;
    if (_android) {
      final cache = debugCache ?? (await getApplicationCacheDirectory()).path;
      if (!path.startsWith('$cache$sep')) return null;
      final rest = path.substring(cache.length + 1).split(sep);
      if (rest.length != 2 || !_uuid.hasMatch(rest.first)) return null;
      return Directory('$cache$sep${rest.first}');
    }
    if (_ios) {
      final temp = debugTemp ?? (await getTemporaryDirectory()).path;
      if (!path.startsWith('$temp$sep')) return null;
      final rest = path.substring(temp.length + 1).split(sep);
      if (rest.length != 2 || !rest.first.endsWith('-Inbox')) return null;
      return Directory('$temp$sep${rest.first}');
    }
    return null;
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

  /// Deletes every copy of the picker's (a logout): the files are what the
  /// person attached, on a device being handed back to nobody in particular.
  static Future<void> clear() async {
    try {
      if (_android) {
        final cache = Directory(debugCache ?? (await getApplicationCacheDirectory()).path);
        if (!cache.existsSync()) return;
        for (final entry in cache.listSync()) {
          if (entry is Directory && _uuid.hasMatch(entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty))) {
            await entry.delete(recursive: true);
          }
        }
      } else if (_ios) {
        final temp = Directory(debugTemp ?? (await getTemporaryDirectory()).path);
        if (!temp.existsSync()) return;
        for (final entry in temp.listSync()) {
          if (entry is Directory && entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty).endsWith('-Inbox')) {
            await entry.delete(recursive: true);
          }
        }
      }
    } catch (error) {
      logRepository.error(target: PickerCopies, error: error.runtimeType);
    }
  }
}
