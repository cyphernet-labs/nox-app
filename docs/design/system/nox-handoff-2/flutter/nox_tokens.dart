// GENERATED — NOX non-color tokens → Flutter constants.
// Sources: tokens/{spacing,shape,elevation,motion}.tokens.json.
import 'package:flutter/material.dart';

/// 4dp base grid. Use with EdgeInsets / SizedBox / Gap. Min tap-target 48.
abstract final class NoxSpacing {
  static const double s1 = 4;   // space/1
  static const double s2 = 8;   // space/2
  static const double s3 = 12;  // space/3
  static const double s4 = 16;  // space/4 — screen horizontal padding
  static const double s6 = 24;  // space/6
  static const double s8 = 32;  // space/8
  static const double screenPadding = 16;
  static const double minTapTarget = 48;
}

/// Corner radii. `full` → StadiumBorder / circle.
abstract final class NoxRadius {
  static const double none = 0;   // edge-to-edge video
  static const double xs = 4;     // TextField, file-chip
  static const double s = 8;      // small chips, segments
  static const double m = 12;     // Card (identity)
  static const double l = 16;     // message bubble base
  static const double xl = 28;    // bottom sheet, AlertDialog
  static const double full = 999; // stadium / circle

  /// Message bubble: base l(16); the "own" bottom-right / "other" bottom-left
  /// corner clips to 4 (asymmetry instead of a tail).
  static BorderRadius bubble({required bool isOwn}) => BorderRadius.only(
        topLeft: const Radius.circular(l),
        topRight: const Radius.circular(l),
        bottomLeft: Radius.circular(isOwn ? l : xs),
        bottomRight: Radius.circular(isOwn ? xs : l),
      );
}

/// M3 tonal elevation (dp). Pass to Material/Card `elevation`; do not hand-roll
/// BoxShadow — Flutter renders the tonal overlay + shadow from the dp value.
abstract final class NoxElevation {
  static const double level0 = 0;  // flat surfaces, AppBar
  static const double level1 = 1;  // Card, raised list
  static const double level2 = 3;  // BottomAppBar, SearchBar
  static const double level3 = 6;  // docked FAB, MaterialBanner
  static const double level5 = 12; // AlertDialog, modal sheet
}

/// M3 motion durations. No looping animations (splash is one-shot).
abstract final class NoxDuration {
  static const splashIn   = Duration(milliseconds: 400);
  static const push       = Duration(milliseconds: 300);
  static const tabFade    = Duration(milliseconds: 150);
  static const snackbarIn  = Duration(milliseconds: 150);
  static const snackbarOut = Duration(milliseconds: 75);
  static const sheet      = Duration(milliseconds: 300);
}

/// M3 easing curves.
abstract final class NoxEasing {
  static const Curve standard = Easing.standard; // Cubic(0.2, 0.0, 0.0, 1.0)
  static const Curve emphasized = Curves.easeInOutCubicEmphasized; // M3 emphasized (two-part)
  static const Curve emphasizedDecelerate = Easing.emphasizedDecelerate; // Cubic(0.05, 0.7, 0.1, 1.0)
}
