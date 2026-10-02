import 'dart:async';
import 'dart:math';

import 'package:injectable/injectable.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/exception/base_repository_exception.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/chat/chat_creation.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/outbox_entry.dart';
import 'package:nox_app/domain/model/chat/outbox_status.dart';
import 'package:nox_app/domain/model/chat/pending_chat_creation.dart';
import 'package:nox_app/domain/model/file/attachment_transfer.dart';
import 'package:nox_app/domain/model/file/mime_types.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/domain/repository/file/file_repository.dart';
import 'package:nox_app/domain/service/attachment_transfer_service.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';

/// Drains the outgoing queue — and is the ONLY thing that sends.
///
/// Single sender is the load-bearing rule. Before this feature two places sent
/// (typing in the thread, and the reconnect re-delivery), and a connectivity
/// flap could run both over the same message. A duplicate in a journal with no
/// deletion cannot be taken back, so the whole design collapses into one
/// serialised drain.
@LazySingleton(env: [Environment.dev, Environment.prod, Environment.test])
class OutboxService {
  OutboxService(this._outbox, this._messages, this._phaseService, this._files, this._transfers, this._chats);

  final OutboxRepository _outbox;
  final MessageRepository _messages;
  final SessionPhaseService _phaseService;
  final FileRepository _files;

  /// Where the bubble of a message with a file learns how far its bytes have
  /// got. Without it the only sign of a send was a clock icon, the same for a
  /// text that goes in a blink and for a picture that takes a minute through
  /// Tor.
  final AttachmentTransferService _transfers;

  /// Chats created on this device and not yet on the server (phase 041). The
  /// queue creates them before it sends anything, and holds the messages of a
  /// chat the server does not have.
  final ChatRepository _chats;

  /// When each chat waiting to be created may be tried again, after a
  /// failure worth retrying. Its own pause, apart from the messages' one: a
  /// creation the server keeps failing holds the messages of ITS chat and
  /// nothing else (FR-006). In memory - after a restart the first pass tries
  /// at once, and the attempts on the row carry the ladder on from there.
  final Map<String, DateTime> _creationRetryAt = <String, DateTime>{};
  Timer? _creationTimer;

  static const Duration _minBackoff = Duration(seconds: 1);
  static const Duration _maxBackoff = Duration(seconds: 30);

  /// How many times the SERVER may refuse an entry before it is set aside.
  ///
  /// Counted against refusals only, never against a broken connection. That
  /// distinction is the whole point: a flapping link produces failure after
  /// failure through no fault of the message, and counting those would set a
  /// perfectly good message aside within seconds of a bad tunnel.
  ///
  /// Set aside is not discarded — the entry stays in the queue, visible, and a
  /// tap replenishes the ladder and sends it again. What the cap buys is the
  /// spec's edge case: a message the server keeps refusing with a retryable
  /// code (a persistent `internal`) would otherwise block every later message
  /// in every chat forever, because the queue is one strictly-ordered line.
  static const int _autoRetryLimit = 10;

  StreamSubscription<SessionPhase>? _phaseSubscription;
  Timer? _retryTimer;

  /// The entry a backoff pause is waiting out, or null when nothing is paused.
  ///
  /// Keyed to the entry rather than kept as a bare flag, because a pause has to
  /// end when its reason does: discard the failing head, or let the server's
  /// echo settle it, and a plain flag would keep every later message waiting on
  /// a record that no longer exists.
  String? _pausedFor;

  /// Set by [stop] and cleared by [start]: the drain stays off in between.
  ///
  /// It has to outlive the stop() call itself. Logout stops the drain and then
  /// empties the store; a flush arriving from anywhere in that window — a bloc
  /// still alive on a screen being torn down — would otherwise send into a wipe.
  /// It also stops a pass finishing mid-stop from arming a new timer behind the
  /// cancel that was supposed to end it.
  bool _stopped = false;

  /// Serialises drains. A phase flap plus a fresh send would otherwise run two
  /// passes over the same records and post the head of the queue twice.
  Future<void> _queue = Future<void>.value();

  final Random _random = Random();

  /// Subscribes to the session phase. Idempotent — main() calls it once, but a
  /// second call must not open a second subscription.
  void start() {
    _stopped = false;
    _phaseSubscription ??= _phaseService.watchPhase().listen((phase) {
      if (!phase.isCurrent) return;
      // A fresh live channel is a new reason to try: whatever the pause was
      // waiting out, the condition that caused it has just changed.
      _retryTimer?.cancel();
      _retryTimer = null;
      _pausedFor = null;
      _creationTimer?.cancel();
      _creationTimer = null;
      _creationRetryAt.clear();
      unawaited(flush());
    });
  }

