import 'package:nox_app/data/remote/channel/channel_failure.dart';

/// Where the socket dials, asked before EVERY attempt (phase 040).
///
/// One address handed over at start was enough while the server had one; now
/// it has several - the direct ones it lists, the ones the pairing link
/// carried, its onion address - and which of them leads to it changes with the
/// network the device is on. The path selector answers this; the socket only
/// dials.
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

  /// The machine at the DIRECT address [url] proved a key other than the one
  /// the pairing link named (phase 044). That means "this address does not
  /// lead home right now", never "this is not your server": addresses are
  /// reused, and the next network's 192.168.1.20 is somebody else's machine.
  void reportWrongServer(Uri url);

  /// The connection to [url] ended before it was greeted: the channel would
  /// not open, for [failure], or it went away with nothing said (null). What
  /// the next attempt makes of it - the reason a round failed (phase 045) -
  /// is the provider's business; the socket only reports.
  void reportFailed(Uri url, ChannelFailure? failure);
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
  void reportWrongServer(Uri url) {}

  @override
  void reportFailed(Uri url, ChannelFailure? failure) {}
}

/// Whether [url] names an onion service. Only there does another server key
/// mean "not your server": nobody can answer at an onion address without the
/// onion service's own keys.
bool isOnionUrl(Uri url) => url.host.toLowerCase().endsWith('.onion');
