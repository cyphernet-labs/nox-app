/// Decodes a QR payload from a still image file (feature P14). Enables the
/// Windows/Linux sign-in fallback: those platforms have no camera scanner
/// (`mobile_scanner` is mobile+macOS only), so instead of scanning, the user picks
/// an image that contains their NOX identity QR and it is decoded locally.
///
/// A domain seam over the pure-Dart decoder (`zxing2`) so the presentation stays
/// testable without real image I/O — mirrors `CameraPermissionService` /
/// `FilePickerService`. Returns the RAW QR text (the caller applies
/// `PairingLink.tryParse`, exactly like the camera path). No-throw: an unreadable
/// file, an unsupported format, or an image with no QR all resolve to `null`.
abstract class QrImageDecodeService {
  Future<String?> decodeQr(String imagePath);
}
