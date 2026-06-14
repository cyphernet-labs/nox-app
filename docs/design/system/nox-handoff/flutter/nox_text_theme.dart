// GENERATED — NOX M3 type scale → Flutter TextTheme.
// Source: tokens/typography.tokens.json. height = lineHeightPx / fontSize.
// Sans = platform-native (DTCG sans stack ["Roboto","system-ui","sans-serif"] ->
// Flutter platform default: Roboto on Android, SF on Apple, system elsewhere).
// Mono = bundled Roboto Mono (pubspec fonts:), so 'Roboto Mono' resolves on all 5 targets.
import 'package:flutter/material.dart';

const String? _sans = null; // platform-native sans (see header); null => Flutter platform default
const String noxMonoFamily = 'Roboto Mono'; // ID string only (7.1); bundled via pubspec fonts:

const TextTheme noxTextTheme = TextTheme(
  displaySmall: TextStyle(fontFamily: _sans, fontSize: 36, height: 1.222, fontWeight: FontWeight.w400, letterSpacing: 0), // 36/44
  headlineSmall: TextStyle(fontFamily: _sans, fontSize: 24, height: 1.333, fontWeight: FontWeight.w400, letterSpacing: 0), // 24/32
  titleLarge: TextStyle(fontFamily: _sans, fontSize: 22, height: 1.273, fontWeight: FontWeight.w400, letterSpacing: 0), // 22/28
  titleMedium: TextStyle(fontFamily: _sans, fontSize: 16, height: 1.500, fontWeight: FontWeight.w500, letterSpacing: 0.15), // 16/24
  bodyLarge: TextStyle(fontFamily: _sans, fontSize: 16, height: 1.500, fontWeight: FontWeight.w400, letterSpacing: 0.5), // 16/24
  bodyMedium: TextStyle(fontFamily: _sans, fontSize: 14, height: 1.429, fontWeight: FontWeight.w400, letterSpacing: 0.25), // 14/20
  labelLarge: TextStyle(fontFamily: _sans, fontSize: 14, height: 1.429, fontWeight: FontWeight.w500, letterSpacing: 0.1), // 14/20
  labelMedium: TextStyle(fontFamily: _sans, fontSize: 12, height: 1.333, fontWeight: FontWeight.w500, letterSpacing: 0.5), // 12/16
  labelSmall: TextStyle(fontFamily: _sans, fontSize: 11, height: 1.455, fontWeight: FontWeight.w500, letterSpacing: 0.5), // 11/16
);

// Wordmark «NOX» — design-system.md §1/§3: titleLarge base, weight 700,
// letter-spacing +0.12em (= 2.64px @ 22). Brand surfaces (splash/AppBar wordmark).
const TextStyle noxWordmark = TextStyle(fontFamily: _sans, fontSize: 22, height: 1.273, fontWeight: FontWeight.w700, letterSpacing: 2.64);
