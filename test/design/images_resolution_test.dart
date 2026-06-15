import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/gen/assets.gen.dart';

/// US3 / FR-006..FR-007 / SC-002 — brand + illustrations bundled, no broken paths,
/// AppImagesTokens removed.
void main() {
  test('logo and the 3 empty-state illustrations resolve to existing assets', () {
    expect(File(Assets.png.logo.path).existsSync(), isTrue);
    expect(File(Assets.svg.illustrations.emptyChats.path).existsSync(), isTrue);
    expect(File(Assets.svg.illustrations.emptyMessages.path).existsSync(), isTrue);
    expect(File(Assets.svg.illustrations.emptyFiles.path).existsSync(), isTrue);
  });

  test('reference-only logo is not bundled and AppImagesTokens is removed', () {
    expect(File('assets/png/logo-reference.png').existsSync(), isFalse);
    expect(File('lib/design/app_images_tokens.dart').existsSync(), isFalse);
  });
}
