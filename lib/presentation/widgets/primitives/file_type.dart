import 'package:flutter/material.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_brand.dart';
import 'package:nox_app/domain/model/file/file_type.dart';

// FileType is the domain single source of truth; re-export it so existing callers
// (file chip / glyph / gallery / tests) keep importing it from here alongside the
// presentation mappers below.
export 'package:nox_app/domain/model/file/file_type.dart';

/// Type icon (SVG glyph from the [NoxIcons] registry) for [type].
/// `audio` → music_note, `other` → draft, to match the shipped SVG set.
SvgGenImage noxFileIcon(FileType type) {
  switch (type) {
    case FileType.image:
      return NoxIcons.image;
    case FileType.video:
      return NoxIcons.videocam;
    case FileType.audio:
      return NoxIcons.musicNote;
    case FileType.pdf:
      return NoxIcons.pictureAsPdf;
    case FileType.doc:
      return NoxIcons.description;
    case FileType.sheet:
      return NoxIcons.tableChart;
    case FileType.text:
      return NoxIcons.article;
    case FileType.archive:
      return NoxIcons.folderZip;
    case FileType.other:
      return NoxIcons.draft;
  }
}

/// Decorative brand color (outside the ColorScheme) for [type].
Color noxFileColor(FileType type) {
  switch (type) {
    case FileType.image:
      return NoxBrand.blue;
    case FileType.video:
      return NoxBrand.coral;
    case FileType.audio:
      return NoxBrand.amber;
    case FileType.pdf:
      return NoxBrand.red;
    case FileType.doc:
      return NoxBrand.tealDeep;
    case FileType.sheet:
      return NoxBrand.lime;
    case FileType.text:
      return NoxBrand.teal;
    case FileType.archive:
      return NoxBrand.gold;
    case FileType.other:
      return NoxBrand.tealDeep;
  }
}
