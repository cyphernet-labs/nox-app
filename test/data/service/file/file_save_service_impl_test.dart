import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/service/file/file_save_service_impl.dart';
import 'package:nox_app/data/service/file/system_save_dialog.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/service/file_picker_service.dart';
import 'package:nox_app/domain/service/local_files_service.dart';
import 'package:nox_tor/vault.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/sealed_files.dart';

/// The desktops' dialog: it names a place, or nothing when cancelled.
class _DesktopDialog implements FilePickerService {
  _DesktopDialog(this.destination);

  final String? destination;
  final List<String> asked = [];

  @override
  Future<PickedFile?> pickFile() async => null;

  @override
  Future<String?> pickSaveLocation({required String suggestedName}) async {
    asked.add(suggestedName);
    return destination;
  }
}

/// The dialog of iOS and Android. It keeps what it was handed as the
/// platform would find it, and [answer] says how it ends.
class _PhoneDialog implements SystemSaveDialog {
  _PhoneDialog({this.available = true, this.answer});

  final bool available;
  final Future<bool> Function()? answer;
  final List<String> paths = [];
  final List<Uint8List> handed = [];

  @override
  bool get isAvailable => available;

  @override
  Future<bool> save({required String path}) async {
    paths.add(path);
    handed.add(File(path).readAsBytesSync());
    return answer == null ? true : answer!();
  }
}

void main() {
  late LocalFilesService files;
  late Directory dir;
  final data = Uint8List.fromList(List<int>.generate(90000, (i) => (i * 7) & 0xFF));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    files = getIt<LocalFilesService>();
    dir = await Directory.systemTemp.createTemp('nox_file_save');
  });

  tearDown(() async {
    await files.clearCopies();
    await dir.delete(recursive: true);
    NoxVault.clear();
    await getIt.reset();
  });

  group('on iOS and Android', () {
    test("the platform's dialog is handed a plain copy under the file's name, and the copy goes once it answers", () async {
      final sealed = await writeSealed('${dir.path}/report', data);
      final desktop = _DesktopDialog('${dir.path}/never.pdf');
      final phone = _PhoneDialog();

      final saved = await FileSaveServiceImpl(desktop, files, phone).save(path: sealed.path, name: 'report.pdf');

      expect(saved, isTrue);
      expect(phone.handed.single, data, reason: 'what the person can open, not what the device keeps');
      expect(phone.paths.single.split(Platform.pathSeparator).last, 'report.pdf');
      expect(File(phone.paths.single).existsSync(), isFalse, reason: 'the platform has written it where the person chose');
      // file_selector has no save dialog here: asking it was what made Save do nothing.
      expect(desktop.asked, isEmpty);
    });

    test('a cancelled dialog saves nothing and leaves no copy behind', () async {
      final sealed = await writeSealed('${dir.path}/report', data);
      final phone = _PhoneDialog(answer: () async => false);

      final saved = await FileSaveServiceImpl(_DesktopDialog(null), files, phone).save(path: sealed.path, name: 'report.pdf');

      expect(saved, isFalse);
      expect(File(phone.paths.single).existsSync(), isFalse);
    });

    test('a dialog that could not save is an error, not a cancel - and still leaves no copy', () async {
      final sealed = await writeSealed('${dir.path}/report', data);
      final phone = _PhoneDialog(answer: () async => throw PlatformException(code: 'save'));

      await expectLater(
        FileSaveServiceImpl(_DesktopDialog(null), files, phone).save(path: sealed.path, name: 'report.pdf'),
        throwsA(isA<PlatformException>()),
      );
      expect(File(phone.paths.single).existsSync(), isFalse);
    });

    test('a copy that cannot be made is an error, and no dialog shows', () async {
      final phone = _PhoneDialog();

      await expectLater(
        FileSaveServiceImpl(_DesktopDialog(null), files, phone).save(path: '${dir.path}/gone', name: 'report.pdf'),
        throwsA(isA<FileSystemException>()),
      );
      expect(phone.paths, isEmpty);
    });
  });

  group('on the desktops', () {
    test('the plain file is written where the dialog pointed', () async {
      final sealed = await writeSealed('${dir.path}/report', data);
      final destination = '${dir.path}/Downloads-report.pdf';
      final desktop = _DesktopDialog(destination);
      final phone = _PhoneDialog(available: false);

      final saved = await FileSaveServiceImpl(desktop, files, phone).save(path: sealed.path, name: 'report.pdf');

      expect(saved, isTrue);
      expect(File(destination).readAsBytesSync(), data);
      expect(desktop.asked, ['report.pdf']);
      expect(phone.paths, isEmpty);
    });

    test('a cancelled dialog writes nothing', () async {
      final sealed = await writeSealed('${dir.path}/report', data);

      final saved = await FileSaveServiceImpl(
        _DesktopDialog(null),
        files,
        _PhoneDialog(available: false),
      ).save(path: sealed.path, name: 'report.pdf');

      expect(saved, isFalse);
      expect(dir.listSync().map((entry) => entry.path.split(Platform.pathSeparator).last), ['report']);
    });
  });
}
