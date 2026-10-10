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
import 'package:nox_app/domain/model/session/pending_pairing.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/domain/service/local_files_service.dart';
import 'package:nox_tor/vault.dart';
import 'package:sembast/sembast.dart';
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
  /// with the database the app keeps on the disk - stage's, or with [prod]
  /// the one a build without its define keeps beside it.
  Future<void> launch({FlutterSecureStorage? store, bool prod = false}) async {
    await getIt.reset();
    NoxVault.clear();
    await configureDependencies(Environment.test);
    await getIt<AppConfigRepository>().initialize(flavorType: prod ? AppFlavorType.prod : AppFlavorType.stage);
    getIt.allowReassignment = true;
    if (store != null) getIt.registerSingleton<FlutterSecureStorage>(store);
    final vault = getIt<DeviceVault>();
    getIt.registerSingleton<AppDatabase>(prod ? AppDatabaseProd(vault) : AppDatabaseDev(vault));
    (getIt<AuthRepository>() as AuthRepositoryImpl).unreadablePause = (_) => Duration.zero;
  }

  /// What a run of the other environment leaves on this device: both share
  /// one app id, so one data folder, one secure store and one key, and a
  /// build without its define is prod. Its database, sealed under the same
  /// key, with something in it - and the compaction file a crash left beside
  /// it.
  Future<void> otherEnvironmentRan() async {
    final prod = AppDatabaseProd(getIt<DeviceVault>());
    await StoreRef<String, String>.main().record('ran').put(await prod.db, 'prod');
    await prod.close();
    File(await AppDataRoot.pathOf('~app.db')).writeAsStringSync('{"version":1,"sembast":1}\n');
  }

  Future<List<String>> databasesLeft() async => [
    for (final path in await AppDataRoot.databasePaths())
      if (File(path).existsSync()) path.split(Platform.pathSeparator).last,
  ];

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

  group('a pairing that waited for approval when the app closed (phase 046)', () {
    const pendingKey = 'session.pending_pairing';

    /// A device that waits: no session yet, the server the link named, the
    /// device key the request was opened with, and the wait itself - beside a
    /// database sealed on the disk. The device key it waited with is returned.
    Future<String> waitingForApproval() async {
      expect((await authRepository.openLocalData()).data, isFalse);
      await StoreRef<String, String>.main().record('opened').put(await getIt<AppDatabase>().db, 'before the pairing');
      await getIt<AppDatabase>().close();
      await sessionRepository.saveServer(address: '192.168.1.20:8443', serverKey: 'oJql9HpnWYAv+VX43C0qFKXJnSO+l/hkEn/5ODRVpPA=');
      final deviceKey = (await sessionRepository.deviceSecret()).data!;
      await sessionRepository.savePendingPairing(PendingPairing(link: link, waitUntil: DateTime.now().add(const Duration(minutes: 5))));
      return deviceKey;
    }

    test('goes with the data whose key is lost: the session goes whole, and 2.1 has nothing to resume (FR-011)', () async {
      final deviceKey = await waitingForApproval();
      await const FlutterSecureStorage().delete(key: storageKey);

      await launch();
      expect((await authRepository.openLocalData()).data, isTrue, reason: 'the data went');

      expect(await const FlutterSecureStorage().read(key: pendingKey), isNull, reason: 'a link left in the store is a credential');
      expect((await authRepository.pendingPairing()).data, isNull, reason: 'the login screen offers no wait to go back to');
      expect((await sessionRepository.deviceSecret()).data, isNot(deviceKey), reason: 'the key the wait went on with is gone with it');
    });

    test('survives a store that does not answer: nothing is wiped, and the wait is there to resume', () async {
      final deviceKey = await waitingForApproval();
      final flaky = _FlakyStore(failures: 2);

      await launch(store: flaky);
      expect((await authRepository.openLocalData()).data, isFalse, reason: 'nothing went');

      expect((await authRepository.pendingPairing()).data?.link, link);
      expect((await sessionRepository.deviceSecret()).data, deviceKey, reason: 'the same key, so the same request');
    });
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

  group('the other environment on the same device', () {
    test("a logout takes the other environment's database with it, and pairing again works at once", () async {
      // Prod ran once beside stage, under the same key; stage logs out. The
      // key goes - and with it every database it sealed, or the one left
      // behind reads as data whose key is lost, to both environments, for good.
      await pairedWithAChat();
      await otherEnvironmentRan();
      await launch();
      expect((await authRepository.openLocalData()).data, isFalse);

      expect((await authRepository.logout()).hasData, isTrue);

      expect(await databasesLeft(), isEmpty, reason: 'nothing a key would have to open (SC-005)');
      expect(await const FlutterSecureStorage().read(key: storageKey), isNull);

      // Paired again in the same process: the database opens under a new key.
      expect((await authRepository.signIn(identifier: link)).hasData, isTrue);
      expect((await authRepository.completeOnboarding(label: 'Alice')).hasData, isTrue);
      expect((await getIt<ChatRepository>().createChat(name: 'After the logout')).hasData, isTrue);
      expect(await chatNames(), contains('After the logout'));
      await getIt<AppDatabase>().close();

      // And the next launch of either environment opens what it finds.
      await launch();
      expect((await authRepository.openLocalData()).data, isFalse, reason: 'nothing retired');
      expect(await chatNames(), contains('After the logout'));
      await launch(prod: true);
      expect((await authRepository.openLocalData()).data, isFalse, reason: 'prod finds nothing it cannot open either');
      expect((await sessionRepository.readSession()).data?.identifier, isNotNull);
    });

    test("no key and the other environment's database left behind: the start retires every database, and the device pairs again", () async {
      // The state a logout that deleted only its own database left: the key
      // gone with the session, the other environment's database still here.
      // Its forced logout could not open the queue it empties - the start
      // retired the data at every launch and the pairing never took.
      await pairedWithAChat();
      await otherEnvironmentRan();
      await const FlutterSecureStorage().deleteAll();
      File(await AppDataRoot.pathOf('app_dev.db')).deleteSync();

      await launch();
      final out = await authRepository.openLocalData();

      expect(out.data, isTrue, reason: 'retired, through a forced logout that went through');
      expect(await databasesLeft(), isEmpty);
      await appStateRepository.fetchAppState();
      expect(appStateRepository.currentState, AppStateType.unauthorized, reason: 'the pairing screen');

      expect((await authRepository.signIn(identifier: link)).hasData, isTrue);
      expect((await authRepository.completeOnboarding(label: 'Alice')).hasData, isTrue);
      expect((await getIt<ChatRepository>().createChat(name: 'Paired again')).hasData, isTrue);
      await getIt<AppDatabase>().close();
      await launch();
      expect((await authRepository.openLocalData()).data, isFalse);
      expect(await chatNames(), contains('Paired again'));
    });
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
