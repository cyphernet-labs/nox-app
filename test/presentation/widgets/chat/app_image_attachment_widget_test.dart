import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/presentation/widgets/chat/app_file_chip_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_image_attachment_widget.dart';

import '../../../utils/pump_app.dart';

/// A minimal valid 1x1 PNG so Image.file has real, decodable bytes.
final Uint8List _png = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

void main() {
  testWidgets('renders an Image for a local image and taps through to onTap (F4)', (tester) async {
    final tmp = File('${Directory.systemTemp.path}/nox_thumb_test.png')..writeAsBytesSync(_png);
    addTearDown(() => tmp.existsSync() ? tmp.deleteSync() : null);
    var taps = 0;

    await pumpApp(
      tester,
      AppImageAttachmentWidget(localPath: tmp.path, type: FileType.image, name: 'thumb.png', size: '1 KB', onTap: () => taps++),
    );

    expect(find.byType(Image), findsOneWidget); // the picture, not a type-icon chip
    await tester.tap(find.byType(Image));
    expect(taps, 1); // opens the full-screen viewer
  });

  testWidgets('falls back to the file chip when the image cannot be decoded (F4/FR-007)', (tester) async {
    await tester.runAsync(() async {
      await pumpApp(
        tester,
        const AppImageAttachmentWidget(localPath: '/no/such/nox_missing.png', type: FileType.image, name: 'x.png', size: '1 KB'),
      );
      // Let the FileImage load fail so the errorBuilder swaps in the chip.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
    expect(find.byType(AppFileChipWidget), findsOneWidget); // graceful fallback, no broken image
  });
}
