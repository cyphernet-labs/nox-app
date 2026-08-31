import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/chat/outbox_entity.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:sembast/sembast.dart';

/// Sembast store for the outgoing queue (contract v0 §9.3/§9.8).
///
/// The record key IS the `client_message_id`. That is not a convenience: a
/// store cannot hold two rows under one key, so re-enqueuing the same key can
/// never produce a second copy — the property the whole feature rests on.
///
/// Ordering is by [OutboxEntity.ordinal] and never by time: goldens freeze the
/// clock, so a burst of sends shares `createdAt` to the millisecond. A corrupt
/// record is skipped rather than tearing down the read/stream.
@lazySingleton
class OutboxDao {
  OutboxDao(this._appDatabase);

  final AppDatabase _appDatabase;

  final StoreRef<String, Map<String, dynamic>> _store = stringMapStoreFactory.store('outbox');

  /// Reactive stream of the queue in send order, optionally narrowed to one chat.
  ///
  /// Filtering happens in Dart, not through a [Filter]: the global
  /// `field_rename: snake` writes `chat_id` to disk, so a Finder on the
  /// camelCase key would silently match nothing.
  Stream<List<OutboxEntity>> watch({String? chatId}) async* {
    final db = await _appDatabase.db;
    yield* _store.query().onSnapshots(db).map((snaps) => _ordered(_decode(snaps), chatId));
  }

  /// The whole queue in send order, optionally narrowed to one chat.
  Future<List<OutboxEntity>> getAllSorted({String? chatId}) async {
    final db = await _appDatabase.db;
    return _ordered(_decode(await _store.query().getSnapshots(db)), chatId);
  }

  /// Appends [entity] at the tail, returning it with the assigned ordinal.
  ///
  /// The max-scan and the write share one transaction: two concurrent enqueues
  /// would otherwise read the same max and both claim it, and the queue would
  /// have no defined order at exactly the moment order matters most.
  Future<OutboxEntity> enqueue(OutboxEntity entity) async {
    final db = await _appDatabase.db;
    return db.transaction((txn) async {
      final existing = _decode(await _store.query().getSnapshots(txn));
      final highest = existing.fold<int>(0, (max, e) => e.ordinal > max ? e.ordinal : max);
      final placed = entity.copyWith(ordinal: highest + 1);
      await _store.record(placed.clientMessageId).put(txn, placed.toJson());
      return placed;
    });
  }

  /// Rewrites an existing record in place (status / attempts / last error).
  Future<void> update(OutboxEntity entity) async {
    final db = await _appDatabase.db;
    await db.transaction((txn) async {
      await _store.record(entity.clientMessageId).put(txn, entity.toJson());
    });
  }

  Future<OutboxEntity?> getById(String clientMessageId) async {
    final db = await _appDatabase.db;
    final value = await _store.record(clientMessageId).get(db);
    return value == null ? null : _tryDecode(value);
  }

  Future<void> remove(String clientMessageId) async {
    final db = await _appDatabase.db;
    await _store.record(clientMessageId).delete(db);
  }

  /// Drops the queue of one chat (the debug-scenario reset).
  Future<void> removeForChat(String chatId) async {
    final db = await _appDatabase.db;
    await db.transaction((txn) async {
      for (final entity in _decode(await _store.query().getSnapshots(txn))) {
        if (entity.chatId == chatId) await _store.record(entity.clientMessageId).delete(txn);
      }
    });
  }

  /// Empties the queue (logout). The records hold message texts, so this runs in
  /// the same wipe as the chats and messages stores.
  Future<void> cleanData() async {
    final db = await _appDatabase.db;
    await db.transaction((txn) async {
      await _store.delete(txn);
    });
  }

  List<OutboxEntity> _ordered(List<OutboxEntity> entities, String? chatId) {
    final filtered = chatId == null ? entities : entities.where((e) => e.chatId == chatId).toList();
    filtered.sort((a, b) {
      final byOrdinal = a.ordinal.compareTo(b.ordinal);
      // Rows written before `ordinal` existed all decode as 0; the key keeps the
      // order total instead of leaving it up to store iteration.
      return byOrdinal != 0 ? byOrdinal : a.clientMessageId.compareTo(b.clientMessageId);
    });
    return filtered;
  }

  List<OutboxEntity> _decode(List<RecordSnapshot<String, Map<String, dynamic>>> snapshots) {
    final result = <OutboxEntity>[];
    for (final snapshot in snapshots) {
      final entity = _tryDecode(snapshot.value);
      if (entity != null) result.add(entity);
    }
    return result;
  }

  OutboxEntity? _tryDecode(Map<String, dynamic> value) {
    try {
      return OutboxEntity.fromJson(value);
    } catch (_) {
      return null;
    }
  }
}
