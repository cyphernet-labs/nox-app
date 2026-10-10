import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/local/app_data_root.dart';
import 'package:nox_app/data/local/device_vault.dart';
import 'package:nox_app/data/local/vault_codec.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast/sembast_memory.dart';

abstract class AppDatabase {
  Future<Database> get db;

  /// Closes the database when it is open. The next [db] opens it again.
  Future<void> close();

  /// Closes the database and deletes it. On the disk that is every database
  /// sealed under the local-data key, the other environment's too: it runs
  /// when the key goes (a logout, data whose key is lost), and the key is
  /// shared ([AppDataRoot.databaseFiles]).
  Future<void> clearEntireDatabase();
}

/// The database on the disk (phase 048): in the app's data folder, every line
/// of it sealed under the local-data key ([VaultCodec]), opened only once the
/// key is in the module. Opened under another key it does not open at all
/// (`DatabaseException.invalidCodec`), which the start reads as data whose
/// key is gone.
abstract class _DiskAppDatabase implements AppDatabase {
  _DiskAppDatabase(this._vault, this._name);

  final DeviceVault _vault;
  final String _name;

  /// The opening, shared by everyone who asks while it runs, and forgotten
  /// when it fails: a vault that could not open now may open on the next ask.
  Future<Database>? _opening;

  @override
  Future<Database> get db => _opening ??= _open().catchError((Object error, StackTrace stackTrace) {
    _opening = null;
    Error.throwWithStackTrace(error, stackTrace);
  });

  Future<Database> _open() async {
    await _vault.ensureOpen();
    return databaseFactoryIo.openDatabase(await AppDataRoot.pathOf(_name), codec: VaultCodec.sembast);
  }

  @override
  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening == null) return;
    try {
      await (await opening).close();
    } on Object {
      // An opening that failed has nothing to close.
    }
  }

  @override
  Future<void> clearEntireDatabase() async {
    await close();
    final own = await AppDataRoot.pathOf(_name);
    // Every other database file goes first: the other environment's, sealed
    // under the same key, and the compaction files Sembast leaves. Left behind,
    // one would read as data whose key is lost to every launch of either
    // environment, and the wipe of neither would delete it: no database would
    // open on this device again, nor would a new key ever be made.
    for (final path in await AppDataRoot.databasePaths()) {
      if (path == own) continue;
      try {
        final file = File(path);
        if (file.existsSync()) await file.delete();
      } on FileSystemException catch (error) {
        // The type only: the message names the path. Best effort, file by
        // file - one that will not go must not keep the rest; a launch that
        // still finds it retires it again.
        logRepository.error(target: this, error: error.runtimeType);
      }
    }
    // This one last. Until it goes, a read that races the wipe finds a
    // database with no key and opens nothing; once it has gone, the next read
    // makes a new key and a new database - and nothing after this deletes them
    // from under it.
    await databaseFactoryIo.deleteDatabase(own);
  }
}

@LazySingleton(as: AppDatabase, env: [Environment.prod])
class AppDatabaseProd extends _DiskAppDatabase {
  AppDatabaseProd(DeviceVault vault) : super(vault, 'app.db');
}

@LazySingleton(as: AppDatabase, env: [Environment.dev])
class AppDatabaseDev extends _DiskAppDatabase {
  AppDatabaseDev(DeviceVault vault) : super(vault, 'app_dev.db');
}

@LazySingleton(as: AppDatabase, env: [Environment.test])
class AppDatabaseTest implements AppDatabase {
  static const String _dbName = 'app_test.db';

  Database? _database;

  @override
  Future<Database> get db async => _database ??= await databaseFactoryMemory.openDatabase(_dbName);

  @override
  Future<void> close() async {
    final open = _database;
    _database = null;
    await open?.close();
  }

  @override
  Future<void> clearEntireDatabase() async {
    await databaseFactoryMemory.deleteDatabase(_dbName);
    _database = null;
  }
}
