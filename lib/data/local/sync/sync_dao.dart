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

  /// A SEPARATE record, not another field on `state`: the cursor writers replace
  /// the whole `state` map, so an epoch stored alongside `since` would be wiped
  /// by the next advance and re-trigger the one-time wipe forever.
  static const String _kEpochKey = 'epoch';
  static const String _kEpochField = 'source';

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

  /// Atomically raises `since` to [seq] when higher — the read and the
  /// conditional write share one transaction, so concurrent advances can never
  /// interleave and persist a lower value after a higher one.
  Future<void> advanceSince(int seq) async {
    final db = await _database.db;
    await db.transaction((txn) async {
      final record = await _store.record(_kStateKey).get(txn);
      final current = record?[_kSinceField];
      final since = current is int ? current : 0;
      if (seq > since) await _store.record(_kStateKey).put(txn, {_kSinceField: seq});
    });
  }

  Future<String?> readEpoch() async {
    final db = await _database.db;
    final record = await _store.record(_kEpochKey).get(db);
    final value = record?[_kEpochField];
    return value is String ? value : null;
  }

  Future<void> writeEpoch(String epoch) async {
    final db = await _database.db;
    await _store.record(_kEpochKey).put(db, {_kEpochField: epoch});
  }

  /// Drops the cursor. The epoch deliberately SURVIVES: it describes which world
  /// the local data came from, and a logout does not change that world.
  Future<void> cleanData() async {
    final db = await _database.db;
    await _store.record(_kStateKey).delete(db);
  }
}
