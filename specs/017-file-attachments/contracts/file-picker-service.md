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

Uses **`file_selector`** (official flutter.dev plugin). `file_picker` was the plan-named
choice but its `win32` constraint conflicts with the project's `package_info_plus ^10.1.0`
(win32 ^6.0.1); `file_selector` resolves cleanly and supports all five targets.

```dart
import 'package:file_selector/file_selector.dart';

@LazySingleton(as: FilePickerService, env: [Environment.dev, Environment.prod, Environment.test])
class FilePickerServiceImpl implements FilePickerService {
  @override
  Future<PickedFile?> pickFile() async {
    try {
      final XFile? file = await openFile(); // any file; metadata only, no bytes read
      if (file == null) return null; // cancelled
      final name = file.name;
      final ext = name.contains('.') ? name.split('.').last : null;
      return (name: name, sizeBytes: await file.length(), extension: ext);
    } catch (_) {
      return null; // defensive fallback: no crash if the picker fails to present
    }
  }
}
```

Notes:
- `openFile()` (no type groups) allows any file; `XFile.length()` stats the size without reading content, and `XFile.name` gives the display name — metadata only (Constitution I + perf).
- The impl is the REAL picker (bound for all envs); in `bloc_test` a fake `FilePickerService` is registered instead (no OS dialog).
- Returns `null` (not an exception) on cancel or failure → the caller leaves the composer unchanged (FR-004) and never crashes (FR-009 fallback).

## Behavioural contract

| Call outcome | Return |
|--------------|--------|
| User picks a file | `(name, sizeBytes, extension)` of that file |
| User cancels | `null` |
| Picker throws / unsupported | `null` (logged is optional; never rethrown) |

## Consumer

`ChatThreadBloc._onAttachmentPicked` (now async): `pickFile()` → if null, no-op; else build the draft `MessageAttachment` (uuid id, real name/size, `FileType.fromExtension(extension)`).