  /// Runs a drain pass, chained after any pass already running.
  ///
  /// The chain absorbs errors deliberately. `_queue.then(...)` on a rejected
  /// future stays rejected forever, so one failed read — a store hiccup, a
  /// teardown mid-pass — would silently end sending for the life of the
  /// process. Whatever went wrong, the queue is still on disk and the next
  /// trigger deserves a real attempt.
  Future<void> flush() {
    _queue = _queue.then((_) => _drain()).catchError((Object error, StackTrace stackTrace) {
      logRepository.error(target: this, error: error, stackTrace: stackTrace);
    });
    return _queue;
  }

  /// Cancels the subscription and any pending retry. Called before the logout
  /// wipe: a pass still in flight would write a message into the store the wipe
  /// is in the middle of emptying.
  Future<void> stop() async {
    _stopped = true;
    await _phaseSubscription?.cancel();
    _phaseSubscription = null;
    // Let a pass that is already running finish before the caller wipes.
    await _queue;
    // Cancel AFTER the pass: a retryable refusal in those last moments arms a
    // new timer, and cancelling first would leave it running past the stop.
    _retryTimer?.cancel();
    _retryTimer = null;
    _pausedFor = null;
    _creationTimer?.cancel();
    _creationTimer = null;
    _creationRetryAt.clear();
  }

  Future<void> _drain() async {
    // Sending with no live channel only burns an attempt and grows the backoff
    // for a reason that has nothing to do with the message.
    if (!_phaseService.phase.isCurrent) return;
    if (_stopped) return;

    // Chats first: a message can only name a chat the server has.
    await _createPendingChats();
    if (_stopped || !_phaseService.phase.isCurrent) return;

    final queued = await _outbox.pending();
    // A pause applies to ONE entry. If that entry is no longer what the pass
    // would try first — discarded, or settled by the server's echo — its pause
    // has outlived its reason and must not hold the rest of the queue.
    if (_pausedFor != null) {
      if (await _pauseStillHolds(queued, _pausedFor!)) return;
      _retryTimer?.cancel();
      _retryTimer = null;
      _pausedFor = null;
    }
    for (final snapshot in queued) {
      // Re-read immediately before sending. The snapshot was taken once, and a
      // pass spans as long as the sends ahead of this entry take — seconds on a
      // slow link. Anything the user discarded in that window is gone from the
      // store, and sending it anyway would publish, permanently, a message they
      // were already shown had been cancelled.
      final entry = await _outbox.find(clientMessageId: snapshot.clientMessageId);
      if (entry == null || entry.status != OutboxStatus.pending) continue;
      // Held, not failed: its chat is not on the server yet. No attempt is
      // spent on it - nobody tried to send it - and the messages of other
      // chats do not wait on it.
      if (!await _chats.isOnServer(chatId: entry.chatId)) continue;

      final sent = await _send(entry);
      // A retryable refusal stops the pass: everything behind this entry has to
      // wait, or the queue would arrive out of order.
      if (!sent) return;
    }
  }

  /// Whether the entry a pause waits out is still the one the pass would try
  /// first: the first message whose chat the server has. A held message - its
  /// chat not created yet - is not tried, so it cannot be "first".
  Future<bool> _pauseStillHolds(List<OutboxEntry> queued, String key) async {
    for (final entry in queued) {
      if (!await _chats.isOnServer(chatId: entry.chatId)) continue;
      return entry.clientMessageId == key;
    }
    return false;
  }

  /// Creates on the server every chat that waits for it, the oldest first
  /// (phase 041). Never stops the pass: a creation that fails holds the
  /// messages of its own chat and waits out its own pause, and the messages of
  /// other chats go on.
  Future<void> _createPendingChats() async {
    final waiting = await _chats.pendingCreations();
    // A pause outlives its chat when the chat stopped waiting some other way -
    // the server's own event, a rename after `name_taken` - and a stale one
    // would wake the queue for nothing and push a live pause's wake-up aside.
    final ids = {for (final pending in waiting) pending.chat.id};
    _creationRetryAt.removeWhere((id, _) => !ids.contains(id));
    for (final pending in waiting) {
      if (_stopped || !_phaseService.phase.isCurrent) break;
      final retryAt = _creationRetryAt[pending.chat.id];
      if (retryAt != null && DateTime.now().isBefore(retryAt)) continue;
      await _createOnServer(pending);
    }
    _armCreationTimer();
  }

