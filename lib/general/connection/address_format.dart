import 'dart:io';
import 'dart:typed_data';

/// The format checks of the addresses a person types (phase 045): the server
/// address and the onion address of the connection screen and of Settings >
/// Connection. Format only - whether the machine at an address is this
/// person's server is decided by the channel's check of the server key on
/// every connection, which is what makes a hand edit safe.
abstract final class AddressFormat {
  const AddressFormat._();

  /// The port the onion service is reached at (contract §1).
  static const int onionPort = 443;

  static const int _maxNameLength = 253;
  static const int _maxLabelLength = 63;
  static final RegExp _label = RegExp(r'^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$');
  static final RegExp _onionHost = RegExp(r'^[a-z2-7]{56}\.onion$');
  static const String _base32 = 'abcdefghijklmnopqrstuvwxyz234567';

  /// `host:port`: an IPv4 literal, an IPv6 literal in brackets, or a DNS name
  /// (labels of letters, digits and hyphens, up to 63 each and 253 in all),
  /// and a port from 1 to 65535. Never an onion name - that has a field of its
  /// own and goes through Tor or nowhere.
  static bool isServerAddress(String value) {
    final text = value.trim();
    if (text.isEmpty || text.contains(RegExp(r'[\s/@?#\\]'))) return false;
    final colon = text.lastIndexOf(':');
    if (colon <= 0 || colon == text.length - 1) return false;
    final hostPart = text.substring(0, colon);
    final port = int.tryParse(text.substring(colon + 1));
    if (port == null || port < 1 || port > 65535 || text.substring(colon + 1).startsWith('+')) return false;
    if (hostPart.startsWith('[') || hostPart.endsWith(']')) {
      if (!hostPart.startsWith('[') || !hostPart.endsWith(']')) return false;
      final literal = InternetAddress.tryParse(hostPart.substring(1, hostPart.length - 1));
      return literal != null && literal.type == InternetAddressType.IPv6;
    }
    // An IPv6 literal without brackets cannot be told from its own port.
    if (hostPart.contains(':')) return false;
    final ip = InternetAddress.tryParse(hostPart);
    if (ip != null) return ip.type == InternetAddressType.IPv4;
    return _isDnsName(hostPart) && !hostPart.toLowerCase().endsWith('.onion');
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
