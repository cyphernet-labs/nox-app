import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/service/qr_image_decode_service_impl.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/general/nox_qr_envelope.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Real QR-from-image decode (P14): render the app's own generator (QrPainter) to a PNG
/// file, then decode it back through the service — the Windows/Linux sign-in round-trip,
/// exercised headless on the desktop host. DI is configured so the impl's LogRepository
/// fallback (in the corrupt-image path) resolves.
Future<String> _writeQrPng(String data, double size, String name) async {
  final painter = QrPainter(data: data, version: QrVersions.auto, gapless: true);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Rect.fromLTWH(0, 0, size, size), Paint()..color = const Color(0xFFFFFFFF)); // white bg
  painter.paint(canvas, Size(size, size));
  final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
  final png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  final file = File('${Directory.systemTemp.path}/$name')..writeAsBytesSync(png);
  return file.path;
}

Future<String> _writeBlankPng(double size, String name) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Rect.fromLTWH(0, 0, size, size), Paint()..color = const Color(0xFFEFEFEF));
  final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
  final png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  final file = File('${Directory.systemTemp.path}/$name')..writeAsBytesSync(png);
  return file.path;
}

void main() {
  late QrImageDecodeServiceImpl service;
  final temp = <String>[];

  setUp(() async {
    await configureDependencies(Environment.test);
    service = QrImageDecodeServiceImpl();
  });

  tearDown(() async {
    for (final p in temp) {
      final f = File(p);
      if (f.existsSync()) f.deleteSync();
    }
    temp.clear();
    await getIt.reset();
  });

  testWidgets('decodes a NOX identity QR from a rendered image file (round-trip)', (tester) async {
    const id = 'User7421-abc.def_GHI-0123456789';
    final env = NoxQrEnvelope.encode(id);
    await tester.runAsync(() async {
      final path = await _writeQrPng(env, 512, 'nox_qr_ok.png');
      temp.add(path);
      final raw = await service.decodeQr(path);
      expect(raw, env); // the exact QR payload
      expect(NoxQrEnvelope.decode(raw!), id); // resolves back to the identifier
    });
  });

  testWidgets('returns null for an image that carries no QR', (tester) async {
    await tester.runAsync(() async {
      final path = await _writeBlankPng(256, 'nox_qr_blank.png');
      temp.add(path);
      expect(await service.decodeQr(path), isNull);
    });
  });

  testWidgets('returns null for a missing file', (tester) async {
    await tester.runAsync(() async {
      expect(await service.decodeQr('${Directory.systemTemp.path}/nox_qr_absent.png'), isNull);
    });
  });

  testWidgets('returns null (no throw) for bytes that are not a decodable image', (tester) async {
    await tester.runAsync(() async {
      final path = '${Directory.systemTemp.path}/nox_qr_garbage.png';
      File(path).writeAsBytesSync(Uint8List.fromList(List<int>.filled(64, 0x7F)));
      temp.add(path);
      expect(await service.decodeQr(path), isNull); // codec failure → logged → null
    });
  });
}
