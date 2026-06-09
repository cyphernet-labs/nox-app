import 'dart:io';

/// Platform detection helpers. Centralizes dart:io Platform checks.
class PlatformUtils {
  PlatformUtils._();

  static bool get isMobile => Platform.isAndroid || Platform.isIOS;
  static bool get isDesktop => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  static bool get isAndroid => Platform.isAndroid;
  static bool get isIOS => Platform.isIOS;
  static bool get isMacOS => Platform.isMacOS;
}
