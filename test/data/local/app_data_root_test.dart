import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_data_root.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  const backupChannel = MethodChannel('nox/backup');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late String sharedRoot;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    sharedRoot = (await getApplicationSupportDirectory()).path;
  });

  tearDown(() async {
    // Back to what the test bootstrap answers: one folder for every question.
    messenger.setMockMethodCallHandler(pathChannel, (call) async => sharedRoot);
    messenger.setMockMethodCallHandler(backupChannel, null);
    await getIt.reset();
  });

  /// path_provider answering each question with a folder of its own.
  Future<({Directory support, Directory documents, Directory cache})> separateFolders() async {
    final base = await Directory.systemTemp.createTemp('nox_data_root');
    addTearDown(() => base.delete(recursive: true));
    final folders = (
      support: await Directory('${base.path}/support').create(),
      documents: await Directory('${base.path}/documents').create(),
      cache: await Directory('${base.path}/cache').create(),
    );
    messenger.setMockMethodCallHandler(pathChannel, (call) async {
      return switch (call.method) {
        'getApplicationDocumentsDirectory' => folders.documents.path,
        'getApplicationCacheDirectory' => folders.cache.path,
        _ => folders.support.path,
      };
    });
    return folders;
  }

  test('the data folder is the application support folder, never Documents (FR-009)', () async {
    final folders = await separateFolders();

    expect((await AppDataRoot.directory()).path, folders.support.path);
    expect(await AppDataRoot.pathOf('app.db'), '${folders.support.path}/app.db');
  });

  test('on macOS the data folder is marked as not for backups, at every launch (FR-010)', () async {
    // The test host is a Mac: the call is the one the runner answers there.
    final folders = await separateFolders();
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(backupChannel, (call) async {
      calls.add(call);
      return true;
    });

    await AppDataRoot.excludeFromBackup();
    await AppDataRoot.excludeFromBackup();

    expect(calls, hasLength(2));
    expect(calls.first.method, 'exclude');
    expect(calls.first.arguments, {'path': folders.support.path});
  });

  test('a runner that refuses the mark does not stop the launch', () async {
    await separateFolders();
    messenger.setMockMethodCallHandler(backupChannel, (call) async => throw PlatformException(code: 'exclude_failed'));

    await expectLater(AppDataRoot.excludeFromBackup(), completes);
  });

  test('on Windows the data folder is the local application data, which a roaming profile does not carry', () async {
    final local = await Directory.systemTemp.createTemp('nox_local_app_data');
    addTearDown(() => local.delete(recursive: true));

    final path = await LocalAppDataPathProvider(localAppData: () async => local.path).getApplicationSupportPath();

    expect(path, '${local.path}${Platform.pathSeparator}NOX');
    expect(Directory(path!).existsSync(), isTrue);
    expect(LocalAppDataPathProvider.localAppDataFolder, '{F1B32785-6FBA-4FCF-9D55-7B8E7F157091}', reason: 'FOLDERID_LocalAppData');
  });

  group('what builds before phase 048 left unsealed', () {
    test('their database in Documents and their attachments in the cache go; the data folder stays', () async {
      final folders = await separateFolders();
      final oldDatabase = File('${folders.documents.path}/app_dev.db')..writeAsStringSync('plain');
      final oldAttachment = File('${folders.cache.path}/nox_attachments/f_1.png')
        ..createSync(recursive: true)
        ..writeAsStringSync('plain');
      final current = File('${folders.support.path}/app_dev.db')..writeAsStringSync('sealed');
      final somebodyElses = File('${folders.documents.path}/notes.txt')..writeAsStringSync('not ours');

      await AppDataRoot.sweepLegacy();

      expect(oldDatabase.existsSync(), isFalse);
      expect(oldAttachment.existsSync(), isFalse);
      expect(current.existsSync(), isTrue);
      expect(somebodyElses.existsSync(), isTrue);
    });

    test('a folder that is also the data folder is never swept', () async {
      // As the test bootstrap answers: one folder for every question.
      final current = File('$sharedRoot/app_dev.db')..writeAsStringSync('sealed');
      addTearDown(() => current.existsSync() ? current.deleteSync() : null);
      final attachment = File('$sharedRoot/nox_attachments/f_1.png')
        ..createSync(recursive: true)
        ..writeAsStringSync('sealed');
      addTearDown(() => attachment.parent.existsSync() ? attachment.parent.deleteSync(recursive: true) : null);

      await AppDataRoot.sweepLegacy();

      expect(current.existsSync(), isTrue);
      expect(attachment.existsSync(), isTrue);
    });
  });
}
