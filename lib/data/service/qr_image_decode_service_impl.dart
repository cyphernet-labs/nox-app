import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:injectable/injectable.dart';
import 'package:zxing2/qrcode.dart';

import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/service/qr_image_decode_service.dart';

/// Pure-Dart QR-from-image decode (feature P14): read the file, decode it to pixels via
/// the engine codec (`dart:ui` — handles PNG/JPEG/WebP on every platform), then run
/// `zxing2`'s QR reader over the luminance. Works headless and on Windows/Linux (no native
/// plugin), so it is host-testable. No-throw: a missing/unreadable file, an undecodable
/// format, or an image with no QR all return `null` (logged for the last two).
@LazySingleton(as: QrImageDecodeService, env: [Environment.dev, Environment.prod, Environment.test])
class QrImageDecodeServiceImpl implements QrImageDecodeService {
  @override
  Future<String?> decodeQr(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final text = await _decodeBytes(bytes);
      return text;
    } on NotFoundException {
      return null; // a valid image, but it carries no QR code
    } catch (e, s) {
      logRepository.error(target: this, error: e, stackTrace: s);
      return null;
    }
  }

  /// Decodes [bytes] → RGBA pixels → zxing2. Throws [NotFoundException] when there is no
  /// QR (caught above); any codec failure propagates to the outer catch.
  Future<String?> _decodeBytes(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final width = image.width;
    final height = image.height;
    final rgbaData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    codec.dispose();
    if (rgbaData == null) return null;
    final rgba = rgbaData.buffer.asUint8List();

    // zxing2 wants one ARGB int per pixel; alpha is opaque (luminance ignores it).
    final pixels = Int32List(width * height);
    for (var i = 0; i < pixels.length; i++) {
      final o = i * 4;
      pixels[i] = (0xFF << 24) | (rgba[o] << 16) | (rgba[o + 1] << 8) | rgba[o + 2];
    }
    final bitmap = BinaryBitmap(HybridBinarizer(RGBLuminanceSource(width, height, pixels)));
    // tryHarder: a real user-saved QR image may be scaled/rotated/noisy.
    final hints = DecodeHints()..put(DecodeHintType.tryHarder);
    return QRCodeReader().decode(bitmap, hints: hints).text;
  }
}
