import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/gen/assets.gen.dart';

/// US3 / FR-006..FR-007 / SC-002 — the brand logo bundled, no broken paths,
/// AppImagesTokens removed. Empty states draw no illustration: their art is the
/// composition of AppEmptyContentWidget, so none is bundled.
void main() {
  test('the logo resolves to an existing asset', () {
    expect(File(Assets.png.logo.path).existsSync(), isTrue);
  });

  test('no empty-state illustration is bundled', () {
    // What ships is what pubspec declares; a folder left on a disk does not.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec.contains('assets/svg/illustrations'), isFalse);
  });

  test('reference-only logo is not bundled and AppImagesTokens is removed', () {
    expect(File('assets/png/logo-reference.png').existsSync(), isFalse);
    expect(File('lib/design/app_images_tokens.dart').existsSync(), isFalse);
  });
}
