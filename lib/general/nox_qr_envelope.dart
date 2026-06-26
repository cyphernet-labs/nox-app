/// Codec for the NOX identity QR payload: `nox://id/<percent-encoded identifier>`.
///
/// Shared by the generator (Show QR, 7.1 — [encode]) and the scanner (2.2 —
/// [decode]) so a code shown on one device round-trips exactly to the id the
/// other device signs in with. Pure string<->string transform: no DI, no codegen,
/// no app_links/routing. Recognizing the envelope is NOT identifier-format
/// validation (009 FR-011 — the identifier stays opaque).
abstract final class NoxQrEnvelope {
  const NoxQrEnvelope._();

  static const String _scheme = 'nox';
  static const String _type = 'id'; // the authority/host segment

  /// `id` -> `nox://id/<Uri.encodeComponent(id)>`. Encodes the full component
  /// charset (`/`, `:`, `?`, `#`, space, unicode) so the path is always a single
  /// segment. An empty id yields the unscannable `nox://id/`; callers (7.1) must
  /// not encode an empty identifier (Settings is reachable only when authorized,
  /// so the id is non-empty; a `rawId.isNotEmpty` gate guards the edge).
  static String encode(String identifier) => '$_scheme://$_type/${Uri.encodeComponent(identifier)}';

  /// Envelope -> identifier, or `null` when [raw] is not a valid non-empty
  /// `nox://id/` envelope (foreign QR, empty id, malformed). Never throws.
  static String? decode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } on FormatException {
      return null;
    }

    if (uri.scheme != _scheme || uri.host != _type) return null;
    if (uri.pathSegments.length != 1) return null;
    // `pathSegments` is already percent-decoded EXACTLY once — never call
    // Uri.decodeComponent on it (double-decode would corrupt a literal `%xx`).
    final identifier = uri.pathSegments.first;
    return identifier.isEmpty ? null : identifier;
  }
}
