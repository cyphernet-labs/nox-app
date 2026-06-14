import 'package:flutter/material.dart';
import 'package:nox_app/design/theme/nox_text_theme.dart';

/// Color-injecting typography helpers over the canonical M3 type scale
/// ([noxTextTheme]) — single source of sizes/weights/letter-spacing (06 §4.1;
/// no off-scale values, no `.sp` double-scale). Callers pass the resolved color
/// from `context.appColors` / `ColorScheme`. The base styles live in
/// `noxTextTheme` (generated from `typography.tokens.json`).
abstract final class AppTextStyleTokens {
  const AppTextStyleTokens._();

  static TextStyle body({required Color color}) => noxTextTheme.bodyMedium!.copyWith(color: color);

  static TextStyle title({required Color color}) => noxTextTheme.titleMedium!.copyWith(color: color);

  static TextStyle caption({required Color color}) => noxTextTheme.labelMedium!.copyWith(color: color);
}