  Future<void> _createOnServer(PendingChatCreation waiting) async {
    final chatId = waiting.chat.id;
    final result = await _chats.createOnServer(chat: waiting.chat);
    final created = result.data;
    if (created != null) {
      // A server older than phase 041 skipped the id and made one of its own
      // (contract §2.1): the messages written into the chat follow it, then the
      // local copy goes. In this order, so no message is ever left naming a
      // chat that is no longer anywhere.
      if (created.id != chatId) {
        await _outbox.moveChat(from: chatId, to: created.id);
        await _chats.adoptServerChat(localId: chatId, serverChat: created);
      }
      _creationRetryAt.remove(chatId);
      // Ids and codes only, never the chat's name.
      logRepository.debug(target: this, message: 'outbox: chat created id=${created.id}');
      return;
    }

    final exception = result.exception;
    final code = exception is RepositoryException ? exception.name : 'unknown';
    logRepository.debug(target: this, message: 'outbox: chat creation failed id=$chatId code=$code');
    if (exception == RepositoryException.nameTaken) {
      _creationRetryAt.remove(chatId);
      await _chats.markCreation(chatId: chatId, creation: ChatCreation.nameTaken, attempts: waiting.attempts);
      return;
    }
    final attempts = waiting.attempts + 1;
    // A server that keeps refusing - not a dead channel - would otherwise hold
    // the one queue for every chat, for good; the same cap as for a message.
    final refused = exception != RepositoryException.connection;
    if (_isTerminal(exception) || (refused && attempts >= _autoRetryLimit)) {
      _creationRetryAt.remove(chatId);
      await _chats.markCreation(chatId: chatId, creation: ChatCreation.failed, attempts: attempts);
      return;
    }
    await _chats.markCreation(chatId: chatId, creation: ChatCreation.pending, attempts: attempts);
    // The same ladder a message climbs; the count comes from the row, so it
    // survives a restart.
    _creationRetryAt[chatId] = DateTime.now().add(_backoff(attempts));
  }

  /// Wakes the queue when the earliest creation pause ends.
  void _armCreationTimer() {
    _creationTimer?.cancel();
    _creationTimer = null;
    if (_stopped || _creationRetryAt.isEmpty) return;
    final earliest = _creationRetryAt.values.reduce((a, b) => a.isBefore(b) ? a : b);
    _creationTimer = Timer(earliest.difference(DateTime.now()), () {
      _creationTimer = null;
      unawaited(flush());
    });
  }

  /// Returns whether the pass may continue past [entry].
  ///
  /// A message with a file is reported as a transfer for the whole send, not
  /// just its upload: once the bytes are on the server the message itself
  /// still has to be accepted, and dropping the ring in between would show a
  /// bubble that looks idle while it is still going.
  Future<bool> _send(OutboxEntry snapshot) async {
    if (snapshot.attachment == null) return _sendEntry(snapshot);
    _transfers.begin(snapshot.clientMessageId, TransferDirection.upload, chatId: snapshot.chatId);
    // The bytes are already there (a restart after the upload): only the
    // message is left, so the ring starts full.
    if (snapshot.fileId != null) _transfers.report(snapshot.clientMessageId, 1);
    try {
      return await _sendEntry(snapshot);
    } finally {
      _transfers.end(snapshot.clientMessageId);
    }
  }

  Future<bool> _sendEntry(OutboxEntry snapshot) async {
    var entry = snapshot;

    // An attachment has to be on the server before the message can name it.
    // Three steps where only the last is idempotent, so this one is guarded by
    // the record itself: `fileId` is written only after the bytes are
    // confirmed, and a restart therefore skips straight past it.
    final attachment = entry.attachment;
    if (attachment != null && entry.fileId == null) {
      final uploaded = await _uploadFor(entry, attachment);
      if (uploaded == null) return false; // retryable; the pass waits with it
      if (uploaded.isEmpty) return true; // terminal for this message; go on

      await _outbox.attachFile(clientMessageId: entry.clientMessageId, fileId: uploaded);
      entry = entry.copyWith(fileId: uploaded);

      // Re-read AFTER the transfer. Feature 027 checks right before sending so
      // a discarded message cannot go out; an upload stretches that window from
      // milliseconds to minutes, which is long enough for someone to change
      // their mind. The bytes stay on the server as an orphan and are swept
      // there — what matters is that no message names them.
      final still = await _outbox.find(clientMessageId: entry.clientMessageId);
      if (still == null || still.status != OutboxStatus.pending) return true;
    }

    final result = await _messages.sendMessage(
      chatId: entry.chatId,
      clientMessageId: entry.clientMessageId,
      text: entry.text,
      // The id the server knows this file by. Before the upload it held the
      // composer's local draft id, which means nothing to anyone else.
      attachment: entry.fileId == null ? attachment : attachment?.copyWith(id: entry.fileId!),
    );

    if (result.hasData) {
      // Removal comes AFTER the repository persisted the message, never before:
      // the reverse order leaves a window in which the message exists nowhere.
      //
      // A discard that landed while this send was in flight has already deleted
      // the record, and this remove is a no-op. The message still shows as sent,
      // which is correct: discarding means "do not send it", and once the server
      // has it, a journal with no deletion cannot take it back.
      await _outbox.remove(clientMessageId: entry.clientMessageId);
      return true;
    }

    final exception = result.exception;
    // A dead channel is not an answer: the server never saw this send, so it
    // must not count towards giving up on the message.
    final serverAnswered = exception != RepositoryException.connection;
    // Exhausting the refusals turns a retryable one into a set-aside entry: the
    // message is kept, but it stops holding the line.
    final exhausted = serverAnswered && entry.refusals + 1 >= _autoRetryLimit;
    final terminal = _isTerminal(exception) || exhausted;
    await _outbox.recordFailure(
      clientMessageId: entry.clientMessageId,
      code: exception is RepositoryException ? exception.name : 'unknown',
      terminal: terminal,
      serverAnswered: serverAnswered,
    );
    // Log the key and the code, never the text, the label or the chat name.
    logRepository.debug(target: this, message: 'outbox: send failed id=${entry.clientMessageId} terminal=$terminal');

    if (terminal) return true; // one bad message must not hold the rest hostage
    _scheduleRetry(entry.clientMessageId, entry.attempts + 1);
    return false;
  }

