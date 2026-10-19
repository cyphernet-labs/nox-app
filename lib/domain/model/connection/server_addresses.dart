import 'package:freezed_annotation/freezed_annotation.dart';

part 'server_addresses.freezed.dart';

/// Where this person's server can be reached, and how the person wants it
/// reached (contract §3, `addresses`, and the `server.addresses` event; phase
/// 045).
///
/// Two sources: what the server last said about itself - [direct], [public],
/// [onion] - and what the person changed by hand on the connection screen or
/// in Settings > Connection - [manualAddress], [manualOnion]. The server is
/// the source of truth about its own addresses: a value it states replaces
/// the hand edit of the same field, and a hand edit lasts until it does
/// (FR-015).
///
/// An address names a place, never the server: who answered is decided by the
/// channel's check of the server key on every connection, whichever path it
/// took (phase 044). That is what makes a hand edit safe.
@freezed
abstract class ServerAddresses with _$ServerAddresses {
  const ServerAddresses._();

  const factory ServerAddresses({
    /// `host:port`, IPv6 in brackets: the addresses the server found on its
    /// own networks, in its order of preference. Tried, never shown.
    @Default(<String>[]) List<String> direct,

    /// `host:port`: the public address set on the server, when there is one.
    String? public,

    /// `<56 chars>.onion:443`; null when the server offers no onion address.
    String? onion,

    /// The server address the person typed, replacing what the field would
    /// otherwise show; null when they did not change it.
    String? manualAddress,

    /// The onion address the person typed (`<56>.onion:443`); an EMPTY string
    /// when they cleared the field - no onion address, whatever the server
    /// last said - and null when they did not change it.
    String? manualOnion,

    /// `Use Tor`: Tor is tried when no direct address answers. Off unless the
    /// person turned it on (FR-011).
    @Default(false) bool useTor,

    /// The direct address that most recently answered with the right key.
    String? lastGood,

    /// The last connection greeted came through Tor - the device was away
    /// from home. The next attempt brings Tor up alongside the direct
    /// addresses rather than after them.
    @Default(false) bool viaTorLast,
  }) = _ServerAddresses;

  static const ServerAddresses empty = ServerAddresses();

  /// What the "Server address" field shows: the person's own edit, else the
  /// server's public address, else [linkAddress] - the first direct address
  /// of the pairing link (`session.server_address`).
  String? fieldAddress(String? linkAddress) => _present(manualAddress) ?? _present(public) ?? _present(linkAddress);

  /// The onion address in effect, `<56>.onion:443`: the person's edit, else
  /// the server's. Null when there is none - the person cleared the field, or
  /// nobody ever named one.
  String? get effectiveOnion {
    final manual = manualOnion;
    if (manual != null) return _present(manual);
    return _present(onion);
  }

  /// The order direct attempts go in: the address that answered last, the
  /// person's own, the public one, the ones the server found on its networks,
  /// then the address the pairing link carried - each once (phase 045).
  List<String> candidates(String? linkAddress) {
    final ordered = <String>[?lastGood, ?manualAddress, ?public, ...direct, ?linkAddress];
    final seen = <String>{};
    return [
      for (final a in ordered)
        if (a.isNotEmpty && seen.add(a)) a,
    ];
  }

  /// The onion host in effect without the port, e.g. `<56>.onion`.
  String? get onionHost {
    final o = effectiveOnion;
    if (o == null) return null;
    final colon = o.lastIndexOf(':');
    return colon < 0 ? o : o.substring(0, colon);
  }

  /// The onion service's virtual port; 443 unless the address says otherwise.
  int get onionPort {
    final o = effectiveOnion;
    if (o == null) return 443;
    final colon = o.lastIndexOf(':');
    return colon < 0 ? 443 : int.tryParse(o.substring(colon + 1)) ?? 443;
  }

  static String? _present(String? value) => value == null || value.isEmpty ? null : value;
}
