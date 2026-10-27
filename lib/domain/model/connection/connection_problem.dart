/// Why the last attempt to reach the server failed, when the app can tell
/// (phase 045, FR-016, FR-017). Each has its own message, because each asks
/// the person to fix something different; with none known the screens say
/// only that there is no connection.
///
/// Decided by the path selector from the last failed round, and cleared by
/// the next greeting.
enum ConnectionProblem {
  /// The onion address is not a valid v3 address.
  invalidOnion,

  /// Nobody answers at the onion address: no service is published there - the
  /// address is wrong, or tor is not running on the server.
  onionNotFound,

  /// The onion service is there, and the server behind it does not answer.
  onionUnreachable,

  /// The onion address leads to a server with another key.
  otherServer,

  /// The Tor network itself cannot be reached.
  torNetwork,

  /// The direct path did not answer, `Use Tor` is off, and an onion address
  /// is known: turning `Use Tor` on is what would help.
  turnOnTor,
}
