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

  group('there is no uniqueness rule left to apply', () {
    test('the names that used to be reserved are ordinary valid names', () {
      // Person labels are not unique (owner, 2026-09-02): the server neither
      // enforces nor reports it and may never refuse a greeting over a name
      // (contract §3). The check that lived here compared against four
      // hardcoded strings, so those four were refused by a rule nothing else
      // in the system observed. Length and charset are all that remain.
      for (final name in ['admin', 'NOX', 'nox', 'User1234', 'taken', 'brand-new-user']) {
        expect(UsernameRules.hasValidCharset(name), isTrue, reason: name);
        expect(name.length <= UsernameRules.maxLength, isTrue, reason: name);
      }
    });
  });

  group('UsernameRules.maxLength', () {
    test('caps the label at 32 characters', () {
      expect(UsernameRules.maxLength, 32);
    });
  });
}
