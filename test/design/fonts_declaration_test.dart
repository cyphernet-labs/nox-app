import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/theme/nox_text_theme.dart';

/// US2 / FR-004..FR-005 — fonts bundled, declared, family names match the theme.
void main() {
  test('the 4 font .ttf files are bundled', () {
    for (final name in ['Roboto-Regular', 'Roboto-Medium', 'Roboto-Bold', 'RobotoMono-Regular']) {
      expect(File('assets/fonts/$name.ttf').existsSync(), isTrue, reason: '$name.ttf missing');
    }
  });

  test('pubspec declares both families with the expected weights', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec.contains('family: Roboto'), isTrue);
    expect(pubspec.contains('family: Roboto Mono'), isTrue);
    for (final w in ['weight: 400', 'weight: 500', 'weight: 700']) {
      expect(pubspec.contains(w), isTrue, reason: 'pubspec missing $w');
    }
    expect(pubspec.contains('assets/fonts/RobotoMono-Regular.ttf'), isTrue);
  });

  test('declared family names match nox_text_theme', () {
    expect(noxMonoFamily, 'Roboto Mono');
    expect(noxTextTheme.bodyMedium!.fontFamily, 'Roboto');
  });
}
