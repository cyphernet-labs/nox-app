/// Fixed mock data driving the happy/taken path of the UI-only onboarding-form
/// availability checks (2.1 sign-in, 2.3 username, 6.1 chat name). It exists only
/// so typing specific values reproduces every state deterministically; it is
/// replaced by a real repository in the backend phase.
//
// TODO(backend): replace with real server uniqueness / sign-in checks.
abstract final class OnboardingMockData {
  const OnboardingMockData._();

  /// Identifiers that resolve to an already-registered account on sign-in (2.1) —
  /// any other non-empty input is treated as a new identifier.
  static const Set<String> registeredIds = {'registered', 'demo'};

  /// Usernames reported as taken (2.3). Matching is CASE-SENSITIVE (Anna != anna,
  /// FR-032) — callers compare with `contains` against the raw input.
  static const Set<String> takenUsernames = {'admin', 'NOX', 'User1234', 'taken'};

  /// Chat names reported as taken (6.1). Charset is unrestricted (FR-041).
  static const Set<String> takenChatNames = {'General', 'Random thoughts', 'taken'};
}
