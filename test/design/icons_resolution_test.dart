import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/nox_icons.dart';

/// US1 / FR-001..FR-003 / SC-001 — icons bundled, resolvable, recolorable.
void main() {
  final iconsDir = Directory('assets/svg/icons');

  test('all 37 icon SVGs are bundled', () {
    final svgs = iconsDir.listSync().whereType<File>().where((f) => f.path.endsWith('.svg')).toList();
    expect(svgs.length, 37, reason: 'expected 37 bundled icon SVGs');
  });

  test('every bundled icon SVG uses currentColor and bakes no color (FR-003)', () {
    for (final f in iconsDir.listSync().whereType<File>().where((f) => f.path.endsWith('.svg'))) {
      final svg = f.readAsStringSync();
      expect(svg.contains('fill="currentColor"'), isTrue, reason: '${f.path}: missing fill="currentColor"');
      expect(RegExp(r'fill="#').hasMatch(svg), isFalse, reason: '${f.path}: has a hardcoded hex fill');
    }
  });

  test('NoxIcons covers the 35 referenced glyphs and each resolves to an existing asset', () {
    final registry = <SvgGenImage>[
      NoxIcons.forum,
      NoxIcons.forumFill,
      NoxIcons.settings,
      NoxIcons.settingsFill,
      NoxIcons.add,
      NoxIcons.arrowBack,
      NoxIcons.contentPaste,
      NoxIcons.qrCodeScanner,
      NoxIcons.attachFile,
      NoxIcons.sendFill,
      NoxIcons.flashlightOnFill,
      NoxIcons.flashlightOff,
      NoxIcons.cameraswitch,
      NoxIcons.search,
      NoxIcons.visibility,
      NoxIcons.visibilityOff,
      NoxIcons.contentCopy,
      NoxIcons.qrCode,
      NoxIcons.download,
      NoxIcons.edit,
      NoxIcons.close,
      NoxIcons.schedule,
      NoxIcons.check,
      NoxIcons.error,
      NoxIcons.image,
      NoxIcons.videocam,
      NoxIcons.musicNote,
      NoxIcons.pictureAsPdf,
      NoxIcons.description,
      NoxIcons.tableChart,
      NoxIcons.article,
      NoxIcons.folderZip,
      NoxIcons.draft,
      NoxIcons.chatBubble,
      NoxIcons.folderOpen,
    ];
    expect(registry.length, 35, reason: 'NoxIcons should expose the 35 referenced glyphs');
    for (final icon in registry) {
      expect(File(icon.path).existsSync(), isTrue, reason: '${icon.path}: asset not found');
    }
  });

  test('count reconciliation: the 2 unreferenced outlined variants are bundled (35 + 2 = 37)', () {
    expect(File('assets/svg/icons/flashlight_on.svg').existsSync(), isTrue);
    expect(File('assets/svg/icons/send.svg').existsSync(), isTrue);
  });
}
