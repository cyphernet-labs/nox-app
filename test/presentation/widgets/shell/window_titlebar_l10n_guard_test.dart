import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The desktop window titlebar's subtitle is the one piece of user-facing copy in
/// this app that a page passes in as a plain constructor argument, so it is the
/// one place a raw English literal can sit without looking out of place. All four
/// call sites did exactly that - `'Sign in'`, `'Set up'`, `'Scan QR'`, `'Error'` -
/// while three ARB keys minted for them went unused: the keys carried the whole
/// window title (`NOX · Sign in`), and the widget draws the wordmark itself, so
/// passing them verbatim would have rendered the wordmark twice. The values were
/// reshaped to be subtitles; this test is what keeps the next call site honest.
///
/// A source scan rather than a widget test on purpose: a widget test proves one
/// screen localized, this proves there is no fifth screen that is not.
void main() {
  final dartFiles = Directory(
    'lib',
  ).listSync(recursive: true).whereType<File>().where((f) => f.path.replaceAll(r'\', '/').endsWith('.dart')).toList();

  test('no window titlebar subtitle is a raw string literal', () {
    // `subtitle:` followed by a quote - i.e. copy that never passed through l10n.
    final rawSubtitle = RegExp(r'''subtitle:\s*['"]''');
    final offenders = dartFiles.where((f) => rawSubtitle.hasMatch(f.readAsStringSync())).map((f) => f.path).toList();
    expect(offenders, isEmpty, reason: 'hardcoded window titlebar subtitle in: $offenders');
  });
}
