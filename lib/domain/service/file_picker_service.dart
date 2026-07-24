/// The transient result of the native file picker — metadata only (no bytes read):
/// the chosen file's display name, size in bytes, extension (no dot, or null), and its
/// device-local [path] (feature F4/F2 — drives the image thumbnail + the real save; null
/// if the platform did not expose a path).
typedef PickedFile = ({String name, int sizeBytes, String? extension, String? path});

/// Opens the platform file picker for a single file. Returns the chosen file's
/// metadata, or null if the user cancelled OR the picker could not present
/// (defensive fallback — never throws). No file content/bytes are read.
///
/// A domain seam over the picker plugin (feature 017) so blocs stay testable
/// without an OS dialog and the plugin is swappable — mirrors the QR feature's
/// `CameraPermissionService`.
abstract class FilePickerService {
  Future<PickedFile?> pickFile();

  /// Opens the platform "save as" dialog and returns the chosen destination path, or
  /// null if the user cancelled OR the dialog could not present (defensive — never
  /// throws). Used by the file view's real Save (feature F2). [suggestedName] pre-fills
  /// the file name.
  Future<String?> pickSaveLocation({required String suggestedName});
}
