@Tags(['golden'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/presentation/widgets/chat/app_image_attachment_widget.dart';

import '../../../utils/fonts.dart';
import '../../../utils/pump_app.dart';

/// A deterministic 2×2 RGBA PNG (four opaque quadrants: teal / white / dark / grey).
/// BoxFit.cover stretches it across the thumbnail box, so the golden locks the picture
/// framing (rounded corners, cover-fit, orientation) with a fixed, content-stable image
/// — a real user photo would be non-deterministic (F4 exempts the viewer for that reason).
final Uint8List _quadPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x02, 0x08, 0x06, 0x00, 0x00, 0x00, 0x72, 0xB6, 0x0D, //
  0x24, 0x00, 0x00, 0x00, 0x18, 0x49, 0x44, 0x41, 0x54, 0x78, 0xDA, 0x63, 0xE0, 0xE9, 0x69, 0xF9, //
  0x0F, 0x02, 0x0C, 0x42, 0x52, 0x32, 0xFF, 0x67, 0x2D, 0x58, 0xF0, 0x1F, 0x00, 0x5A, 0x8E, 0x0A, //
  0x38, 0xD0, 0xDC, 0xD5, 0xC1, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// Both live variants of the widget: the in-bubble thumbnail (tap → viewer) and the
/// compact composer draft (a removable × overlay). See P2/F4.
Widget _content(String path) => Padding(
  padding: const EdgeInsets.all(16),
  child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AppImageAttachmentWidget(localPath: path, type: FileType.image, name: 'photo.png', size: '128 KB', onTap: () {}),
      const SizedBox(height: 24),
      AppImageAttachmentWidget(
        localPath: path,
        type: FileType.image,
        name: 'photo.png',
        size: '128 KB',
        width: 72,
        height: 72,
        onRemove: () {},
      ),
    ],
  ),
);

void main() {
  setUpAll(loadNoxFonts);

  late File tmp;
  setUp(() => tmp = File('${Directory.systemTemp.path}/nox_p9_thumb.png')..writeAsBytesSync(_quadPng));
  tearDown(() => tmp.existsSync() ? tmp.deleteSync() : null);

  // A bespoke harness (not the shared goldenTest): Image.file decodes on a real IO thread,
  // which only runs under tester.runAsync — pumpAndSettle alone would snapshot a blank box.
  for (final entry in const <(ThemeMode, String)>[(ThemeMode.light, 'light'), (ThemeMode.dark, 'dark')]) {
    final mode = entry.$1;
    final suffix = entry.$2;
    testWidgets('app_image_attachment_widget golden matches the $suffix theme', (tester) async {
      tester.view.devicePixelRatio = 3.0;
      tester.view.physicalSize = Constants.designSize * 3.0;
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      await tester.runAsync(() async {
        await pumpApp(tester, _content(tmp.path), themeMode: mode, settle: false);
        // Force the file image to decode before the snapshot.
        await precacheImage(FileImage(tmp), tester.element(find.byType(MaterialApp)));
        await tester.pumpAndSettle();
      });
      await tester.pump();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/app_image_attachment_widget_$suffix.png'));
    });
  }
}
