import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/font_licenses.dart';

/// The licence of every bundled font travels with the app (Apache 2.0 for
/// Roboto, SIL OFL 1.1 for Roboto Mono, as the fonts' own name tables state).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('both bundled font families are registered with their licence texts', () async {
    registerFontLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    String textOf(String package) =>
        entries.where((e) => e.packages.contains(package)).expand((e) => e.paragraphs).map((p) => p.text).join('\n');

    final roboto = textOf('Roboto');
    expect(roboto, contains('Copyright 2011 Google Inc.'));
    expect(roboto, contains('Apache License'));
    expect(roboto, contains('END OF TERMS AND CONDITIONS'));

    final mono = textOf('Roboto Mono');
    expect(mono, contains('The Roboto Mono Project Authors'));
    expect(mono, contains('SIL OPEN FONT LICENSE Version 1.1'));
  });
}
