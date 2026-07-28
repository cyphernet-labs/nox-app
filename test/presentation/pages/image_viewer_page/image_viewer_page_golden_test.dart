@Tags(['golden'])
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/presentation/pages/image_viewer_page/image_viewer_page.dart';

import '../../../utils/fonts.dart';
import '../../../utils/golden.dart';
import '../../../utils/pump_app.dart';

/// Paints a deterministic [w]×[h] four-quadrant image (teal / white / dark / grey) and
/// encodes it to PNG. A real-size picture (vs a 1px sample) lets BoxFit.contain fill the
/// viewport so the golden locks the framing; the content is fixed, not a real photo
/// (F4 keeps photo pixels out of goldens). Painted at test time to avoid a huge byte
/// literal — needs tester.runAsync (real raster + PNG encode).
Future<Uint8List> _renderQuadPng(int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
  final hw = w / 2, hh = h / 2;
  void quad(double l, double t, Color c) => canvas.drawRect(Rect.fromLTWH(l, t, hw, hh), Paint()..color = c);
  quad(0, 0, const Color(0xFF0C8C84));
  quad(hw, 0, const Color(0xFFFFFFFF));
  quad(0, hh, const Color(0xFF121A1C));
  quad(hw, hh, const Color(0xFF9AA0A0));
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  setUpAll(loadNoxFonts);

  // A UNIQUE file per test: FileImage's cache key is the path, so a shared path would make
  // precacheImage serve one test's decode to the next (a landscape image rendered as the
  // earlier portrait one). Distinct paths keep each golden's picture independent.
  File pngFile(String name) => File('${Directory.systemTemp.path}/nox_viewer_$name.png');

  // Bespoke harness (not the shared goldenTest): Image.file decodes on a real IO thread,
  // which only runs under tester.runAsync — pumpAndSettle alone would snapshot a blank frame.
  for (final entry in const <(ThemeMode, String)>[(ThemeMode.light, 'light'), (ThemeMode.dark, 'dark')]) {
    final mode = entry.$1;
    final suffix = entry.$2;

    // page-mobile: the full-screen pushed viewer (scrim + AppBar close + InteractiveViewer).
    testWidgets('image_viewer_page mobile matches the $suffix theme', (tester) async {
      final tmp = pngFile('mobile_$suffix');
      addTearDown(() => tmp.existsSync() ? tmp.deleteSync() : null);
      tester.view.devicePixelRatio = 3.0;
      tester.view.physicalSize = Constants.designSize * 3.0;
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      await tester.runAsync(() async {
        tmp.writeAsBytesSync(await _renderQuadPng(360, 600));
        await pumpApp(tester, ImageViewerPage(localPath: tmp.path), themeMode: mode, settle: false);
        await precacheImage(FileImage(tmp), tester.element(find.byType(MaterialApp)));
        await tester.pumpAndSettle();
      });
      await tester.pump();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/image_viewer_page_$suffix.png'));
    });

    // page-desktop: the centered lightbox Dialog (mirrors openImageViewer's wide branch).
    testWidgets('image_viewer_page desktop matches the $suffix theme', (tester) async {
      final tmp = pngFile('desktop_$suffix');
      addTearDown(() => tmp.existsSync() ? tmp.deleteSync() : null);
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = kDesktopGoldenSize * 2.0;
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      await tester.runAsync(() async {
        tmp.writeAsBytesSync(await _renderQuadPng(640, 480));
        await pumpApp(
          tester,
          Dialog(
            insetPadding: EdgeInsets.all(AppSpacingTokens.s24),
            clipBehavior: Clip.antiAlias,
            child: ImageViewerPage(localPath: tmp.path, inDialog: true),
          ),
          themeMode: mode,
          settle: false,
        );
        await precacheImage(FileImage(tmp), tester.element(find.byType(MaterialApp)));
        await tester.pumpAndSettle();
      });
      await tester.pump();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/image_viewer_page_desktop_$suffix.png'));
    });
  }
}
