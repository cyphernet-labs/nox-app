/// Save on the file view (5.3): the plain file (phase 048, FR-008), where the
/// person chooses in the platform's own save dialog. On the desktops that
/// dialog names a place and the file is written there; on iOS and Android it
/// takes the file and writes it to the place chosen itself.
///
/// Takes paths, never `dart:io` types: `domain` imports nothing.
abstract class FileSaveService {
  /// Saves the file at [path] - sealed when it is NOX's own copy, as it is
  /// when the person picked it in the composer - under [name]. True once it
  /// is written; false when no place was chosen. Throws when it could not be
  /// written, or when the dialog of iOS or Android could not be shown.
  Future<bool> save({required String path, required String name});
}
