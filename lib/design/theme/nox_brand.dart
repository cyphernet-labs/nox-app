// GENERATED — NOX brand-fixed colors + deterministic avatar logic.
// Sources: tokens/brand.tokens.json, tokens/avatars.tokens.json.
// These are NOT themed (except where noted) — they sit outside the ColorScheme.
import 'package:flutter/material.dart';

abstract final class NoxBrand {
  static const Color teal = Color(0xFF12B4B4);
  static const Color tealDeep = Color(0xFF0E7C7C);
  static const Color gold = Color(0xFFF4C20C);
  static const Color amber = Color(0xFFFBB00C);
  static const Color coral = Color(0xFFFB7A12);
  static const Color red = Color(0xFFE11D1D);
  static const Color lime = Color(0xFF8FA50C);
  static const Color blue = Color(0xFF2E6FB0);
  static const Color white = Color(0xFFFAFAFA);
  static const Color canvasDark = Color(0xFF0C2424);
  static const Color ink = Color(0xFF0C0C0C);
  static const Color qrSurface = Color(0xFFFFFFFF);
  static const Color qrInk = Color(0xFF0C0C0C);
}

/// Generated-avatar backgrounds (avatar-only). Initials are always white.
const List<Color> noxAvatarPalette = [
  Color(0xFF0E7C7C),
  Color(0xFF8A6A00),
  Color(0xFFAD4A15),
  Color(0xFF5C7300),
  Color(0xFF2E6FB0),
  Color(0xFFC0392B),
  Color(0xFF7A4DB3),
  Color(0xFF1E7268),
];

/// Deterministic palette index from a name. Mirrors src/tokens.jsx exactly:
/// h = (h * 31 + charCodeAt(i)) >>> 0 ; index = h % 8.
int noxAvatarIndex(String name) {
  int h = 0;
  for (final cu in name.codeUnits) {
    h = (h * 31 + cu) & 0xFFFFFFFF;
  }
  return h % noxAvatarPalette.length;
}

Color noxAvatarColor(String name) => noxAvatarPalette[noxAvatarIndex(name)];

/// 1–2 initials: first letters of the first two words, else first 1–2
/// alphanumerics. Returns null → caller shows the `forum` glyph fallback.
String? noxInitials(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return null;
  final words = trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final alnum = RegExp(r'[A-Za-z0-9]');
  if (words.length >= 2) {
    final a = words[0][0], b = words[1][0];
    if (alnum.hasMatch(a) && alnum.hasMatch(b)) return (a + b).toUpperCase();
  }
  final matches = alnum.allMatches(name).map((m) => m.group(0)!).take(2).toList();
  return matches.isEmpty ? null : matches.join().toUpperCase();
}

/// Account-avatar initials — DISTINCT from the chat-row [noxInitials]. Tokenizes
/// the display `label` on whitespace and the `.`, `_`, `-` separators (NOX labels
/// have no spaces, charset `[A-Za-z0-9._-]`), then takes the first alphanumeric
/// letter of the FIRST and LAST token (2 letters); a single token yields ONE
/// letter. Returns null when no alphanumeric letter exists (caller shows the
/// `forum` glyph fallback). Examples: `User7421`→`U`, `john.doe`→`JD`,
/// `john_doe_smith`→`JS`, `Alice`→`A`.
String? noxAccountInitials(String label) {
  final alnum = RegExp(r'[A-Za-z0-9]');
  final letters = label.split(RegExp(r'[\s._-]+')).map((token) => alnum.firstMatch(token)?.group(0)).whereType<String>().toList();
  if (letters.isEmpty) return null;
  if (letters.length == 1) return letters.first.toUpperCase();
  return (letters.first + letters.last).toUpperCase();
}
