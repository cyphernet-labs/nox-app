/// Which way the app reaches its server (phase 040).
enum ConnectionPath {
  /// The server's network address (`host:port`), as before phase 040.
  direct,

  /// The server's onion address, through the Tor client built into the app.
  tor,
}
