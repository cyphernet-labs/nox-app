import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

bool _loaded = false;

/// Loads the bundled Roboto / Roboto Mono fonts from disk so golden tests render
/// real glyphs instead of the flutter_test placeholder font. Idempotent per
/// isolate. Read via dart:io (font files live under `fonts:`, not the asset
/// manifest, so `rootBundle.load` would miss them). Source: assets/fonts/.
Future<void> loadNoxFonts() async {
  if (_loaded) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final path in paths) {
      final bytes = await File(path).readAsBytes();
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('Roboto', const ['assets/fonts/Roboto-Regular.ttf', 'assets/fonts/Roboto-Medium.ttf', 'assets/fonts/Roboto-Bold.ttf']);
  await load('Roboto Mono', const ['assets/fonts/RobotoMono-Regular.ttf']);
  _loaded = true;
}
