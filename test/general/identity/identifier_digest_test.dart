import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/identity/identifier_digest.dart';

void main() {
  group('IdentifierDigest.loginRef', () {
    test('matches the vector pinned in contract v0 §3', () {
      // A self-comparison would pass no matter what the function did. This is
      // the contract's own vector, and the future Rust core checks against the
      // same one without running Dart. If it ever fails, either the formula
      // moved or the contract did - and either way every install of one person
      // silently becomes two people.
      expect(IdentifierDigest.loginRef('abc'), 'ebd1cf0d547f0c4f025f2ab7a6dd2a01d6cd4c6c32c9a7c402a09d10e70752b5');
    });

    test('is exactly 64 lowercase hex characters', () {
      final ref = IdentifierDigest.loginRef('NOX-7c1f9a4e2b8d40f3-a6e5c2179bd0e83f');
      expect(ref, isNotNull);
      expect(ref, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('is deterministic — the same identifier always derives the same ref', () {
      const identifier = 'NOX-same-every-time';
      expect(IdentifierDigest.loginRef(identifier), IdentifierDigest.loginRef(identifier));
    });

    test('different identifiers derive different refs', () {
      expect(IdentifierDigest.loginRef('one'), isNot(IdentifierDigest.loginRef('two')));
    });

    test('is domain-separated: the ref is not a bare hash of the identifier', () {
      // Without the prefix the same digest could double as some later derivation
      // of the same secret.
      expect(IdentifierDigest.loginRef('abc'), isNot(IdentifierDigest.loginRef('${IdentifierDigest.prefix}abc')));
    });

    test('an absent identifier claims nothing', () {
      expect(IdentifierDigest.loginRef(null), isNull);
      expect(IdentifierDigest.loginRef(''), isNull);
    });

    test('the raw identifier never appears inside the ref', () {
      const identifier = 'NOX-secret-value';
      expect(IdentifierDigest.loginRef(identifier), isNot(contains(identifier)));
    });
  });
}
