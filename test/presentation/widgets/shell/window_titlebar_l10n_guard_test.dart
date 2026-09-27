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

  // Everything from `//` to end of line, so a comment that merely MENTIONS the
  // old shape cannot fail the build and send someone to a file that is correct.
  // A `//` preceded by a colon is left alone - that is a URL inside a string.
  final comments = RegExp(r'(?<!:)//[^\n]*');

  // A quote anywhere in the argument, not only glued to the colon: a ternary or
  // a `?? 'fallback'` is the same defect wearing a different shape. Bounded by
  // `,`, `)` or the line end so it cannot run on into unrelated code.
  final rawSubtitle = RegExp(r'''subtitle:[^,)\n]*['"]''');

  test('no window titlebar subtitle is a raw string literal', () {
    final offenders = dartFiles
        .where((f) => rawSubtitle.hasMatch(f.readAsStringSync().replaceAll(comments, '')))
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty, reason: 'hardcoded window titlebar subtitle in: $offenders');
  });
}
