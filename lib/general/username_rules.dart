import 'package:nox_app/general/onboarding_mock_data.dart';

/// Single source of truth for the public username / label rules, shared by Set
/// username (2.3) and the Settings inline name-edit (7.1): the client charset and
/// the (UI-phase, case-sensitive, mock-backed) uniqueness check. `// TODO(backend):`
/// replace [isTaken] with the real server uniqueness check.
abstract final class UsernameRules {
  static final RegExp charset = RegExp(r'^[A-Za-z0-9._-]+$');

  static const int maxLength = 32;

  static bool hasValidCharset(String name) => charset.hasMatch(name);

  /// Case-sensitive (FR-032): `Anna` != `anna`.
  static bool isTaken(String name) => OnboardingMockData.takenUsernames.contains(name);
}
