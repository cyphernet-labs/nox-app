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
  unsupported,

  /// Something answered at the paired address, but it is not this person's
  /// server: the key behind its certificate is not the one the pairing link
  /// named.
  ///
  /// Its own value, and NOT a sixth use of an existing one. Two things follow
  /// from that, and both are the point:
  ///
  /// * it is not [disconnected], so the app stops saying "no connection" over
  ///   a server that answers perfectly well and will never be accepted. The
  ///   reconnect ladder would otherwise call it for ever while the screen
  ///   blamed the network;
  /// * it is not the refusal that ends in a forced logout. That path wipes
  ///   every local message and puts the device back on the pairing screen —
  ///   so routing a bad certificate through it would hand anyone able to stand
  ///   in the middle a way to erase every device this person owns, by doing
  ///   nothing more than presenting one.
  ///
  /// Terminal, and deliberately not persisted: a fresh process tries again,
  /// because the cause may have been a captive portal or somebody's proxy.
  serverMismatch;

  /// Whether the app may present its data as current. This is the single
  /// predicate the UI's connection indicator is derived from (FR-005) — a
  /// device that is online but still catching up must not look up to date.
  bool get isCurrent => this == SessionPhase.live;

  /// Whether retrying by itself can ever help. Nothing about the connection
  /// will change on its own from here; a person has to act, or a build has to.
  bool get isTerminal => this == SessionPhase.unsupported || this == SessionPhase.serverMismatch;

  /// Whether the machine that answered is the wrong one.
  bool get isServerMismatch => this == SessionPhase.serverMismatch;
}
