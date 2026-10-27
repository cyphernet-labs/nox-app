import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Why a pairing link could not be read.
///
/// Kept apart from a rejected token on purpose: the two ask different things
/// of the person. A link that will not parse means "scan it again"; a link
/// from a newer server means "update the app"; a token the server refuses
/// means "get a new one". One shared "it did not work" leaves them guessing.
enum PairingLinkError {
  /// Not a link at all, truncated, a length that does not add up, or a link
  /// of the formats before version 3 - a half-scanned QR, a clipped paste.
  malformed,

  /// A version above this build's. Refused rather than guessed at: a layout
  /// read under the wrong version would produce a plausible-looking address
  /// pointing anywhere.
  newerVersion,
}

/// Raised by [PairingLink.parse]. Carries [error] so the caller can pick the
/// message without matching on strings.
class PairingLinkException implements Exception {
  const PairingLinkException(this.error);

  final PairingLinkError error;

  @override
  String toString() => 'PairingLinkException(${error.name})';
}

/// One address a pairing link carries.
sealed class LinkAddress {
  const LinkAddress();
}

/// How a direct address is written in the link.
enum DirectAddressKind { ipv4, ipv6, name }

/// An address reached directly: an IP literal or a name, and a port.
final class DirectLinkAddress extends LinkAddress {
  const DirectLinkAddress({required this.kind, required this.host, required this.port});

  final DirectAddressKind kind;
  final String host;
  final int port;

  /// `host:port`, an IPv6 literal in brackets - the shape every stored
  /// address has, and the one the socket layer dials.
  String get authority => kind == DirectAddressKind.ipv6 ? '[$host]:$port' : '$host:$port';

  @override
  bool operator ==(Object other) => other is DirectLinkAddress && other.kind == kind && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(kind, host, port);
}

/// The server's onion service: its v3 public key, from which the `.onion`
/// address is derived (by the native module - see `TorService`). Always port
/// 443.
final class OnionLinkAddress extends LinkAddress {
  OnionLinkAddress(Uint8List servicePublicKey) : servicePublicKey = Uint8List.fromList(servicePublicKey);

  final Uint8List servicePublicKey;

  int get port => 443;

