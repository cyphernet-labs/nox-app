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

  /// Chats waiting to be created on the server (phase 041), the oldest first,
  /// so they reach it in the order they were made. Filtered in Dart over the
  /// decoded rows: a Finder on a camelCase key would match nothing under the
  /// global `field_rename: snake`.
  Future<List<ChatEntity>> pendingCreations() async {
    final db = await _appDatabase.db;
    final pending = _decode(await _store.query().getSnapshots(db)).where((c) => c.creation == 'pending').toList()
      ..sort((a, b) {
        final byTime = (a.createdAt ?? 0).compareTo(b.createdAt ?? 0);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    return pending;
  }

  /// Changes one chat inside a transaction and returns what was written, or
  /// null when there is no such chat. Read-modify-write in ONE transaction:
  /// the creation state and the name are changed while the list, the sync and
  /// the read mark write the same row.
  Future<ChatEntity?> update(String id, ChatEntity Function(ChatEntity current) change) async {
    final db = await _appDatabase.db;
    return db.transaction((txn) async {
      final stored = await _store.record(id).get(txn);
      final current = stored == null ? null : _tryDecode(stored);
      if (current == null) return null;
      final next = change(current);
      await _store.record(id).put(txn, next.toJson());
      return next;
    });
  }

  /// Removes one chat. Only for a local copy the server replaced with its own
  /// id (phase 041); chats are never deleted otherwise.
  Future<void> delete(String id) async {
    final db = await _appDatabase.db;
    await _store.record(id).delete(db);
  }

  /// Atomically write/replace a batch (used for the one-time seed).
  Future<void> saveData(List<ChatEntity> chats) async {
    final db = await _appDatabase.db;
    await db.transaction((txn) async {
      for (final chat in chats) {
        await _store.record(chat.id).put(txn, (await _keepingReadMark(txn, chat)).toJson());
      }
    });
  }

  /// Atomic upsert of a single chat (create / update).
  Future<void> upsert(ChatEntity chat) async {
    final db = await _appDatabase.db;
    await db.transaction((txn) async {
      await _store.record(chat.id).put(txn, (await _keepingReadMark(txn, chat)).toJson());
    });
  }

  /// [chat] with the stored read mark kept when [chat] carries an older one.
  ///
  /// Writers carry the mark forward from a read made BEFORE this transaction,
  /// and a mark advanced in between - the chat opened while a page of chats
  /// was on its way from the server - would be put back by the write, bringing
  /// a badge back for messages already seen. The mark only moves forward
  /// ([advanceReadMark]); only [clearReadMarks] takes it away.
  Future<ChatEntity> _keepingReadMark(Transaction txn, ChatEntity chat) async {
    final stored = await _store.record(chat.id).get(txn);
    final mark = stored == null ? null : _tryDecode(stored)?.lastOpenedSeq;
    if (mark == null || (chat.lastOpenedSeq ?? -1) >= mark) return chat;
    return chat.copyWith(lastOpenedSeq: mark);
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
