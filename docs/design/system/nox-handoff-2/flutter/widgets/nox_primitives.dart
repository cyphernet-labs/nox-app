// NOX · primitives — leaf widgets (icon, avatar, spinner, file glyph).
// Idiomatic Material 3. Colors come from Theme.of(context).colorScheme,
// text from Theme.of(context).textTheme, tokens from nox_tokens.dart.
// Hand-written to match src/m3.jsx + src/chats-parts.jsx 1:1 (not transpiled).
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'nox_brand.dart';
import 'nox_tokens.dart';

// ─────────────────────────────────────────────────────────────
// NoxIcon — Material Symbols Rounded glyph.
// FILL axis: 0 = outlined, 1 = filled (selected/active). weight 400,
// optical 24, grade 0 to match the design exactly.
// Source: src/m3.jsx <Icon>.
// ─────────────────────────────────────────────────────────────
class NoxIcon extends StatelessWidget {
  const NoxIcon(
    this.icon, {
    super.key,
    this.size = 24,
    this.color,
    this.fill = 0,
  });

  final IconData icon; // e.g. Symbols.forum
  final double size;
  final Color? color; // defaults to onSurfaceVariant
  final double fill; // 0 outlined · 1 filled

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      size: size,
      color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
      fill: fill,
      weight: 400,
      opticalSize: 24,
      grade: 0,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// NoxSpinner — indeterminate circular progress (M3 default).
// Standalone → primary; inside a FilledButton → onPrimary.
// Source: src/m3.jsx <Spinner>.
// ─────────────────────────────────────────────────────────────
class NoxSpinner extends StatelessWidget {
  const NoxSpinner({super.key, this.size = 24, this.color, this.strokeWidth = 3});
  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        color: color ?? Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Avatar — generated color + initials. Deterministic per name.
// Initials always white; no valid initials → white `forum` glyph.
// Source: src/m3.jsx <Avatar> + avatarFor/initialsFor in tokens.jsx.
// (noxAvatarColor / noxInitials live in nox_brand.dart.)
// ─────────────────────────────────────────────────────────────
class NoxAvatar extends StatelessWidget {
  const NoxAvatar({super.key, required this.name, this.size = 40});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bg = noxAvatarColor(name);
    final initials = noxInitials(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: initials != null
          ? Text(
              initials,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w500,
                fontSize: size * 0.4,
                color: Colors.white,
                height: 1,
              ),
            )
          : Icon(Symbols.forum, size: size * 0.5, color: Colors.white, fill: 1),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// File types — icon + decorative brand color per type.
// Source: src/chats-parts.jsx fileIcon() / fileColor().
// Note: audio uses music_note and `other` uses draft to match the
// shipped SVG set (nox-assets/icons/svg).
// ─────────────────────────────────────────────────────────────
enum NoxFileType { image, video, audio, pdf, doc, sheet, text, archive, other }

IconData noxFileIcon(NoxFileType t) {
  switch (t) {
    case NoxFileType.image:
      return Symbols.image;
    case NoxFileType.video:
      return Symbols.videocam;
    case NoxFileType.audio:
      return Symbols.music_note;
    case NoxFileType.pdf:
      return Symbols.picture_as_pdf;
    case NoxFileType.doc:
      return Symbols.description;
    case NoxFileType.sheet:
      return Symbols.table_chart;
    case NoxFileType.text:
      return Symbols.article;
    case NoxFileType.archive:
      return Symbols.folder_zip;
    case NoxFileType.other:
      return Symbols.draft;
  }
}

Color noxFileColor(NoxFileType t) {
  switch (t) {
    case NoxFileType.image:
      return NoxBrand.blue;
    case NoxFileType.video:
      return NoxBrand.coral;
    case NoxFileType.audio:
      return NoxBrand.amber;
    case NoxFileType.pdf:
      return NoxBrand.red;
    case NoxFileType.doc:
      return NoxBrand.tealDeep;
    case NoxFileType.sheet:
      return NoxBrand.lime;
    case NoxFileType.text:
      return NoxBrand.teal;
    case NoxFileType.archive:
      return NoxBrand.gold;
    case NoxFileType.other:
      return NoxBrand.tealDeep;
  }
}

// ─────────────────────────────────────────────────────────────
// NoxFileGlyph — type icon inside a soft tinted rounded square.
// Used in file lists (5.4) and file view (5.3).
// Source: src/chats-parts.jsx <FileGlyph>.
// ─────────────────────────────────────────────────────────────
class NoxFileGlyph extends StatelessWidget {
  const NoxFileGlyph({super.key, required this.type, this.iconSize = 24, this.box = 44});
  final NoxFileType type;
  final double iconSize;
  final double box;

  @override
  Widget build(BuildContext context) {
    final c = noxFileColor(type);
    return Container(
      width: box,
      height: box,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(box * 0.27),
      ),
      child: NoxIcon(noxFileIcon(type), size: iconSize, color: c),
    );
  }
}
