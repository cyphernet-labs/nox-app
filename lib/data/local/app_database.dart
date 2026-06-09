import 'package:injectable/injectable.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast/sembast_memory.dart';

abstract class AppDatabase {
  Future<Database> get db;

  Future<void> clearEntireDatabase();
}

@LazySingleton(as: AppDatabase, env: [Environment.prod])
class AppDatabaseProd implements AppDatabase {
  static const String _dbName = 'app.db';

  Database? _database;

  @override
  Future<Database> get db async => _database ??= await _initDb();

  Future<Database> _initDb() async {
    final dir = await getApplicationDocumentsDirectory();
    return databaseFactoryIo.openDatabase('${dir.path}/$_dbName');
  }

  @override
  Future<void> clearEntireDatabase() async {
    final dir = await getApplicationDocumentsDirectory();
    await databaseFactoryIo.deleteDatabase('${dir.path}/$_dbName');
    _database = null;
  }
}

@LazySingleton(as: AppDatabase, env: [Environment.dev])
class AppDatabaseDev implements AppDatabase {
  static const String _dbName = 'app_dev.db';

  Database? _database;

  @override
  Future<Database> get db async => _database ??= await _initDb();

  Future<Database> _initDb() async {
    final dir = await getApplicationDocumentsDirectory();
    return databaseFactoryIo.openDatabase('${dir.path}/$_dbName');
  }

  @override
  Future<void> clearEntireDatabase() async {
    final dir = await getApplicationDocumentsDirectory();
    await databaseFactoryIo.deleteDatabase('${dir.path}/$_dbName');
    _database = null;
  }
}

@LazySingleton(as: AppDatabase, env: [Environment.test])
class AppDatabaseTest implements AppDatabase {
  static const String _dbName = 'app_test.db';

  Database? _database;

  @override
  Future<Database> get db async => _database ??= await databaseFactoryMemory.openDatabase(_dbName);

  @override
  Future<void> clearEntireDatabase() async {
    await databaseFactoryMemory.deleteDatabase(_dbName);
    _database = null;
  }
}
