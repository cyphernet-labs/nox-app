import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/chat/chat_entity.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:sembast/sembast.dart';

/// Sembast store for chats (5.1) — cache-first, keyed by id and ordered newest-first
/// by `lastMessageAt` (ISO-8601 sorts chronologically) for the list + reactive watch.
/// A corrupt record is skipped rather than tearing down the read/stream.
@lazySingleton
class ChatDao {
  ChatDao(this._appDatabase);

  final AppDatabase _appDatabase;

  final StoreRef<String, Map<String, dynamic>> _store = stringMapStoreFactory.store('chats');

  /// Reactive stream of all cached chats, newest first.
  Stream<List<ChatEntity>> watch() async* {
    final db = await _appDatabase.db;
    yield* _store.query().onSnapshots(db).map((snaps) => _sortNewestFirst(_decode(snaps)));
  }

  /// All cached chats, newest first (the repo filters/paginates in memory over the
  /// small local set). Sorted in Dart on the ISO-8601 `lastMessageAt` (lexicographic
  /// order equals chronological order).
  Future<List<ChatEntity>> getAllSorted() async {
    final db = await _appDatabase.db;
    return _sortNewestFirst(_decode(await _store.query().getSnapshots(db)));
  }

  List<ChatEntity> _sortNewestFirst(List<ChatEntity> chats) {
    chats.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    return chats;
  }

  /// A single chat by id, or null if absent/undecodable. Record-key `get` (no Finder →
  /// the global `field_rename:snake` camelCase-filter gotcha does not apply).
  Future<ChatEntity?> getById(String id) async {
    final db = await _appDatabase.db;
    final value = await _store.record(id).get(db);
    return value == null ? null : _tryDecode(value);
  }

  /// Reactive stream of one chat by id (record-key `onSnapshot` → same no-Finder,
  /// field_rename-safe path as [getById]); emits null when the record is absent or
  /// undecodable. Drives the live name/avatar after a rename.
  Stream<ChatEntity?> watchById(String id) async* {
    final db = await _appDatabase.db;
    yield* _store.record(id).onSnapshot(db).map((snap) => snap == null ? null : _tryDecode(snap.value));
  }

  Future<int> count() async {
    final db = await _appDatabase.db;
    return _store.count(db);
  }

  /// Atomically write/replace a batch (used for the one-time seed).
  Future<void> saveData(List<ChatEntity> chats) async {
    final db = await _appDatabase.db;
    await db.transaction((txn) async {
      for (final chat in chats) {
        await _store.record(chat.id).put(txn, chat.toJson());
      }
    });
  }

  /// Atomic upsert of a single chat (create / update).
  Future<void> upsert(ChatEntity chat) async {
    final db = await _appDatabase.db;
    await db.transaction((txn) async {
      await _store.record(chat.id).put(txn, chat.toJson());
    });
  }

  /// Moves the mark forward only, and never past [ceiling].
  ///
  /// Monotonic because a badge must not resurrect: going backwards would make
  /// already-seen messages unread again. Clamped because a foreign seq space
  /// would otherwise poison it permanently - the debug inbound path once
  /// minted seqs from the clock, fifteen digits above anything a server
  /// issues, and one such message would put the mark somewhere no real event
  /// can ever reach, killing that chat's badge for good.
  Future<void> advanceReadMark({required String chatId, required int seq, required int ceiling}) async {
    final db = await _appDatabase.db;
    await db.transaction((txn) async {
      final record = await _store.record(chatId).get(txn);
      if (record == null) return;
      final entity = ChatEntity.fromJson(record);
      final capped = seq > ceiling ? ceiling : seq;
      // -1, not 0: "never opened" and "opened when nothing was cached" are
      // different states. Opening a chat offline with an empty cache marks 0,
      // which is a real open - history that arrives later is genuinely unread,
      // because nobody saw it. Collapsing the two would leave that chat
      // permanently badge-less.
      if (capped <= (entity.lastOpenedSeq ?? -1)) return;
      await _store.record(chatId).put(txn, entity.copyWith(lastOpenedSeq: capped).toJson());
    });
  }

  /// Drops every mark, leaving the rest of each chat row alone.
  ///
  /// Called before the sync cursor is cleared: a mark that outlived the cursor
  /// would sit above a rebuilt seq space and silently suppress every badge,
  /// and unlike a stale counter - which the next open resets - nothing ever
  /// repairs it.
  Future<void> clearReadMarks() async {
    final db = await _appDatabase.db;
    await db.transaction((txn) async {
      final records = await _store.find(txn);
      for (final record in records) {
        final entity = ChatEntity.fromJson(record.value);
        if (entity.lastOpenedSeq == null) continue;
        await _store.record(record.key).put(txn, entity.copyWith(lastOpenedSeq: null).toJson());
      }
    });
  }

  /// Drop every chat (logout).
  Future<void> cleanData() async {
    final db = await _appDatabase.db;
    await db.transaction((txn) async {
      await _store.delete(txn);
    });
  }

  List<ChatEntity> _decode(List<RecordSnapshot<String, Map<String, dynamic>>> snapshots) {
    final result = <ChatEntity>[];
    for (final snapshot in snapshots) {
      final entity = _tryDecode(snapshot.value);
      if (entity != null) result.add(entity);
    }
    return result;
  }

  ChatEntity? _tryDecode(Map<String, dynamic> value) {
    try {
      return ChatEntity.fromJson(value);
    } catch (_) {
      return null;
    }
  }
}
