import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/username_rules.dart';

void main() {
  group('UsernameRules.hasValidCharset', () {
    test('accepts letters, digits, dot, underscore and hyphen', () {
      expect(UsernameRules.hasValidCharset('User1234'), isTrue);
      expect(UsernameRules.hasValidCharset('john.doe'), isTrue);
      expect(UsernameRules.hasValidCharset('a_b-c.1'), isTrue);
      expect(UsernameRules.hasValidCharset('A'), isTrue);
    });

    test('rejects a space', () {
      expect(UsernameRules.hasValidCharset('john doe'), isFalse);
    });

    test('rejects an @ sign', () {
      expect(UsernameRules.hasValidCharset('john@doe'), isFalse);
    });

    test('rejects the empty string (the + quantifier requires at least one char)', () {
      expect(UsernameRules.hasValidCharset(''), isFalse);
    });

    test('rejects non-ASCII characters', () {
      expect(UsernameRules.hasValidCharset('Ünïcode'), isFalse);
    });
  });

  group('UsernameRules.isTaken', () {
    test('reports a name in the mock taken set as taken', () {
      expect(UsernameRules.isTaken('admin'), isTrue);
      expect(UsernameRules.isTaken('taken'), isTrue);
      expect(UsernameRules.isTaken('User1234'), isTrue);
    });

    test('is case-sensitive: NOX is taken but nox is not', () {
      expect(UsernameRules.isTaken('NOX'), isTrue);
      expect(UsernameRules.isTaken('nox'), isFalse);
    });

    test('reports an unknown name as not taken', () {
      expect(UsernameRules.isTaken('brand-new-user'), isFalse);
    });
  });

  group('UsernameRules.maxLength', () {
    test('caps the label at 32 characters', () {
      expect(UsernameRules.maxLength, 32);
    });
  });
}
