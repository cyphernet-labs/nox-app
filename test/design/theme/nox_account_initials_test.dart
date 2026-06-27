import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/theme/nox_brand.dart';

void main() {
  group('noxAccountInitials', () {
    test('single token yields one letter', () {
      expect(noxAccountInitials('User7421'), 'U');
      expect(noxAccountInitials('Alice'), 'A');
    });

    test('two dot/underscore/dash tokens yield first + last initial', () {
      expect(noxAccountInitials('john.doe'), 'JD');
      expect(noxAccountInitials('a-b-c'), 'AC');
    });

    test('three or more tokens take the first and last token only', () {
      expect(noxAccountInitials('john_doe_smith'), 'JS');
      expect(noxAccountInitials('nox.core.team'), 'NT');
    });

    test('whitespace is also a token separator', () {
      expect(noxAccountInitials('  spaced  name '), 'SN');
    });

    test('mixed separators are collapsed', () {
      expect(noxAccountInitials('john. doe'), 'JD');
    });

    test('result is always upper-cased', () {
      expect(noxAccountInitials('nyx'), 'N');
      expect(noxAccountInitials('ada lovelace'), 'AL');
    });

    test('empty or separator-only labels return null (glyph fallback)', () {
      expect(noxAccountInitials(''), isNull);
      expect(noxAccountInitials('   '), isNull);
      expect(noxAccountInitials('...'), isNull);
      expect(noxAccountInitials('__'), isNull);
    });
  });
}
