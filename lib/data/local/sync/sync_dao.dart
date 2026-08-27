import 'package:injectable/injectable.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:sembast/sembast.dart';

/// Single-record Sembast store for the device sync state. Lives beside the
/// message store on purpose: the cursor promises "everything up to seq is
/// applied HERE", so it must die in the same wipe as the messages.
@lazySingleton
class SyncDao {
  SyncDao(this._database);

  final AppDatabase _database;

  static final StoreRef<String, Map<String, dynamic>> _store = stringMapStoreFactory.store('sync');
  static const String _kStateKey = 'state';
  static const String _kSinceField = 'since';

  Future<int> readSince() async {
    final db = await _database.db;
    final record = await _store.record(_kStateKey).get(db);
    final value = record?[_kSinceField];
    return value is int ? value : 0;
  }

  Future<void> writeSince(int since) async {
    final db = await _database.db;
    await _store.record(_kStateKey).put(db, {_kSinceField: since});
  }

  Future<void> cleanData() async {
    final db = await _database.db;
    await _store.record(_kStateKey).delete(db);
  }
}
