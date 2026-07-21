import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/app/session_model.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/identity/identity_resolver.dart';
import 'package:nox_app/general/identity_mock_data.dart';

void main() {
  group('resolveIdentity', () {
    test('no session falls back to the sentinel id and the default label', () {
      final identity = resolveIdentity(null);
      expect(identity.id, IdentityMockData.fallbackOwnId);
      expect(identity.label, Constants.defaultUserLabel);
    });

    test('a full session passes the identifier and label through', () {
      final identity = resolveIdentity(const SessionModel(identifier: 'abc-123', label: 'Alice'));
      expect(identity.id, 'abc-123');
      expect(identity.label, 'Alice');
    });

    test('an absent label falls back to the default while the id passes through', () {
      final identity = resolveIdentity(const SessionModel(identifier: 'abc-123'));
      expect(identity.id, 'abc-123');
      expect(identity.label, Constants.defaultUserLabel);
    });

    test('an empty label is treated as absent (falls back to the default)', () {
      final identity = resolveIdentity(const SessionModel(identifier: 'abc-123', label: ''));
      expect(identity.label, Constants.defaultUserLabel);
    });

    test('an empty identifier falls back to the sentinel id', () {
      final identity = resolveIdentity(const SessionModel(identifier: '', label: 'Alice'));
      expect(identity.id, IdentityMockData.fallbackOwnId);
      expect(identity.label, 'Alice');
    });

    test('both fields are always non-empty', () {
      for (final session in <SessionModel?>[
        null,
        const SessionModel(identifier: ''),
        const SessionModel(identifier: 'x'),
        const SessionModel(identifier: 'x', label: ''),
      ]) {
        final identity = resolveIdentity(session);
        expect(identity.id, isNotEmpty);
        expect(identity.label, isNotEmpty);
      }
    });
  });
}
