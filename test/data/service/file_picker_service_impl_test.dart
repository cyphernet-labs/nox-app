import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/service/file_picker_service_impl.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// A fake file_selector platform: `openFile()` returns a canned XFile, null, or throws.
class _FakeFileSelector extends FileSelectorPlatform with MockPlatformInterfaceMixin {
  _FakeFileSelector({this.file, this.throwErr = false});

  final XFile? file;
  final bool throwErr;

  @override
  Future<XFile?> openFile({List<XTypeGroup>? acceptedTypeGroups, String? initialDirectory, String? confirmButtonText}) async {
    if (throwErr) throw Exception('picker failed to present');
    return file;
  }
}

void main() {
  final service = FilePickerServiceImpl();

  group('FilePickerServiceImpl.pickedFileFrom (pure mapping)', () {
    test('extracts the extension as the last dot-segment', () {
      expect(FilePickerServiceImpl.pickedFileFrom('report.pdf', 2048, '/tmp/report.pdf'), (
        name: 'report.pdf',
        sizeBytes: 2048,
        extension: 'pdf',
        path: '/tmp/report.pdf',
      ));
      expect(FilePickerServiceImpl.pickedFileFrom('archive.tar.gz', 10).extension, 'gz'); // multi-dot → last segment
    });

    test('a name with no dot has a null extension', () {
      expect(FilePickerServiceImpl.pickedFileFrom('LICENSE', 99).extension, isNull);
    });

    test('the device-local path is carried, and an empty path maps to null (F4/F2)', () {
      expect(FilePickerServiceImpl.pickedFileFrom('a.png', 1, '/tmp/a.png').path, '/tmp/a.png');
      expect(FilePickerServiceImpl.pickedFileFrom('a.png', 1, '').path, isNull); // empty → null
      expect(FilePickerServiceImpl.pickedFileFrom('a.png', 1).path, isNull); // absent → null
    });
  });

  group('FilePickerServiceImpl.pickFile (over a fake platform)', () {
    tearDown(() => FileSelectorPlatform.instance = FileSelectorPlatform.instance); // no global leak beyond the test run

    test('maps the chosen file to a PickedFile (name/size/extension)', () async {
      // A real temp file so XFile.name (basename) + XFile.length() (real bytes) resolve
      // deterministically on the VM (the length: override / fromData name are unreliable there).
      final tmp = File('${Directory.systemTemp.path}/notes.txt')..writeAsBytesSync(Uint8List(512));
      addTearDown(() => tmp.existsSync() ? tmp.deleteSync() : null);
      FileSelectorPlatform.instance = _FakeFileSelector(file: XFile(tmp.path));

      final picked = await service.pickFile();

      expect(picked, isNotNull);
      expect(picked!.name, 'notes.txt');
      expect(picked.sizeBytes, 512);
      expect(picked.extension, 'txt');
      expect(picked.path, tmp.path); // the device-local path flows through (F4/F2)
    });

    test('returns null when the user cancels (openFile → null)', () async {
      FileSelectorPlatform.instance = _FakeFileSelector(file: null);
      expect(await service.pickFile(), isNull);
    });

    test('returns null (defensive fallback) when the picker throws', () async {
      FileSelectorPlatform.instance = _FakeFileSelector(throwErr: true);
      expect(await service.pickFile(), isNull);
    });
  });
}
