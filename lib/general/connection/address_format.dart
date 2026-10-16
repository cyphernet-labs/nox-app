import 'dart:io';
import 'dart:typed_data';

/// A server address read into its parts: `host` the way a connection dials it
/// (an IPv6 literal without its brackets, a name in lower case) and `port`.
typedef ServerAddressParts = ({String host, int port});

/// The format checks of server addresses (phase 045): the ones a person types
/// on the connection screen and in Settings > Connection, the ones the server
/// states about itself, and every one the app tries directly - one reading for
/// all of them, so no address passes one check and fails the next. Format
/// only - whether the machine at an address is this person's server is decided
/// by the channel's check of the server key on every connection, which is what
/// makes a hand edit safe.
abstract final class AddressFormat {
  const AddressFormat._();

  /// The port the onion service is reached at (contract §1).
  static const int onionPort = 443;

  static const int _maxNameLength = 253;
  static const int _maxLabelLength = 63;
  static final RegExp _label = RegExp(r'^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$');
  static final RegExp _onionHost = RegExp(r'^[a-z2-7]{56}\.onion$');
  static final RegExp _forbidden = RegExp(r'[\s/@?#\\]');
  static final RegExp _port = RegExp(r'^[0-9]{1,5}$');
  static const String _base32 = 'abcdefghijklmnopqrstuvwxyz234567';

  /// `host:port`: an IPv4 literal, an IPv6 literal in brackets, or a DNS name
  /// (labels of letters, digits and hyphens, up to 63 each and 253 in all),
  /// and a port from 1 to 65535. Never an onion name - that has a field of its
  /// own and goes through Tor or nowhere. Spaces around it are what a field
  /// holds, and do not count.
  static bool isServerAddress(String value) => parseServerAddress(value.trim()) != null;

  /// [text] read as a server address (see [isServerAddress]) exactly as it is
  /// written - nothing trimmed, which is what a stored address must be - or
  /// null when it is not one.
  ///
  /// The port is read off the text itself, never through `Uri`: a `Uri` drops
  /// its scheme's default port, so `host:443` read as `https://host:443`
  /// reports no port at all, and every address on 443 - the port a public
  /// address is the most likely to have - would be refused as portless and
  /// never tried. Digits only: `int.tryParse` alone would also take `0x1bb`,
  /// `+443` and spaces.
  static ServerAddressParts? parseServerAddress(String text) {
    if (text.isEmpty || text.contains(_forbidden)) return null;
    final colon = text.lastIndexOf(':');
    if (colon <= 0) return null;
    final digits = text.substring(colon + 1);
    if (!_port.hasMatch(digits)) return null;
    final port = int.parse(digits);
    if (port < 1 || port > 65535) return null;
    final hostPart = text.substring(0, colon);
    if (hostPart.startsWith('[') || hostPart.endsWith(']')) {
      if (!hostPart.startsWith('[') || !hostPart.endsWith(']')) return null;
      final literal = hostPart.substring(1, hostPart.length - 1);
      final ip = InternetAddress.tryParse(literal);
      return ip != null && ip.type == InternetAddressType.IPv6 ? (host: literal.toLowerCase(), port: port) : null;
    }
    // An IPv6 literal without brackets cannot be told from its own port.
    if (hostPart.contains(':')) return null;
    final ip = InternetAddress.tryParse(hostPart);
    if (ip != null) return ip.type == InternetAddressType.IPv4 ? (host: hostPart, port: port) : null;
    final name = hostPart.toLowerCase();
    return _isDnsName(name) && !name.endsWith('.onion') ? (host: name, port: port) : null;
  }

  /// The onion address as it is stored, `<56>.onion:443`, or null when
  /// [value] is not a version-3 onion address: 56 base32 characters and
  /// `.onion`, any case, with or without `:443`, whose last byte names
  /// version 3 - and, where [derive] can say, whose checksum holds: the
  /// address [derive] makes of the key the text carries must be the text
  /// itself. [derive] is the Tor module's arithmetic (`TorService
  /// .onionFromPublicKey`); null where the module is absent, and then the
  /// checksum is left to the module that dials.
  static String? normalizeOnion(String value, {String? Function(Uint8List publicKey)? derive}) {
    var text = value.trim().toLowerCase();
    if (text.endsWith(':$onionPort')) text = text.substring(0, text.length - ':$onionPort'.length);
    if (!_onionHost.hasMatch(text)) return null;
    final bytes = _decodeBase32(text.substring(0, 56));
    if (bytes == null || bytes.length != 35 || bytes[34] != 3) return null;
    final derived = derive?.call(Uint8List.sublistView(bytes, 0, 32));
    if (derived != null && derived.toLowerCase() != text) return null;
    return '$text:$onionPort';
  }

  /// What an onion field shows for a stored address: the host, `<56>.onion`.
  static String onionHostOf(String stored) {
    final colon = stored.lastIndexOf(':');
    return colon < 0 ? stored : stored.substring(0, colon);
  }

  static bool _isDnsName(String host) {
    if (host.isEmpty || host.length > _maxNameLength) return false;
    for (final label in host.split('.')) {
      if (label.isEmpty || label.length > _maxLabelLength || !_label.hasMatch(label)) return false;
    }
    return true;
  }

  /// RFC 4648 base32, lowercase alphabet, no padding; null for a character
  /// outside it.
  static Uint8List? _decodeBase32(String text) {
    final out = BytesBuilder(copy: false);
    var buffer = 0;
    var bits = 0;
    for (final unit in text.codeUnits) {
      final value = _base32.indexOf(String.fromCharCode(unit));
      if (value < 0) return null;
      buffer = (buffer << 5) | value;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.addByte((buffer >> bits) & 0xFF);
      }
      buffer &= (1 << bits) - 1;
    }
    return out.takeBytes();
  }
}
