import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_data_root.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/local/device_vault.dart';
import 'package:nox_app/data/repository/app/auth_repository_impl.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/model/app/app_state_type.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/domain/service/local_files_service.dart';
import 'package:nox_tor/vault.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/sealed_files.dart';

/// The local data across launches (phase 048): a key that is gone, a store
/// that does not answer, a key that opens nothing, a logout. Each test runs on
/// the database the app keeps on the disk, sealed, and starts "a new process"
/// - a fresh container over the same disk and the same secure store - the way
/// a launch does.
void main() {
  // The contract's `minimal` link: one IPv4 address.
  const link = 'nox://pair/A6CapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTwAAECAwQFBgcICQoLDA0ODwEGwKgBFCD7';
  const storageKey = 'device.storage_key';
  late Directory root;

  /// A launch: a fresh container over what is on the disk and in the store,
  /// with the database the app keeps on the disk.
  Future<void> launch({FlutterSecureStorage? store}) async {
    await getIt.reset();
    NoxVault.clear();
    await configureDependencies(Environment.test);
    await getIt<AppConfigRepository>().initialize(flavorType: AppFlavorType.stage);
    getIt.allowReassignment = true;
    if (store != null) getIt.registerSingleton<FlutterSecureStorage>(store);
    getIt.registerSingleton<AppDatabase>(AppDatabaseDev(getIt<DeviceVault>()));
    (getIt<AuthRepository>() as AuthRepositoryImpl).unreadablePause = (_) => Duration.zero;
  }

  /// A device that is paired and has a conversation: a chat, sealed on the disk.
  Future<void> pairedWithAChat() async {
    expect((await authRepository.openLocalData()).data, isFalse);
    await sessionRepository.saveIdentifier(identifier: 'token', onboardingComplete: true, label: 'Alice');
    expect((await getIt<ChatRepository>().createChat(name: 'Trip to the sea')).hasData, isTrue);
    await getIt<AppDatabase>().close();
  }

  Future<List<String>> chatNames() async {
    final page = await getIt<ChatRepository>().getChats(config: const GetChatsConfig(page: 1, cachedOnly: true));
    return [for (final chat in page.data!.$1) chat.name];
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await launch();
    root = await AppDataRoot.directory();
    for (final entity in root.listSync()) {
      entity.deleteSync(recursive: true);
    }
  });

  tearDown(() async {
    await getIt<AppDatabase>().clearEntireDatabase();
    for (final entity in root.listSync()) {
      entity.deleteSync(recursive: true);
    }
    NoxVault.clear();
    await getIt.reset();
  });

  test('the key opens what it sealed at the next launch, and nothing is wiped', () async {
    await pairedWithAChat();

    await launch();
    expect((await authRepository.openLocalData()).data, isFalse);

    expect(await chatNames(), contains('Trip to the sea'));
    expect((await sessionRepository.readSession()).data?.identifier, 'token');
  });

  test(
    'no key while the database is here: the data goes, the device pairs again - and after pairing the chats come back (SC-006)',
    () async {
      await pairedWithAChat();
      // The secure store lost the key: cleared, or the app restored elsewhere.
      await const FlutterSecureStorage().delete(key: storageKey);

      await launch();
      final out = await authRepository.openLocalData();

      expect(out.data, isTrue, reason: 'the data went');
      await appStateRepository.fetchAppState();
      expect(appStateRepository.currentState, AppStateType.unauthorized, reason: 'the pairing screen');
      expect(File(await AppDataRoot.pathOf('app_dev.db')).existsSync(), isFalse);
      expect((await sessionRepository.readSession()).data, isNull);

      // Paired again: the conversation comes from the server - the mock world's.
      expect((await authRepository.signIn(identifier: link)).hasData, isTrue);
      expect((await authRepository.completeOnboarding(label: 'Alice')).hasData, isTrue);
      expect(appStateRepository.currentState, AppStateType.authorized);
      final page = await getIt<ChatRepository>().getChats(config: const GetChatsConfig(page: 1));
      expect(page.data!.$1, isNotEmpty, reason: 'the chats are back, from the server');
      expect(page.data!.$1.map((c) => c.name), isNot(contains('Trip to the sea')), reason: 'the old store was never read');
    },
  );

  test('a key that does not open the database is as good as none: the data goes, the device pairs again', () async {
    await pairedWithAChat();
    await const FlutterSecureStorage().write(key: storageKey, value: base64.encode(List<int>.generate(32, (i) => 0x77 ^ i)));

    await launch();
    final out = await authRepository.openLocalData();

    expect(out.data, isTrue);
    expect(File(await AppDataRoot.pathOf('app_dev.db')).existsSync(), isFalse);
    expect((await sessionRepository.readSession()).data, isNull);
  });

  test('a store that does not answer wipes nothing: the key is asked for again, and opens what it sealed (FR-011)', () async {
    await pairedWithAChat();
    final flaky = _FlakyStore(failures: 2);

    await launch(store: flaky);
    final out = await authRepository.openLocalData();

    expect(out.data, isFalse, reason: 'nothing went');
    expect(flaky.keyReads, 3, reason: 'two that failed, one that answered');
    expect(await chatNames(), contains('Trip to the sea'));
    expect((await sessionRepository.readSession()).data?.identifier, 'token');
  });

  test('a logout leaves nothing of NOX in the data folder or in the secure store (SC-005)', () async {
    await pairedWithAChat();
    await launch();
    await authRepository.openLocalData();
    // Everything the device keeps: the database, a downloaded file, a file
    // waiting to be sent, a plain copy a player was reading.
    final attachment = await writeSealed(
      '${await AppDataRoot.pathOf(AppDataRoot.attachmentsFolder)}/f_1.png',
      Uint8List.fromList(List<int>.generate(70000, (i) => i & 0xFF)),
    );
    final picked = File('${Directory.systemTemp.path}/nox_lifecycle_picked.pdf')..writeAsBytesSync(List<int>.filled(1000, 7));
    addTearDown(() => picked.existsSync() ? picked.deleteSync() : null);
    final chat = (await getIt<ChatRepository>().getChats(config: const GetChatsConfig(page: 1, cachedOnly: true))).data!.$1.first;
    await getIt<OutboxRepository>().enqueue(
      chatId: chat.id,
      text: 'a message never sent',
      attachment: MessageAttachment(id: 'a', type: FileType.pdf, name: 'doc.pdf', sizeBytes: 1000, localPath: picked.path),
    );
    await getIt<LocalFilesService>().openCopy(path: attachment.path, name: 'photo.png');
    expect(root.listSync(recursive: true).whereType<File>(), isNotEmpty);

    expect((await authRepository.logout()).hasData, isTrue);

    expect(root.listSync(recursive: true).whereType<File>().map((f) => f.path), isEmpty);
    expect(await const FlutterSecureStorage().readAll(), isEmpty, reason: 'neither key, nor anything of the session');
    expect(() => NoxVault.seal(Uint8List(1)), throwsA(isA<VaultException>()), reason: 'the module holds no key either');
    expect(picked.existsSync(), isTrue, reason: "the person's own file is theirs");
  });
}

/// The secure store of a phone not unlocked yet since its restart: the key
/// cannot be read [failures] times, then it can.
class _FlakyStore extends FlutterSecureStorage {
  _FlakyStore({required this.failures});

  final int failures;
  int keyReads = 0;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    if (key == 'device.storage_key' && keyReads++ < failures) {
      throw StateError('the keystore is not available yet');
    }
    return super.read(key: key);
  }
}
