/// Single source of truth for the public username / label rules, shared by Set
/// username (2.3) and the Settings inline name-edit (7.1).
///
/// There is deliberately no uniqueness check. Person labels are NOT unique
/// (owner, 2026-09-02): the server neither enforces nor reports it, and may
/// never refuse a greeting because of a name (contract §3). The check that
/// used to live here compared against four hardcoded strings, so those four
/// names were refused by a rule nothing else in the system observed.
///
/// The design spec still states uniqueness as a product rule; that divergence
/// is open and resolves with stage-2 pairing, where the server assigns labels.
abstract final class UsernameRules {
  static final RegExp charset = RegExp(r'^[A-Za-z0-9._-]+$');

  static const int maxLength = 32;

  static bool hasValidCharset(String name) => charset.hasMatch(name);
}
