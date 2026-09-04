import 'dart:convert';
import 'dart:typed_data';

/// Why a pairing link could not be read.
///
/// Kept apart from a rejected token on purpose: the two ask different things
/// of the person. A link that will not parse means "scan it again"; a token
/// the server refuses means "get a new one". One shared "it did not work"
/// leaves them guessing which.
enum PairingLinkError {
  /// Not a link at all, or truncated - a half-scanned QR, a clipped paste.
  malformed,

  /// A version this build does not know. Refused rather than guessed at: a
  /// layout read under the wrong version would produce a plausible-looking
  /// address pointing anywhere.
  unsupportedVersion,
}

/// Raised by [PairingLink.parse]. Carries [error] so the caller can pick the
/// message without matching on strings.
class PairingLinkException implements Exception {
  const PairingLinkException(this.error);

  final PairingLinkError error;

  @override
  String toString() => 'PairingLinkException(${error.name})';
}

/// What a person physically presents to sign in: where the server is, which
/// key it will be pinned against, and the one-shot right to pair.
///
/// Contract §8A. The token's TYPE is deliberately absent — the server issued
/// it and knows what it is for, and telling the presenter would let a stolen
/// link announce whether it grants ownership.
class PairingLink {
  const PairingLink({required this.host, required this.port, required this.serverKey, required this.token});

  /// Version this build writes and is willing to read.
  static const int version = 1;

  static const String _prefix = 'https://nox.app/p/#';

  static const int _hostTypeIPv4 = 1;
  static const int _hostTypeIPv6 = 2;
  static const int _hostTypeDns = 3;

  final String host;
  final int port;

  /// The server's public key, base64. Parsed and kept, but nothing verifies it
  /// yet: there is nothing to pin against while the transport is not TLS. It
  /// travels now so that pinning arriving later changes no format and forces
  /// nobody to pair again.
  final String serverKey;

  /// The one-shot pairing right, base64url without padding.
  final String token;

  /// The address to connect to, as the socket layer wants it.
  String get authority => host.contains(':') ? '[$host]:$port' : '$host:$port';

  /// Reads a link, or throws [PairingLinkException].
  ///
  /// Accepts the bare fragment as well as the whole link: a person pasting by
  /// hand may well copy only the part after the `#`, and refusing that would
  /// be pedantry rather than safety.
  static PairingLink parse(String raw) {
    var payload = raw.trim();
    if (payload.startsWith(_prefix)) {
      payload = payload.substring(_prefix.length);
    } else if (payload.contains('#')) {
      payload = payload.substring(payload.indexOf('#') + 1);
    }
    if (payload.isEmpty) throw const PairingLinkException(PairingLinkError.malformed);

    final Uint8List bytes;
    try {
      bytes = base64Url.decode(base64Url.normalize(payload));
    } on FormatException {
      throw const PairingLinkException(PairingLinkError.malformed);
    }

    // Shortest possible: version + type + 4 host + 2 port + 32 key + 16 token.
    if (bytes.length < 55) throw const PairingLinkException(PairingLinkError.malformed);
    if (bytes[0] != version) throw const PairingLinkException(PairingLinkError.unsupportedVersion);

    var offset = 2;
    final String host;
    switch (bytes[1]) {
      case _hostTypeIPv4:
        if (bytes.length < offset + 4) throw const PairingLinkException(PairingLinkError.malformed);
        host = bytes.sublist(offset, offset + 4).join('.');
        offset += 4;
      case _hostTypeIPv6:
        if (bytes.length < offset + 16) throw const PairingLinkException(PairingLinkError.malformed);
        final groups = <String>[];
        for (var i = 0; i < 16; i += 2) {
          groups.add(((bytes[offset + i] << 8) | bytes[offset + i + 1]).toRadixString(16));
        }
        host = groups.join(':');
        offset += 16;
      case _hostTypeDns:
        if (bytes.length < offset + 1) throw const PairingLinkException(PairingLinkError.malformed);
        final length = bytes[offset];
        offset += 1;
        if (length == 0 || bytes.length < offset + length) throw const PairingLinkException(PairingLinkError.malformed);
        host = utf8.decode(bytes.sublist(offset, offset + length), allowMalformed: true);
        offset += length;
      default:
        // An address whose type this build cannot read is not a malformed
        // link - it is a newer shape of a valid one.
        throw const PairingLinkException(PairingLinkError.unsupportedVersion);
    }

    if (bytes.length != offset + 2 + 32 + 16) throw const PairingLinkException(PairingLinkError.malformed);

    final port = (bytes[offset] << 8) | bytes[offset + 1];
    offset += 2;
    final key = base64.encode(bytes.sublist(offset, offset + 32));
    offset += 32;
    final token = base64Url.encode(bytes.sublist(offset, offset + 16)).replaceAll('=', '');

    return PairingLink(host: host, port: port, serverKey: key, token: token);
  }

  /// Renders the link, so a device can show an invite it just obtained.
  String encode() {
    final out = <int>[version];
    final ipv4 = _asIPv4(host);
    if (ipv4 != null) {
      out.addAll([_hostTypeIPv4, ...ipv4]);
    } else if (host.contains(':')) {
      out.add(_hostTypeIPv6);
      for (final group in host.split(':')) {
        final value = int.parse(group.isEmpty ? '0' : group, radix: 16);
        out.addAll([(value >> 8) & 0xFF, value & 0xFF]);
      }
    } else {
      final name = utf8.encode(host);
      out.addAll([_hostTypeDns, name.length, ...name]);
    }
    out.addAll([(port >> 8) & 0xFF, port & 0xFF]);
    out.addAll(base64.decode(serverKey));
    out.addAll(base64Url.decode(base64Url.normalize(token)));
    return _prefix + base64Url.encode(out).replaceAll('=', '');
  }

  static List<int>? _asIPv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return null;
    final octets = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) return null;
      octets.add(value);
    }
    return octets;
  }
}
