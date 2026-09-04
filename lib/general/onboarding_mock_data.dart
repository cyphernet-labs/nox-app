/// MOCK-PATH ONLY. Nothing on the live path reads any of this any more.
///
/// `takenChatNames` is consulted by the mock chat datasource so the mock world
/// has something to refuse; the live path asks the server. `registeredIds`
/// survives for the screens gallery, which drives login outcomes by hand. A
/// reader who finds either on a live path has found a defect: that is exactly
/// what feature 031 removed.
///
/// The former `takenUsernames` is gone with the check that read it: person
/// labels are not unique (owner, 2026-09-02), so a list of taken ones was a
/// rule nothing in the system observed.
abstract final class OnboardingMockData {
  const OnboardingMockData._();

  /// Identifiers that resolve to an already-registered account on sign-in (2.1) —
  /// any other non-empty input is treated as a new identifier.
  static const Set<String> registeredIds = {'registered', 'demo'};

  /// Usernames reported as taken (2.3). Matching is CASE-SENSITIVE (Anna != anna,

  /// Chat names reported as taken (6.1). Charset is unrestricted (FR-041).
  static const Set<String> takenChatNames = {'General', 'Random thoughts', 'taken'};
}
