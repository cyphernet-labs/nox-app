import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/nox_icons.dart';

/// US1 / FR-001..FR-003 / SC-001 — icons bundled, resolvable, recolorable.
void main() {
  final iconsDir = Directory('assets/svg/icons');

  test('all 43 icon SVGs are bundled', () {
    final svgs = iconsDir.listSync().whereType<File>().where((f) => f.path.endsWith('.svg')).toList();
    expect(svgs.length, 43, reason: 'expected 43 bundled icon SVGs');
  });

  test('every bundled icon SVG uses currentColor and bakes no color (FR-003)', () {
    for (final f in iconsDir.listSync().whereType<File>().where((f) => f.path.endsWith('.svg'))) {
      final svg = f.readAsStringSync();
      expect(svg.contains('fill="currentColor"'), isTrue, reason: '${f.path}: missing fill="currentColor"');
      expect(RegExp(r'fill="#').hasMatch(svg), isFalse, reason: '${f.path}: has a hardcoded hex fill');
    }
  });

  test('NoxIcons covers the 41 referenced glyphs and each resolves to an existing asset', () {
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
      NoxIcons.noPhotography,
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
      NoxIcons.notifications,
      NoxIcons.notificationsOff,
      NoxIcons.wifiOff,
      NoxIcons.chevronRight,
      NoxIcons.smartphone,
    ];
    expect(registry.length, 41, reason: 'NoxIcons should expose the 41 referenced glyphs');
    for (final icon in registry) {
      expect(File(icon.path).existsSync(), isTrue, reason: '${icon.path}: asset not found');
    }
  });

  test('NoxIcons exposes exactly 41 getters (parsed from source — catches silent drift)', () {
    final src = File('lib/design/nox_icons.dart').readAsStringSync();
    final getters = RegExp(r'static SvgGenImage get ').allMatches(src).length;
    expect(getters, 41, reason: 'NoxIcons getter count must match the verified registry');
  });

  test('count reconciliation: the 2 unreferenced outlined variants are bundled (41 + 2 = 43)', () {
    expect(File('assets/svg/icons/flashlight_on.svg').existsSync(), isTrue);
    expect(File('assets/svg/icons/send.svg').existsSync(), isTrue);
  });
}
