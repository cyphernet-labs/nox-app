import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// US5 / FR-012 — flutter_gen is the single authoritative asset-path channel: no raw
/// asset-path string literals in feature code, and no AppImagesTokens symbol anywhere.
void main() {
  final dartFiles = Directory(
    'lib',
  ).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart') && !f.path.contains('/design/gen/')).toList();

  test('no raw "assets/..." path literals in lib/ outside the generated channel', () {
    final rawPath = RegExp('''['"]assets/''');
    final offenders = dartFiles.where((f) => rawPath.hasMatch(f.readAsStringSync())).map((f) => f.path).toList();
    expect(offenders, isEmpty, reason: 'raw asset-path literals found in: $offenders');
  });

  test('AppImagesTokens is removed everywhere', () {
    expect(File('lib/design/app_images_tokens.dart').existsSync(), isFalse);
    final offenders = dartFiles.where((f) => f.readAsStringSync().contains('AppImagesTokens')).map((f) => f.path).toList();
    expect(offenders, isEmpty, reason: 'AppImagesTokens still referenced in: $offenders');
  });
}
