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
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
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
    this._outbox,
  );

  final NoxSocketClient _socket;
  final SyncRepository _syncRepository;
  final ChatDao _chatDao;
  final MessageDao _messageDao;
  final ChatMapper _chatMapper;
  final ChatWireMapper _chatWireMapper;
  final MessageMapper _messageMapper;
  final MessageWireMapper _messageWireMapper;
  final OutboxRepository _outbox;

  StreamSubscription<ServerEvent>? _subscription;
  StreamSubscription<SessionPhase>? _phaseSubscription;

  /// Serialises applies. The stream does not await the handler, so a replay
  /// burst would otherwise run every apply concurrently and the read-modify-
  /// write of a chat row would lose updates.
  Future<void> _queue = Future<void>.value();

  /// Set when an apply fails. The cursor takes the MAX of what it is given, so
  /// letting later events keep advancing it would step straight over the failed
  /// one and it would never be redelivered — the opposite of the guarantee.
  ///
  /// Cleared when a new catch-up begins: the cursor never moved past the gap,
  /// so the replay redelivers the failed event and applying can resume. Without
  /// that reset a single transient write error would silence this device for
  /// the rest of the process.
  bool _halted = false;

  /// Starts applying events. Must be subscribed BEFORE the socket connects, or
  /// the replay that follows the greeting would arrive with nobody listening.
  void start() {
    _subscription ??= _socket.events.listen(
      (event) => _queue = _queue.then((_) => _apply(event)),
      onError: (Object e, StackTrace s) => logRepository.error(target: this, error: e, stackTrace: s),
    );
    _phaseSubscription ??= _socket.phase.listen((phase) {
      if (phase == SessionPhase.catchingUp && _halted) {
        logRepository.debug(target: this, message: 'sync: resuming, the replay redelivers what failed');
        _halted = false;
      }
    });
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _phaseSubscription?.cancel();
    _phaseSubscription = null;
    _halted = false;
  }

  Future<void> _apply(ServerEvent event) async {
    // Once an apply has failed, everything after it waits for the next
    // catch-up: applying later events would advance the cursor past the gap.
    if (_halted) return;
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
      // A failed apply must NOT advance the cursor, and nothing after it may
      // either: the whole tail is redelivered on the next catch-up, which is
      // the safe direction.
      _halted = true;
      logRepository.error(target: this, error: error, stackTrace: stackTrace);
    }
  }

  Future<void> _applyChat(Map<String, dynamic> data) async {
    final wire = _chatWireMapper.toModel(entity: ChatWireEntity.fromJson(data));
    final existing = await _chatDao.getById(wire.id);
    // The unread badge is this device's alone — the wire has no such field, so
    // taking the wire row wholesale would silently clear it.
    await _chatDao.upsert(
      _chatMapper.toEntity(
        model: wire.copyWith(unreadCount: existing?.unreadCount ?? 0),
        lastOpenedSeq: existing?.lastOpenedSeq,
      ),
    );
  }

  Future<void> _applyMessage(Map<String, dynamic> data) async {
    final entity = MessageWireEntity.fromJson(data);
    // Contract §5: an own message carries back the key it was sent with, and
    // only an own message does. Seeing it means the server already has this
    // send, so the queue entry is settled — dropping it is what stops a restart
    // from re-sending something that arrived before the crash. The resend would
    // be harmless (idempotency covers it) but not free: a round trip, and the
    // bubble stays queued until the answer comes back.
    final clientMessageId = entity.clientMessageId;
    final settled = clientMessageId == null || clientMessageId.isEmpty ? null : await _outbox.find(clientMessageId: clientMessageId);

    final wire = _messageWireMapper.toModel(entity: entity);
    final existing = await _messageDao.getById(wire.id);
    // localPath and the local delivery status are device-local; an echo or a
    // redelivery must not wipe the path that makes a sent image previewable.
    //
    // On the FIRST arrival there is no stored row to take the path from, and
    // the wire never carries one — the queue entry is the only place it still
    // exists, so it has to be read across before the entry is dropped.
    final localPath = existing?.attachmentLocalPath ?? settled?.attachment?.localPath;
    final merged = existing == null && settled == null
        ? wire
        : wire.copyWith(
            attachment: wire.attachment?.copyWith(localPath: localPath),
            status: existing == null ? wire.status : _messageMapper.toModel(entity: existing).status,
          );
    await _messageDao.upsert(_messageMapper.toEntity(model: merged));
    // Only now: the same order the drain uses, and for the same reason — the
    // entry is the message's only home until the message itself is stored.
    if (settled != null) await _outbox.remove(clientMessageId: settled.clientMessageId);
    // The server does NOT emit chat.updated for a new message (§6): the preview,
    // the activity time and the ordering are the client's to fold.
    final chat = await _chatDao.getById(wire.chatId);
    if (chat == null) return;
    await _chatDao.upsert(
      chat.copyWith(
        lastMessagePreview: chatPreviewFor(merged),
        lastMessageAt: merged.sentAt.toUtc().toIso8601String(),
        // No increment. The badge is recounted from the chat's read mark, so
        // an event delivered twice at the replay/live boundary - which §3
        // explicitly permits - counts once, and the sender's own echo counts
        // not at all, by construction rather than by a special case.
      ),
    );
  }
}
