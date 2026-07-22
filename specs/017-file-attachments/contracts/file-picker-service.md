# Contract: FilePickerService seam

A domain service over the native picker, so blocs stay testable and the plugin is swappable (mirrors feature-010's `CameraPermissionService`).

## Interface (`lib/domain/service/file_picker_service.dart`)

```dart
/// The transient result of the native file picker — metadata only (no bytes).
typedef PickedFile = ({String name, int sizeBytes, String? extension});

/// Opens the platform file picker for a single file. Returns the chosen file's
/// metadata, or null if the user cancelled OR the picker could not present
/// (defensive fallback — never throws). No file content/bytes are read.
abstract class FilePickerService {
  Future<PickedFile?> pickFile();
}
```

## Real implementation (`lib/data/service/file_picker_service_impl.dart`)

```dart
@LazySingleton(as: FilePickerService, env: [Environment.dev, Environment.prod, Environment.test])
class FilePickerServiceImpl implements FilePickerService {
  @override
  Future<PickedFile?> pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(withData: false); // metadata only
      final f = result?.files.singleOrNull;
      if (f == null) return null; // cancelled
      return (name: f.name, sizeBytes: f.size, extension: f.extension);
    } catch (_) {
      return null; // defensive fallback: no crash if the picker fails to present
    }
  }
}
```

Notes:
- Named `Mock*` for env consistency with the other seams, but it is the REAL picker (the "mock" is the UI-first phase's absence of a backend, not the picker). It is bound for all envs; in `bloc_test` a fake `FilePickerService` is registered instead (no OS dialog).
- `withData: false` → no bytes loaded (Constitution I + perf).
- Returns `null` (not an exception) on cancel or failure → the caller leaves the composer unchanged (FR-004) and never crashes (FR-009 fallback).

## Behavioural contract

| Call outcome | Return |
|--------------|--------|
| User picks a file | `(name, sizeBytes, extension)` of that file |
| User cancels | `null` |
| Picker throws / unsupported | `null` (logged is optional; never rethrown) |

## Consumer

`ChatThreadBloc._onAttachmentPicked` (now async): `pickFile()` → if null, no-op; else build the draft `MessageAttachment` (uuid id, real name/size, `FileType.fromExtension(extension)`).
