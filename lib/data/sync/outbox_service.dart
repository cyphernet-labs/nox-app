import 'dart:async';
import 'dart:math';

import 'package:injectable/injectable.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/exception/base_repository_exception.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/chat/outbox_entry.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';

/// Drains the outgoing queue — and is the ONLY thing that sends.
///
/// Single sender is the load-bearing rule. Before this feature two places sent
/// (typing in the thread, and the reconnect re-delivery), and a connectivity
/// flap could run both over the same message. A duplicate in an open space with
/// no deletion cannot be taken back, so the whole design collapses into one
/// serialised drain.
@LazySingleton(env: [Environment.dev, Environment.prod, Environment.test])
class OutboxService {
  OutboxService(this._outbox, this._messages, this._phaseService);

  final OutboxRepository _outbox;
  final MessageRepository _messages;
  final SessionPhaseService _phaseService;

  static const Duration _minBackoff = Duration(seconds: 1);
  static const Duration _maxBackoff = Duration(seconds: 30);

  StreamSubscription<SessionPhase>? _phaseSubscription;
  Timer? _retryTimer;

  /// Serialises drains. A phase flap plus a fresh send would otherwise run two
  /// passes over the same records and post the head of the queue twice.
  Future<void> _queue = Future<void>.value();

  final Random _random = Random();

  /// Subscribes to the session phase. Idempotent — main() calls it once, but a
  /// second call must not open a second subscription.
  void start() {
    _phaseSubscription ??= _phaseService.watchPhase().listen((phase) {
      if (!phase.isCurrent) return;
      // A fresh live channel is a new reason to try: whatever the pause was
      // waiting out, the condition that caused it has just changed.
      _retryTimer?.cancel();
      _retryTimer = null;
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
    await _phaseSubscription?.cancel();
    _phaseSubscription = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    // Let a pass that is already running finish before the caller wipes.
    await _queue;
  }

  Future<void> _drain() async {
    // Sending with no live channel only burns an attempt and grows the backoff
    // for a reason that has nothing to do with the message.
    if (!_phaseService.phase.isCurrent) return;

    final queued = await _outbox.pending();
    for (final entry in queued) {
      final sent = await _send(entry);
      // A retryable refusal stops the pass: everything behind this entry has to
      // wait, or the queue would arrive out of order.
      if (!sent) return;
    }
  }

  /// Returns whether the pass may continue past [entry].
  Future<bool> _send(OutboxEntry entry) async {
    final result = await _messages.sendMessage(
      chatId: entry.chatId,
      clientMessageId: entry.clientMessageId,
      text: entry.text,
      attachment: entry.attachment,
    );

    if (result.hasData) {
      // Removal comes AFTER the repository persisted the message, never before:
      // the reverse order leaves a window in which the message exists nowhere.
      //
      // A discard that landed while this send was in flight has already deleted
      // the record, and this remove is a no-op. The message still shows as sent,
      // which is correct: discarding means "do not send it", and once the server
      // has it, an open space with no deletion cannot take it back.
      await _outbox.remove(clientMessageId: entry.clientMessageId);
      return true;
    }

    final exception = result.exception;
    final terminal = _isTerminal(exception);
    await _outbox.recordFailure(
      clientMessageId: entry.clientMessageId,
      code: exception is RepositoryException ? exception.name : 'unknown',
      terminal: terminal,
    );
    // Log the key and the code, never the text, the label or the chat name.
    logRepository.debug(target: this, message: 'outbox: send failed id=${entry.clientMessageId} terminal=$terminal');

    if (terminal) return true; // one bad message must not hold the rest hostage
    _scheduleRetry(entry.attempts + 1);
    return false;
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

  /// `min(30s, 1s * 2^(attempts - 1))` with ±20% jitter. The count comes from
  /// the RECORD, not from this pass: a process restart resets everything in
  /// memory, which is exactly the moment the pause has to be remembered.
  void _scheduleRetry(int attempts) {
    _retryTimer?.cancel();
    final exponent = (attempts - 1).clamp(0, 16);
    final raw = _minBackoff * pow(2, exponent).toDouble();
    final capped = raw > _maxBackoff ? _maxBackoff : raw;
    // Jitter keeps a herd of clients from hitting a recovering server in step.
    final jittered = capped * (0.8 + _random.nextDouble() * 0.4);
    _retryTimer = Timer(jittered, () {
      _retryTimer = null;
      unawaited(flush());
    });
  }
}
