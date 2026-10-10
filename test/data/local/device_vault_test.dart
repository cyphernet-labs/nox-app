import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_data_root.dart';
import 'package:nox_app/data/local/device_vault.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_tor/vault.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/fake_session_repository.dart';

/// The secure store as the vault sees it: a key, nothing, or no answer.
class _KeyStore extends FakeSessionRepository {
  String? key;
  bool unreadable = false;
  bool refusesWrites = false;
  int writes = 0;
  int deletes = 0;

  @override
  Future<RepositoryResult<String?>> storageKey() async {
    if (unreadable) return const RepositoryResult<String?>.error(exception: RepositoryException.unknown);
    // A turn of the event loop, as a platform channel takes: two openings at
    // once then really overlap.
    await Future<void>.delayed(Duration.zero);
    return RepositoryResult<String?>.success(data: key);
  }

  @override
  Future<RepositoryResult<bool>> saveStorageKey({required String key}) async {
    writes++;
    if (refusesWrites) return const RepositoryResult<bool>.error(exception: RepositoryException.unknown);
    this.key = key;
    return const RepositoryResult<bool>.success(data: true);
  }

  @override
  Future<RepositoryResult<bool>> forgetStorageKey() async {
    deletes++;
    key = null;
    return const RepositoryResult<bool>.success(data: true);
  }
}

void main() {
  late _KeyStore store;
  late DeviceVault vault;
  final text = Uint8List.fromList(utf8.encode('a line of the local database'));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    NoxVault.clear();
    store = _KeyStore();
    vault = DeviceVault(store);
    for (final name in AppDataRoot.databaseFiles) {
      final file = File(await AppDataRoot.pathOf(name));
      if (file.existsSync()) file.deleteSync();
    }
  });

  tearDown(() async {
    for (final name in AppDataRoot.databaseFiles) {
      final file = File(await AppDataRoot.pathOf(name));
      if (file.existsSync()) file.deleteSync();
    }
    NoxVault.clear();
    await getIt.reset();
  });

  /// A database a key once sealed, as the disk shows it.
  Future<void> leaveDatabase() async {
    final file = File(await AppDataRoot.pathOf('app_dev.db'));
    await file.parent.create(recursive: true);
    await file.writeAsString('{"version":1,"sembast":1}\n');
  }

  bool moduleHasKey() {
    try {
      NoxVault.seal(text);
      return true;
    } on VaultException catch (e) {
      expect(e.code, VaultCode.noKey);
      return false;
    }
  }

  test('the key the secure store holds goes to the module, and what it seals opens', () async {
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
    store.key = base64.encode(key);

    expect(await vault.open(), LocalDataOpening.open);
    expect(vault.isOpen, isTrue);
    final sealed = NoxVault.seal(text);
    // The same key set again opens it: the module was handed THIS key.
    NoxVault.setKey(key);
    expect(NoxVault.open(sealed), text);
    expect(store.writes, 0);
  });

  test('neither a key nor a database: a new key, in the store and in the module', () async {
    expect(await vault.open(), LocalDataOpening.created);

    expect(base64.decode(store.key!), hasLength(32));
    expect(moduleHasKey(), isTrue);
    // Opened once, opened for the life of the process.
    expect(await vault.open(), LocalDataOpening.open);
    expect(store.writes, 1);
  });

  test('two openings at once make one key, not two', () async {
    final both = await Future.wait([vault.open(), vault.open()]);

    expect(both, [LocalDataOpening.created, LocalDataOpening.created]);
    expect(store.writes, 1);
  });

  test('no key and a database sealed under one: lost - and nothing is written or handed over', () async {
    await leaveDatabase();

    expect(await vault.open(), LocalDataOpening.lost);

    expect(store.writes, 0, reason: 'a new key over data nothing can open would only hide it');
    expect(vault.isOpen, isFalse);
    expect(moduleHasKey(), isFalse);
    expect(await vault.hasLocalData(), isTrue);
  });

  test('a store that does not answer is unreadable: nothing decided, nothing written, nothing deleted', () async {
    await leaveDatabase();
    store.unreadable = true;

    expect(await vault.open(), LocalDataOpening.unreadable);

    expect(store.writes, 0);
    expect(store.deletes, 0);
    expect(File(await AppDataRoot.pathOf('app_dev.db')).existsSync(), isTrue, reason: 'a wait never costs the data (FR-011)');
    expect(moduleHasKey(), isFalse);
  });

  test('a store that will not keep a new key is unreadable, and the module gets nothing it could not get again', () async {
    store.refusesWrites = true;

    expect(await vault.open(), LocalDataOpening.unreadable);
    expect(moduleHasKey(), isFalse);
  });

  test('a stored key that is no key is as good as none', () async {
    for (final broken in ['not base64 at all', base64.encode(Uint8List(16)), base64.encode(Uint8List(32))]) {
      final fresh = DeviceVault(store..key = broken);
      expect(await fresh.open(), LocalDataOpening.created, reason: broken);
      expect(store.key, isNot(broken));
      NoxVault.clear();
    }
    await leaveDatabase();
    final lost = DeviceVault(store..key = base64.encode(Uint8List(32)));
    expect(await lost.open(), LocalDataOpening.lost);
  });

  test('ensureOpen opens, or refuses: nothing is sealed on a guess', () async {
    await vault.ensureOpen();
    expect(moduleHasKey(), isTrue);

    NoxVault.clear();
    final elsewhere = DeviceVault(_KeyStore()..unreadable = true);
    await expectLater(elsewhere.ensureOpen(), throwsA(isA<VaultException>().having((e) => e.code, 'code', VaultCode.noKey)));
    await leaveDatabase();
    final lost = DeviceVault(_KeyStore());
    await expectLater(lost.ensureOpen(), throwsA(isA<VaultException>()));
  });

  test('forget drops the key from the module and from the store; the next opening makes a new one', () async {
    await vault.open();
    final first = store.key;

    await vault.forget();

    expect(vault.isOpen, isFalse);
    expect(store.key, isNull);
    expect(moduleHasKey(), isFalse);
    expect(await vault.open(), LocalDataOpening.created);
    expect(store.key, isNot(first));
  });
}
