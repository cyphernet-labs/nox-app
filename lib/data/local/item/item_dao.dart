import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/item/item_entity.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:sembast/sembast.dart';

/// Sembast store for the cacheable single `Item` entity — the reference
/// cache-first DAO for the skeleton.
///
/// Network-only carve-out (data-model §2.4): the paginated `getItems` list is a
/// server-owned list and goes through the network-only branch, so it does NOT
/// use this DAO. The DAO exists for the `watch()` (reactive cache) path and gets
/// wired up with the first genuinely cacheable feature. A broken record is
/// skipped rather than killing the stream; a storage failure throws raw and is
/// mapped to RepositoryException.unknown by the repository's catch-all execute().
@lazySingleton
class ItemDao {
  ItemDao(this._appDatabase);

  final AppDatabase _appDatabase;

  final StoreRef<String, Map<String, dynamic>> _store = stringMapStoreFactory.store('items');

  /// Reactive stream of all cached records (keyed by id). Broken records are
  /// dropped, so a single corrupt entry never tears down the stream.
  Stream<List<ItemEntity>> watch() async* {
    final db = await _appDatabase.db;
    yield* _store.query().onSnapshots(db).map(_decode);
  }

  /// One-shot read of every cached record.
  Future<List<ItemEntity>> getData() async {
    final db = await _appDatabase.db;
    return _decode(await _store.query().getSnapshots(db));
  }

  /// One-shot read of a single record by id; null if absent or corrupt.
  Future<ItemEntity?> getById(String id) async {
    final db = await _appDatabase.db;
    final value = await _store.record(id).get(db);
    return value == null ? null : _tryDecode(value);
  }

  /// Atomically write/replace a batch of records.
  Future<void> saveData(List<ItemEntity> items) async {
    final db = await _appDatabase.db;
    await db.transaction((txn) async {
      for (final item in items) {
        await _store.record(item.id).put(txn, item.toJson());
      }
    });
  }

  /// Atomic upsert of a single record.
  Future<void> upsert(ItemEntity item) async {
    final db = await _appDatabase.db;
    await db.transaction((txn) async {
      await _store.record(item.id).put(txn, item.toJson());
    });
  }

  /// Delete a single record by id.
  Future<void> removeById(String id) async {
    final db = await _appDatabase.db;
    await db.transaction((txn) async {
      await _store.record(id).delete(txn);
    });
  }

  /// Drop every record in the store.
  Future<void> cleanData() async {
    final db = await _appDatabase.db;
    await db.transaction((txn) async {
      await _store.delete(txn);
    });
  }

  List<ItemEntity> _decode(List<RecordSnapshot<String, Map<String, dynamic>>> snapshots) {
    final result = <ItemEntity>[];
    for (final snapshot in snapshots) {
      final entity = _tryDecode(snapshot.value);
      if (entity != null) result.add(entity);
    }
    return result;
  }

  /// A corrupt record decodes to null (skipped) instead of throwing.
  ItemEntity? _tryDecode(Map<String, dynamic> value) {
    try {
      return ItemEntity.fromJson(value);
    } catch (_) {
      return null;
    }
  }
}
