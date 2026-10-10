import 'package:freezed_annotation/freezed_annotation.dart';

part 'server_addresses.freezed.dart';

/// Where this person's server can be reached, as it last told us (contract §3,
/// `addresses`, and the `server.addresses` event).
///
/// An address names a place, never the server: who answered is decided by the
/// channel's check of the server key on every connection, whichever path it
/// took (phase 044).
@freezed
abstract class ServerAddresses with _$ServerAddresses {
  const ServerAddresses._();

  const factory ServerAddresses({
    /// `host:port`, IPv6 in brackets, in the server's order of preference.
    @Default(<String>[]) List<String> direct,

    /// `<56 chars>.onion:443`; null when the server offers no onion address.
    String? onion,

    /// The direct address that most recently answered with the right key.
    String? lastGood,

    /// The last connection greeted came through Tor - the device was away
    /// from home. The next attempt brings Tor up alongside the direct
    /// addresses rather than after them.
    @Default(false) bool viaTorLast,
  }) = _ServerAddresses;

  static const ServerAddresses empty = ServerAddresses();

  /// The order direct attempts go in: the address that answered last, then
  /// the server's list, then the address the pairing link carried - each once.
  List<String> candidates(String? linkAddress) {
    final ordered = <String>[?lastGood, ...direct, ?linkAddress];
    final seen = <String>{};
    return [
      for (final a in ordered)
        if (a.isNotEmpty && seen.add(a)) a,
    ];
  }

  /// The onion host without the port, e.g. `<56>.onion`.
  String? get onionHost {
    final o = onion;
    if (o == null) return null;
    final colon = o.lastIndexOf(':');
    return colon < 0 ? o : o.substring(0, colon);
  }

  /// The onion service's virtual port; 443 unless the address says otherwise.
  int get onionPort {
    final o = onion;
    if (o == null) return 443;
    final colon = o.lastIndexOf(':');
    return colon < 0 ? 443 : int.tryParse(o.substring(colon + 1)) ?? 443;
  }
}
