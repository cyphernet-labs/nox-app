import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/general/platform_utils.dart';

/// The save dialog of iOS and Android, which the runner shows (`nox/save`):
/// Files' export picker on iOS (`NoxSave`, `ios/Runner/AppDelegate.swift`),
/// the system's "create document" on Android (`MainActivity`). Unlike a
/// desktop's, it takes a FILE: the person picks the place, and the platform
/// writes the file there itself.
@lazySingleton
class SystemSaveDialog {
  static const MethodChannel _channel = MethodChannel('nox/save');

  /// iOS and Android: the platforms whose runner carries this dialog, and the
  /// two where file_selector has none - its `getSaveLocation` is not
  /// implemented there.
  bool get isAvailable => PlatformUtils.isMobile;

  /// Shows the dialog for the file at [path], under that file's own name.
  /// True once it is written where the person chose; false when they
  /// cancelled. Throws a [PlatformException] when it could not be shown, or
  /// the file could not be written.
  Future<bool> save({required String path}) async => await _channel.invokeMethod<bool>('save', <String, Object>{'path': path}) == true;
}