  /// Uploads the entry's file. Returns the server id on success, an empty
  /// string when this message is beyond saving, and null when the pass should
  /// simply wait and try again.
  Future<String?> _uploadFor(OutboxEntry entry, MessageAttachment attachment) async {
    final path = attachment.localPath;
    if (path == null) {
      // Nothing to send: an attachment with no bytes on this device cannot be
      // uploaded, and never will be.
      await _outbox.recordFailure(clientMessageId: entry.clientMessageId, code: 'invalid_request', terminal: true, serverAnswered: false);
      return '';
    }

    final result = await _files.upload(
      path: path,
      mime: attachment.mime ?? MimeTypes.forFileName(attachment.name),
      onProgress: (fraction) => _transfers.report(entry.clientMessageId, fraction),
    );
    if (result.hasData) return result.data;

    final exception = result.exception;
    final terminal = _isTerminal(exception);
    await _outbox.recordFailure(
      clientMessageId: entry.clientMessageId,
      code: exception is RepositoryException ? exception.name : 'unknown',
      terminal: terminal,
      // A dead channel is not an answer, but `internal` and `rate_limited` from
      // `file.uploadBegin` ARE: the server looked at this file and said no. If
      // none of them counted, an endpoint that refuses every upload would hold
      // the one global queue — every chat, every later message — for good,
      // which is the exact edge case the refusal cap exists to prevent.
      serverAnswered: exception != RepositoryException.connection,
    );
    if (terminal) return '';
    _scheduleRetry(entry.clientMessageId, entry.attempts + 1);
    return null;
  }

  /// Whether retrying is pointless. A message the server called malformed or
  /// too large will be just as malformed on the tenth attempt, and retrying it
  /// forever would block everything queued behind it.
  bool _isTerminal(BaseRepositoryException? exception) {
    return switch (exception) {
      RepositoryException.connection => false,
      RepositoryException.rateLimited => false,
      RepositoryException.internal => false,
      RepositoryException.unknown => false,
      // An unrecognised failure type is treated as retryable for the same
      // reason the contract treats an unknown code as `internal`: guessing
      // "give up" would silently drop a message.
      null => false,
      _ => true,
    };
  }

  /// `min(30s, 1s * 2^(attempts - 1))` with ±20% jitter - for a message and
  /// for a chat creation alike.
  Duration _backoff(int attempts) {
    final exponent = (attempts - 1).clamp(0, 16);
    final raw = _minBackoff * pow(2, exponent).toDouble();
    final capped = raw > _maxBackoff ? _maxBackoff : raw;
    // Jitter keeps a herd of clients from hitting a recovering server in step.
    return capped * (0.8 + _random.nextDouble() * 0.4);
  }

  /// Pauses the queue on [clientMessageId]. The count comes from the RECORD,
  /// not from this pass: a process restart resets everything in memory, which
  /// is exactly the moment the pause has to be remembered.
  void _scheduleRetry(String clientMessageId, int attempts) {
    if (_stopped) return;
    _retryTimer?.cancel();
    _pausedFor = clientMessageId;
    _retryTimer = Timer(_backoff(attempts), () {
      _retryTimer = null;
      _pausedFor = null;
      unawaited(flush());
    });
  }
}
