/// The transient result of the native file picker — metadata only (no bytes read):
/// the chosen file's display name, size in bytes, and extension (no dot, or null).
typedef PickedFile = ({String name, int sizeBytes, String? extension});

/// Opens the platform file picker for a single file. Returns the chosen file's
/// metadata, or null if the user cancelled OR the picker could not present
/// (defensive fallback — never throws). No file content/bytes are read.
///
/// A domain seam over the picker plugin (feature 017) so blocs stay testable
/// without an OS dialog and the plugin is swappable — mirrors the QR feature's
/// `CameraPermissionService`.
abstract class FilePickerService {
  Future<PickedFile?> pickFile();
}