  @override
  bool operator ==(Object other) {
    if (other is! OnionLinkAddress || other.servicePublicKey.length != servicePublicKey.length) return false;
    for (var i = 0; i < servicePublicKey.length; i++) {
      if (other.servicePublicKey[i] != servicePublicKey[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(servicePublicKey);
}

/// What a person physically presents to pair a device (link version 3,
/// specs/044-secure-channel/contracts/pairing-link-v3.md): the server's
/// Ed25519 key, a one-time token, and where the server can be reached.
///
/// `nox://pair/<base64url without '='>` over: version (1, `0x03`) ‖ server
/// key (32) ‖ token (16) ‖ addresses, each `type (1) ‖ length (1) ‖ value`.
///
/// The server key is what every later connection is checked against: the
/// channel opens only once the machine answering has proved it, and only
/// then does the token go out. The token's TYPE is deliberately absent - the
/// server issued it and knows what it is for, and telling the presenter would
/// let a stolen link announce whether it grants ownership.
///
/// Reading is pure: no address is resolved and no onion address derived here.
class PairingLink {
  PairingLink({required Uint8List serverKey, required this.token, required List<LinkAddress> addresses})
    : serverKey = Uint8List.fromList(serverKey),
      addresses = List<LinkAddress>.unmodifiable(addresses);

  /// The only version this build reads.
  static const int version = 3;

  static const String prefix = 'nox://pair/';

  static const int _keyLength = 32;
  static const int _tokenLength = 16;
  static const int _headerLength = 1 + _keyLength + _tokenLength;

  static const int _typeIPv4 = 1;
  static const int _typeIPv6 = 2;
  static const int _typeName = 3;
  static const int _typeOnion = 4;

  /// The longest name an address may carry (a DNS name's limit).
  static const int _maxNameLength = 253;

  /// The server's Ed25519 public key.
  final Uint8List serverKey;

  /// The one-shot pairing right, base64url without padding - the form `pair`
  /// sends.
  final String token;

  /// Every address this build can read, in the link's order; types it cannot
  /// read are skipped.
  final List<LinkAddress> addresses;

  /// The server key as stored (`session.server_key`): base64.
  String get serverKeyBase64 => base64.encode(serverKey);

  /// The direct addresses in the link's order, as `host:port`: the server's
  /// public address first when it set one, then a direct one (contract §8A).
  /// The first is what the connection screen shows (phase 045).
  List<String> get directAddresses => [
    for (final address in addresses)
      if (address is DirectLinkAddress) address.authority,
  ];

  /// The onion service's public key, when the link carries one.
  Uint8List? get onionServiceKey {
    for (final address in addresses) {
      if (address is OnionLinkAddress) return address.servicePublicKey;
    }
    return null;
  }

  /// A readable link for debug surfaces, so the screens gallery can drive the
  /// scanner without a server - the contract's `minimal` vector. Not
  /// reachable from the real flow.
  static const String demo = 'nox://pair/A6CapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTwAAECAwQFBgcICQoLDA0ODwEGwKgBFCD7';

  /// Reads a link, or throws [PairingLinkException].
  static PairingLink parse(String raw) {
    final text = raw.trim();
    // The formats before version 3 (`https://nox.app/p/#…`) land here too:
    // no build reads them any more, and they read as broken, not as old.
    if (!text.startsWith(prefix)) throw const PairingLinkException(PairingLinkError.malformed);
    final payload = text.substring(prefix.length);
    if (payload.isEmpty || !_base64UrlNoPad.hasMatch(payload)) throw const PairingLinkException(PairingLinkError.malformed);
    final Uint8List bytes;
    try {
      bytes = base64Url.decode(base64Url.normalize(payload));
    } on FormatException {
      throw const PairingLinkException(PairingLinkError.malformed);
    }
    if (bytes.length < _headerLength) throw const PairingLinkException(PairingLinkError.malformed);
    final linkVersion = bytes[0];
    if (linkVersion > version) throw const PairingLinkException(PairingLinkError.newerVersion);
    if (linkVersion != version) throw const PairingLinkException(PairingLinkError.malformed);

    final serverKey = Uint8List.sublistView(bytes, 1, 1 + _keyLength);
    final token = base64Url.encode(Uint8List.sublistView(bytes, 1 + _keyLength, _headerLength)).replaceAll('=', '');
    final addresses = <LinkAddress>[];
    var offset = _headerLength;
    while (offset < bytes.length) {
      if (bytes.length - offset < 2) throw const PairingLinkException(PairingLinkError.malformed);
      final type = bytes[offset];
      final length = bytes[offset + 1];
      offset += 2;
      if (offset + length > bytes.length) throw const PairingLinkException(PairingLinkError.malformed);
      final value = Uint8List.sublistView(bytes, offset, offset + length);
      offset += length;
      final address = _address(type, value);
      if (address != null) addresses.add(address);
    }
    if (addresses.isEmpty) throw const PairingLinkException(PairingLinkError.malformed);
    return PairingLink(serverKey: serverKey, token: token, addresses: addresses);
  }

  /// Reads a link, or returns null. For places that only need to know whether
  /// a string is a usable pairing link at all, where the reason it failed
  /// changes nothing.
  static PairingLink? tryParse(String raw) {
    try {
      return parse(raw);
    } on PairingLinkException {
      return null;
    }
  }

  /// Why [raw] is not a usable link, or null when it is one.
  static PairingLinkError? refusalOf(String raw) {
    try {
      parse(raw);
      return null;
    } on PairingLinkException catch (e) {
      return e.error;
    }
  }

  /// Whether [raw] is a pairing link at all - a readable one, or one from a
  /// server newer than this build. A scanner hands both on: the second is
  /// still the person's link, and the screen that receives it says to update
  /// the app instead of calling it a stranger's QR code.
  static bool isPairingLink(String raw) => refusalOf(raw) != PairingLinkError.malformed;

  /// Renders the link: version 3, every address in order.
  String encode() {
    final out = BytesBuilder(copy: false)
      ..addByte(version)
      ..add(serverKey)
      ..add(base64Url.decode(base64Url.normalize(token)));
    for (final address in addresses) {
      switch (address) {
        case DirectLinkAddress(:final kind, :final host, :final port):
          final value = switch (kind) {
            DirectAddressKind.ipv4 || DirectAddressKind.ipv6 => InternetAddress(host).rawAddress,
            DirectAddressKind.name => utf8.encode(host),
          };
          out
            ..addByte(switch (kind) {
              DirectAddressKind.ipv4 => _typeIPv4,
              DirectAddressKind.ipv6 => _typeIPv6,
              DirectAddressKind.name => _typeName,
            })
            ..addByte(value.length + 2)
            ..add(value)
            ..addByte((port >> 8) & 0xFF)
            ..addByte(port & 0xFF);
        case OnionLinkAddress(:final servicePublicKey):
          out
            ..addByte(_typeOnion)
            ..addByte(servicePublicKey.length)
            ..add(servicePublicKey);
      }
    }
    return prefix + base64Url.encode(out.takeBytes()).replaceAll('=', '');
  }

  /// One address, or null for a type this build does not know - skipped by
  /// its length, so a newer server can add kinds without breaking this build.
  static LinkAddress? _address(int type, Uint8List value) {
    switch (type) {
      case _typeIPv4:
        if (value.length != 4 + 2) throw const PairingLinkException(PairingLinkError.malformed);
        return DirectLinkAddress(kind: DirectAddressKind.ipv4, host: value.sublist(0, 4).join('.'), port: _port(value));
      case _typeIPv6:
        if (value.length != 16 + 2) throw const PairingLinkException(PairingLinkError.malformed);
        final host = InternetAddress.fromRawAddress(Uint8List.fromList(value.sublist(0, 16)), type: InternetAddressType.IPv6).address;
        return DirectLinkAddress(kind: DirectAddressKind.ipv6, host: host, port: _port(value));
      case _typeName:
        final nameLength = value.length - 2;
        if (nameLength < 1 || nameLength > _maxNameLength) throw const PairingLinkException(PairingLinkError.malformed);
        final String name;
        try {
          name = utf8.decode(value.sublist(0, nameLength));
        } on FormatException {
          throw const PairingLinkException(PairingLinkError.malformed);
        }
        return DirectLinkAddress(kind: DirectAddressKind.name, host: name, port: _port(value));
      case _typeOnion:
        if (value.length != _keyLength) throw const PairingLinkException(PairingLinkError.malformed);
        return OnionLinkAddress(value);
      default:
        return null;
    }
  }

  /// The big-endian port at the end of [value]; port 0 is no address.
  static int _port(Uint8List value) {
    final port = (value[value.length - 2] << 8) | value[value.length - 1];
    if (port == 0) throw const PairingLinkException(PairingLinkError.malformed);
    return port;
  }

  static final RegExp _base64UrlNoPad = RegExp(r'^[A-Za-z0-9_-]+$');
}
