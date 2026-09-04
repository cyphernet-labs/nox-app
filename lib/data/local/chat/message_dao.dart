import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/chat/message_entity.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:sembast/sembast.dart';

/// Sembast store for chat messages (5.2) — cache-first, keyed by id, chat-scoped and
/// ordered by the server journal `seq` (sentAt/id tiebreak). A corrupt record is skipped.
@lazySingleton
class MessageDao {
  MessageDao(this._appDatabase);

  final AppDatabase _appDatabase;

  final StoreRef<String, Map<String, dynamic>> _store = stringMapStoreFactory.store('messages');

  /// Reactive stream of a chat's messages, chronological.
  Stream<List<MessageEntity>> watch(String chatId) async* {
    final db = await _appDatabase.db;
    yield* _store.query().onSnapshots(db).map((s) => _forChat(_decode(s), chatId));
  }

  /// All messages in a chat, chronological (oldest first); the repo paginates the
  /// newest batch first over this small local list.
  Future<List<MessageEntity>> getByChatSorted(String chatId) async {
    final db = await _appDatabase.db;
    return _forChat(_decode(await _store.query().getSnapshots(db)), chatId);
  }

  Future<int> countByChat(String chatId) async => (await getByChatSorted(chatId)).length;

  /// The highest seq cached for a chat, or null when nothing is cached.
  Future<int?> highestSeq(String chatId) async {
    // seq is nullable on the entity: pre-025 rows and locally-minted optimistic
    // sends have none. A row without a seq has no place in the journal order,
    // so it neither raises the mark nor counts against it.
    final seqs = (await getByChatSorted(chatId)).map((m) => m.seq).nonNulls;
    if (seqs.isEmpty) return null;
    return seqs.reduce((a, b) => a > b ? a : b);
  }

  /// How many cached messages sit above [aboveSeq] and were not written by us.
  ///
  /// Counted in Dart over decoded entities rather than by a Finder: the global
  /// snake_case field rename means a query keyed on a camelCase field name
  /// silently matches nothing.
  ///
  /// This is a recount, not a running total, and that is the point: the
  /// protocol permits the same event to arrive twice at the replay/live
  /// boundary, and counting the set is idempotent where incrementing was not.
  Future<int> countUnread({required String chatId, required int? aboveSeq, required Set<String> excludeAuthors}) async {
    // Never opened means no badge at all, by the product spec.
    if (aboveSeq == null) return 0;
    final messages = await getByChatSorted(chatId);
    return messages.where((m) {
      final seq = m.seq;
      return seq != null && seq > aboveSeq && !excludeAuthors.contains(m.authorId);
    }).length;
  }

  /// One message by id, or null. Record-key lookup, so it is unaffected by the
  /// `field_rename: snake` gotcha that makes a Finder on a camelCase key match
  /// nothing.
  Future<MessageEntity?> getById(String id) async {
    final db = await _appDatabase.db;
    final value = await _store.record(id).get(db);
    return value == null ? null : _tryDecode(value);
  }

  /// Filter by the typed entity field, then chronological order (small local store).
  /// NB: filtering in Dart — not via a sembast Finder on the stored map — because
  /// `field_rename: snake` persists `chatId` as `chat_id`, so a `Filter.equals('chatId', …)`
  /// would never match the stored key and silently return nothing.
  List<MessageEntity> _forChat(List<MessageEntity> messages, String chatId) =>
      _sortChrono(messages.where((m) => m.chatId == chatId).toList());

  /// Atomically write/replace a batch (the one-time per-chat seed).
  Future<void> saveData(List<MessageEntity> messages) async {
    final db = await _appDatabase.db;
    await db.transaction((txn) async {
      for (final message in messages) {
        await _store.record(message.id).put(txn, message.toJson());
      }
    });
  }

  /// Atomic upsert of a single message (send).
  Future<void> upsert(MessageEntity message) async {
    final db = await _appDatabase.db;
    await db.transaction((txn) async {
      await _store.record(message.id).put(txn, message.toJson());
    });
  }

  Future<void> cleanData() async {
    final db = await _appDatabase.db;
    await db.transaction((txn) async {
      await _store.delete(txn);
    });
  }

  /// The server journal number (seq) is the authoritative order (contract §5);
  /// sentAt breaks ties for legacy pre-025 rows (seq null → 0, a whole-chat
  /// block on an upgraded-in-place DB) and the id makes the order total, so
  /// same-second wire timestamps (unix-second precision) can never reorder
  /// rows against their seq via an unstable sort.
  List<MessageEntity> _sortChrono(List<MessageEntity> messages) {
    messages.sort((a, b) {
      final bySeq = (a.seq ?? 0).compareTo(b.seq ?? 0);
      if (bySeq != 0) return bySeq;
      final byTime = a.sentAt.compareTo(b.sentAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    return messages;
  }

  List<MessageEntity> _decode(List<RecordSnapshot<String, Map<String, dynamic>>> snapshots) {
    final result = <MessageEntity>[];
    for (final snapshot in snapshots) {
      final entity = _tryDecode(snapshot.value);
      if (entity != null) result.add(entity);
    }
    return result;
  }

  MessageEntity? _tryDecode(Map<String, dynamic> value) {
    try {
      return MessageEntity.fromJson(value);
    } catch (_) {
      return null;
    }
  }
}
