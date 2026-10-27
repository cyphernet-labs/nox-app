/// Fallback identity sentinel for the signed-in device when no session is available
/// (tests / a degraded session read). The real signed-in identity comes from the
/// session (`SessionModel.identifier` + `label`), resolved through `resolveIdentity`
/// (`lib/general/identity/identity_resolver.dart`); this only supplies the no-session
/// own-id so the chat thread (5.2) still renders a coherent own/other split.
///
/// [fallbackOwnId] is ALSO the raw own-author the deterministic mock seed emits
/// (`get_messages_api`), so seeded own rows and a no-session thread resolve to the
/// same own-id. When a session exists, the message repository reconciles those seed
/// rows to the session identifier at seed time.
abstract final class IdentityMockData {
  const IdentityMockData._();

  /// No-session own-id sentinel + the mock seed's raw own-author id.
  static const String fallbackOwnId = 'me';
}
