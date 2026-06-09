import 'dart:ui';

/// App-wide constants. Never instantiated — access members statically.
final class Constants {
  Constants._();

  /// General config
  static const databaseName = 'nox_app_db';
  static const defaultLocale = 'en_US';

  /// UI
  static const defaultNavTransitionTimeMilliseconds = 300;
  static const preventDoubleNavDelayMilliseconds = 300;
  static const designSize = Size(360, 779); // flutter_screenutil reference
  static const double railBreakpoint = 840; // M3 medium->expanded; bottom-bar <-> NavigationRail

  /// Validation patterns (compile once as static final RegExp)
  static final emailRegex = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@"
    r"[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?"
    r"(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$",
  );
  static final phoneRegex = RegExp(r'^\+?[0-9]{7,15}$');
}
