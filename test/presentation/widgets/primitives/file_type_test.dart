import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_brand.dart';
import 'package:nox_app/presentation/widgets/primitives/file_type.dart';

void main() {
  group('FileType mapping', () {
    // Expected icon per type. Looping FileType.values against this map forces a
    // test update whenever a new enum case is added.
    final expectedIcons = <FileType, SvgGenImage>{
      FileType.image: NoxIcons.image,
      FileType.video: NoxIcons.videocam,
      FileType.audio: NoxIcons.musicNote,
      FileType.pdf: NoxIcons.pictureAsPdf,
      FileType.doc: NoxIcons.description,
      FileType.sheet: NoxIcons.tableChart,
      FileType.text: NoxIcons.article,
      FileType.archive: NoxIcons.folderZip,
      FileType.other: NoxIcons.draft,
    };

    // Expected decorative brand color per type. Note doc and other both map to
    // NoxBrand.tealDeep.
    final expectedColors = <FileType, Color>{
      FileType.image: NoxBrand.blue,
      FileType.video: NoxBrand.coral,
      FileType.audio: NoxBrand.amber,
      FileType.pdf: NoxBrand.red,
      FileType.doc: NoxBrand.tealDeep,
      FileType.sheet: NoxBrand.lime,
      FileType.text: NoxBrand.teal,
      FileType.archive: NoxBrand.gold,
      FileType.other: NoxBrand.tealDeep,
    };

    test('covers every FileType case', () {
      expect(expectedIcons.keys.toSet(), FileType.values.toSet());
      expect(expectedColors.keys.toSet(), FileType.values.toSet());
    });

    for (final type in FileType.values) {
      test('noxFileIcon($type) returns the expected SVG glyph', () {
        expect(noxFileIcon(type).path, expectedIcons[type]!.path);
      });

      test('noxFileColor($type) returns the expected brand color', () {
        expect(noxFileColor(type), expectedColors[type]);
      });
    }
  });
}
