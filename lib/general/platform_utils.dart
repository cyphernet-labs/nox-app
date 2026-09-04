import 'dart:io';

/// Platform detection helpers. Centralizes dart:io Platform checks.
class PlatformUtils {
  PlatformUtils._();

  static bool get isMobile => Platform.isAndroid || Platform.isIOS;
  static bool get isDesktop => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  static bool get isAndroid => Platform.isAndroid;
  static bool get isIOS => Platform.isIOS;
  static bool get isMacOS => Platform.isMacOS;

  /// The OS family, as the server records it against a device key.
  ///
  /// Deliberately the FAMILY and nothing finer: it is enough to recognise one's
  /// own tablet among three in the device list, while the exact model would be
  /// a fingerprint the server has no reason to hold.
  static String get family {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }
}
