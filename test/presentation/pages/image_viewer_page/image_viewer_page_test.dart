import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/image_viewer_page/image_viewer_page.dart';

import '../../../utils/pump_app.dart';

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
  final l10nEn = AppLocalizationsEn();

  testWidgets('shows a zoomable InteractiveViewer around the image (F4)', (tester) async {
    final tmp = File('${Directory.systemTemp.path}/nox_viewer_test.png')..writeAsBytesSync(_png);
    addTearDown(() => tmp.existsSync() ? tmp.deleteSync() : null);

    await pumpApp(tester, ImageViewerPage(localPath: tmp.path));

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('a missing file shows a graceful placeholder, not a crash (F4/FR-007)', (tester) async {
    await tester.runAsync(() async {
      await pumpApp(tester, const ImageViewerPage(localPath: '/no/such/nox_viewer_missing.png'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
    expect(find.text(l10nEn.imageUnavailable), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
