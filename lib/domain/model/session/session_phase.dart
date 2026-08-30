/// Where the live connection to the client server currently stands.
///
/// Deliberately NOT the same thing as "does the device have a network": a
/// device can be online while the socket is down, and the socket can be open
/// while the device has not yet been told what it missed. Contract v0 §3 makes
/// the distinction load-bearing — only [live] means "what you see is current".
enum SessionPhase {
  /// No socket. Either nothing has been attempted yet, or the last attempt
  /// failed and the next one is waiting out its backoff.
  disconnected,

  /// A socket is being opened and greeted; the greeting has not come back yet.
  connecting,

  /// Greeted, and the server is replaying what happened while we were away.
  /// Data on screen is still behind (contract §3, the "caught up" rule).
  catchingUp,

  /// Replay is done: every event up to the server's cursor has been applied and
  /// new ones arrive as they happen.
  live,

  /// The server refused the greeting in a way retrying cannot fix — a protocol
  /// version it does not speak, or a malformed frame. The contract marks both
  /// non-repeatable (§2.1), so the reconnect ladder stops here instead of
  /// hammering a server that will never accept this build.
  unsupported;

  /// Whether the app may present its data as current. This is the single
  /// predicate the UI's connection indicator is derived from (FR-005) — a
  /// device that is online but still catching up must not look up to date.
  bool get isCurrent => this == SessionPhase.live;
}
