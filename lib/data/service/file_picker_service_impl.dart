import 'package:file_selector/file_selector.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/domain/service/file_picker_service.dart';

/// Real [FilePickerService] over `file_selector` (official flutter.dev plugin, all
/// five targets). `file_picker` was the plan's first choice but its `win32` pin
/// conflicts with `package_info_plus`; `file_selector` resolves cleanly (feature 017).
///
/// Metadata only: `openFile()` never reads file bytes, and `XFile.length()` stats the
/// size without loading content — so large files never block the UI and nothing leaves
/// the device (Constitution I). Returns null on cancel OR any plugin failure so the
/// caller leaves the composer unchanged and the attach action never crashes.
@LazySingleton(as: FilePickerService, env: [Environment.dev, Environment.prod, Environment.test])
class FilePickerServiceImpl implements FilePickerService {
  @override
  Future<PickedFile?> pickFile() async {
    try {
      final XFile? file = await openFile(); // any file type; no bytes read
      if (file == null) return null; // cancelled
      return pickedFileFrom(file.name, await file.length());
    } catch (_) {
      return null; // defensive fallback: never throws (FR-009)
    }
  }

  /// Pure mapping XFile metadata → [PickedFile], extracted so it is unit-testable
  /// without the platform picker. Extension = the last dot-segment of the name (or null).
  static PickedFile pickedFileFrom(String name, int sizeBytes) {
    final ext = name.contains('.') ? name.split('.').last : null;
    return (name: name, sizeBytes: sizeBytes, extension: ext);
  }
}
