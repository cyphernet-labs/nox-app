import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/chat/wire/chat_wire_entity.dart';
import 'package:nox_app/data/entity/chat/wire/message_wire_entity.dart';
import 'package:nox_app/data/local/chat/chat_dao.dart';
import 'package:nox_app/data/local/chat/message_dao.dart';
import 'package:nox_app/data/mapper/chat/chat_mapper.dart';
import 'package:nox_app/data/mapper/chat/chat_wire_mapper.dart';
import 'package:nox_app/data/mapper/chat/message_mapper.dart';
import 'package:nox_app/data/mapper/chat/message_wire_mapper.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/remote/socket/server_frame.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:nox_app/general/formatters/chat_preview_formatter.dart';

/// Applies journal events into the local stores.
///
/// Writing to the DAOs is deliberately the whole job: the repositories already
/// project those stores through `watchChats`/`watchMessages`, so an applied
/// event reaches the screens without a single change in the presentation layer.
///
/// Two rules from the contract shape everything here. Application MERGES onto
/// the stored row rather than replacing it, because the wire carries none of
/// the device-local state (§6, §8.3). And the cursor advances only AFTER a
/// successful write (§9.4), so a crash in between costs a redelivery — which
/// dedup absorbs — rather than a lost message.
@LazySingleton(env: [Environment.dev])
class SyncService {
  SyncService(
    this._socket,
    this._syncRepository,
    this._chatDao,
    this._messageDao,
    this._chatMapper,
    this._chatWireMapper,
    this._messageMapper,
    this._messageWireMapper,
  );

  final NoxSocketClient _socket;
  final SyncRepository _syncRepository;
  final ChatDao _chatDao;
  final MessageDao _messageDao;
  final ChatMapper _chatMapper;
  final ChatWireMapper _chatWireMapper;
  final MessageMapper _messageMapper;
  final MessageWireMapper _messageWireMapper;

  StreamSubscription<ServerEvent>? _subscription;

  /// Starts applying events. Must be subscribed BEFORE the socket connects, or
  /// the replay that follows the greeting would arrive with nobody listening.
  void start() {
    _subscription ??= _socket.events.listen(
      _apply,
      onError: (Object e, StackTrace s) => logRepository.error(target: this, error: e, stackTrace: s),
    );
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _apply(ServerEvent event) async {
    try {
      // Duplicates are allowed at the replay/live boundary (§3) — the cursor is
      // what tells them apart, so anything at or below it has been applied.
      if (event.seq <= await _syncRepository.getCursor()) return;
      switch (event.event) {
        case ServerEvent.chatCreated:
        case ServerEvent.chatUpdated:
          await _applyChat(event.data);
        case ServerEvent.messageNew:
          await _applyMessage(event.data);
        default:
          // v0 evolves: an unknown event is ignored, not fatal (§2.1).
          logRepository.debug(target: this, message: 'sync: unknown event ignored: ${event.event}');
      }
      await _syncRepository.advanceCursor(event.seq);
    } catch (error, stackTrace) {
      // A failed apply must NOT advance the cursor: the event will be
      // redelivered on the next catch-up, which is the safe direction.
      logRepository.error(target: this, error: error, stackTrace: stackTrace);
    }
  }

  Future<void> _applyChat(Map<String, dynamic> data) async {
    final wire = _chatWireMapper.toModel(entity: ChatWireEntity.fromJson(data));
    final existing = await _chatDao.getById(wire.id);
    // The unread badge is this device's alone — the wire has no such field, so
    // taking the wire row wholesale would silently clear it.
    await _chatDao.upsert(_chatMapper.toEntity(model: wire.copyWith(unreadCount: existing?.unreadCount ?? 0)));
  }

  Future<void> _applyMessage(Map<String, dynamic> data) async {
    final wire = _messageWireMapper.toModel(entity: MessageWireEntity.fromJson(data));
    final existing = await _messageDao.getById(wire.id);
    // localPath and the local delivery status are device-local; an echo or a
    // redelivery must not wipe the path that makes a sent image previewable.
    final merged = existing == null
        ? wire
        : wire.copyWith(
            attachment: wire.attachment?.copyWith(localPath: existing.attachmentLocalPath),
            status: _messageMapper.toModel(entity: existing).status,
          );
    await _messageDao.upsert(_messageMapper.toEntity(model: merged));
    // The server does NOT emit chat.updated for a new message (§6): the preview,
    // the activity time and the ordering are the client's to fold.
    final chat = await _chatDao.getById(wire.chatId);
    if (chat == null) return;
    await _chatDao.upsert(
      chat.copyWith(
        lastMessagePreview: chatPreviewFor(merged),
        lastMessageAt: merged.sentAt.toUtc().toIso8601String(),
        unreadCount: chat.unreadCount + 1,
      ),
    );
  }
}
