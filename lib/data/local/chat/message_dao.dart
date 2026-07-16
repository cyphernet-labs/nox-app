import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/chat/message_entity.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:sembast/sembast.dart';

/// Sembast store for chat messages (5.2) — cache-first, keyed by id, chat-scoped and
/// chronological (oldest first) by ISO-8601 `sentAt`. A corrupt record is skipped.
@lazySingleton
class MessageDao {
  MessageDao(this._appDatabase);

  final AppDatabase _appDatabase;

  final StoreRef<String, Map<String, dynamic>> _store = stringMapStoreFactory.store('messages');

  /// Reactive stream of a chat's messages, chronological.
  Stream<List<MessageEntity>> watch(String chatId) async* {
    final db = await _appDatabase.db;
    yield* _store.query(finder: Finder(filter: Filter.equals('chatId', chatId))).onSnapshots(db).map((s) => _sortChrono(_decode(s)));
  }

  /// All messages in a chat, chronological (oldest first); the repo paginates the
  /// newest batch first over this small local list.
  Future<List<MessageEntity>> getByChatSorted(String chatId) async {
    final db = await _appDatabase.db;
    final finder = Finder(filter: Filter.equals('chatId', chatId));
    return _sortChrono(_decode(await _store.query(finder: finder).getSnapshots(db)));
  }

  Future<int> countByChat(String chatId) async {
    final db = await _appDatabase.db;
    return _store.count(db, filter: Filter.equals('chatId', chatId));
  }

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

  List<MessageEntity> _sortChrono(List<MessageEntity> messages) {
    messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
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
