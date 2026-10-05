/// Where the socket dials, asked before EVERY attempt (phase 040).
///
/// One address handed over at start was enough while the server had one; now
/// it has several - the direct ones it lists, the one the pairing link carried,
/// its onion address - and which of them leads to it changes with the network
/// the device is on. The path selector answers this; the socket only dials.
abstract class SocketTargetProvider {
  /// The next address to dial, or null when there is no path right now. The
  /// socket then waits on its reconnect ladder and asks again.
  Future<Uri?> nextTarget();

  /// True while the path being brought up is the slow one - Tor and a circuit
  /// to the server. A command sent meanwhile waits for it instead of failing on
  /// the short command timeout (FR-023).
  bool get bringingUpSlowPath;

  /// The connection to [url] was greeted: the path works.
  void reportGreeted(Uri url);

  /// The machine at the DIRECT address [url] presented a key the pairing link
  /// did not name. That means "this address does not lead home right now",
  /// never "this is not your server" (FR-005): addresses are reused, and the
  /// next network's 192.168.1.20 is somebody else's machine.
  void reportPinRefused(Uri url);
}

/// One address, always: the shape every connection had before phase 040, and
/// what tests and tools that know a single address still use.
class FixedSocketTarget implements SocketTargetProvider {
  const FixedSocketTarget(this.url);

  final Uri url;

  @override
  Future<Uri?> nextTarget() async => url;

  @override
  bool get bringingUpSlowPath => false;

  @override
  void reportGreeted(Uri url) {}

  @override
  void reportPinRefused(Uri url) {}
}

/// Whether [url] names an onion service. Only there does a refused pin mean
/// "not your server" (FR-030): nobody can hold an onion address without the
/// server's own keys.
bool isOnionUrl(Uri url) => url.host.toLowerCase().endsWith('.onion');
