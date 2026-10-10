import 'package:nox_app/domain/model/connection/server_addresses.dart';

/// Reads the `addresses` object - the greeting's field and the payload of the
/// `server.addresses` event, which are the same shape (contract §3, §8A):
/// `{direct: [...], public?: "host:port", onion?: "<56>.onion:443"}`.
///
/// Lenient the way the rest of the greeting is: a malformed entry is dropped,
/// never a reason to refuse the reply. The object arrives over the verified
/// channel, so nobody but the server can have written it; the checks below
/// keep a bug on either side from becoming an address the app dials.
abstract final class ServerAddressesParser {
  /// The contract's ceiling; anything past it is a peer that does not follow
  /// the contract, and the least likely addresses anyway (they come last).
  static const int maxDirect = 16;

  static final RegExp _onion = RegExp(r'^[a-z2-7]{56}\.onion(:[0-9]{1,5})?$');

  /// Null when [raw] is not an object at all - the server did not state its
  /// addresses, which is also how a server older than phase 039 looks.
  static ServerAddresses? parse(Object? raw) {
    if (raw is! Map) return null;
    final direct = <String>[];
    final list = raw['direct'];
    if (list is List) {
      for (final entry in list) {
        if (direct.length >= maxDirect) break;
        if (entry is String && isHostPort(entry) && !direct.contains(entry)) direct.add(entry);
      }
    }
    return ServerAddresses(direct: List<String>.unmodifiable(direct), public: _publicOf(raw['public']), onion: _onionOf(raw['onion']));
  }

  /// `host:port` with an explicit, valid port; IPv6 in brackets.
  static bool isHostPort(String value) {
    if (value.isEmpty || value.contains('/') || value.contains('@')) return false;
    final uri = Uri.tryParse('https://$value');
    if (uri == null || uri.host.isEmpty || !uri.hasPort) return false;
    return uri.port > 0 && uri.port <= 65535;
  }

  /// The public address (phase 045): `host:port`, an onion name never - that
  /// goes through Tor or nowhere.
  static String? _publicOf(Object? raw) {
    if (raw is! String) return null;
    final value = raw.trim();
    if (!isHostPort(value) || value.toLowerCase().contains('.onion')) return null;
    return value;
  }

  static String? _onionOf(Object? raw) {
    if (raw is! String) return null;
    final value = raw.toLowerCase();
    if (!_onion.hasMatch(value)) return null;
    final colon = value.lastIndexOf(':');
    if (colon < 0) return '$value:443';
    final port = int.parse(value.substring(colon + 1));
    return port > 0 && port <= 65535 ? value : null;
  }
}
