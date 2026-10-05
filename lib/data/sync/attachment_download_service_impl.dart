import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/sync/retry_ladder.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/exception/base_repository_exception.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/file/file_repository.dart';
import 'package:nox_app/domain/service/attachment_download_service.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';

/// The downloads of attachment bytes, kept at until they arrive (phase 043).
///
/// The repository makes one attempt, going on from whatever the last one left;
/// this decides when to make the next. The same ladder as the outgoing queue,
/// and the same rule about what may end it: a broken connection never does,
/// however many times it breaks - only the server refusing does.
@LazySingleton(as: AttachmentDownloadService, env: [Environment.dev, Environment.prod, Environment.test])
class AttachmentDownloadServiceImpl implements AttachmentDownloadService {
  AttachmentDownloadServiceImpl(this._files, this._messages, this._phase) : _ladder = RetryLadder(), _pauseFor = null;

  /// [pause] stands in for the ladder's pause, so a test does not sit out
  /// thirty seconds per attempt.
  @visibleForTesting
  AttachmentDownloadServiceImpl.forTest(this._files, this._messages, this._phase, {required Duration Function(int attempts) pause})
    : _ladder = RetryLadder(),
      _pauseFor = pause;

  final FileRepository _files;
  final MessageRepository _messages;
  final SessionPhaseService _phase;
  final RetryLadder _ladder;
  final Duration Function(int attempts)? _pauseFor;

  /// Downloads under way, by file id: one per file, joined by everyone who
  /// asks for it while it runs.
  final Map<String, _Download> _downloads = <String, _Download>{};

  /// Pauses being waited out, so a reset can end them at once.
  final Set<Completer<void>> _pauses = <Completer<void>>{};

  /// Raised by every [reset]: a download begun before it stops at its next
  /// step instead of writing into what the reset is wiping.
  int _generation = 0;

  @override
  Future<RepositoryResult<String>> fetch({String? messageId, required MessageAttachment attachment, TransferFraction? onProgress}) {
    final running = _downloads[attachment.id];
    if (running != null) {
      running.join(messageId, onProgress);
      return running.result;
    }
    final download = _Download()..join(messageId, onProgress);
    _downloads[attachment.id] = download;
    download.result = _run(attachment, download).whenComplete(() {
      if (identical(_downloads[attachment.id], download)) _downloads.remove(attachment.id);
    });
    return download.result;
  }

  Future<RepositoryResult<String>> _run(MessageAttachment attachment, _Download download) async {
    final generation = _generation;
    var attempts = 0;
    var refusals = 0;
    while (true) {
      final result = await _files.download(
        fileId: attachment.id,
        suggestedName: attachment.name,
        expectedSize: attachment.sizeBytes > 0 ? attachment.sizeBytes : null,
        onProgress: download.report,
      );
      if (generation != _generation) return RepositoryResult<String>.error(exception: RepositoryException.connection);

      final path = result.data;
      if (path != null) {
        // Recorded here, not by whoever asked: the file view may be long
        // closed, and the thumbnail and Save still have to find the bytes.
        for (final messageId in download.messageIds) {
          await _messages.attachLocalFile(messageId: messageId, localPath: path);
        }
        return result;
      }

      final exception = result.exception;
      if (_isTerminal(exception)) return result;
      attempts++;
      // A dead channel is not an answer, and never spends the ladder: a link
      // that breaks a hundred times is still a link worth trying again.
      if (exception != RepositoryException.connection) {
        refusals++;
        if (refusals >= RetryLadder.refusalLimit) {
          logRepository.debug(target: this, message: 'download: ${attachment.id} refused $refusals times, giving up');
          return result;
        }
      }
      await _pause(attempts);
      if (generation != _generation) return RepositoryResult<String>.error(exception: RepositoryException.connection);
    }
  }

  /// Whether no retry can change the answer.
  bool _isTerminal(BaseRepositoryException? exception) {
    return switch (exception) {
      RepositoryException.connection => false,
      RepositoryException.rateLimited => false,
      RepositoryException.internal => false,
      RepositoryException.unknown => false,
      // Unrecognised is retryable, as the contract treats an unknown code as
      // `internal`: guessing "give up" would lose a file over a new word.
      null => false,
      _ => true,
    };
  }

  /// Waits out the ladder's pause - or less, when the channel comes back: the
  /// condition that broke the last attempt has just changed.
  Future<void> _pause(int attempts) {
    final done = Completer<void>();
    _pauses.add(done);
    final timer = Timer(_pauseFor?.call(attempts) ?? _ladder.pause(attempts), () {
      if (!done.isCompleted) done.complete();
    });
    // Only a CHANGE to a current channel wakes it: the stream hands over the
    // phase as it stands on listen, and a channel that was current all along
    // is no reason to skip the pause.
    var wasCurrent = _phase.phase.isCurrent;
    final subscription = _phase.watchPhase().listen((SessionPhase phase) {
      if (phase.isCurrent && !wasCurrent && !done.isCompleted) done.complete();
      wasCurrent = phase.isCurrent;
    });
    return done.future.whenComplete(() {
      timer.cancel();
      unawaited(subscription.cancel());
      _pauses.remove(done);
    });
  }

  @override
  Future<void> reset() async {
    _generation++;
    for (final pause in List<Completer<void>>.of(_pauses)) {
      if (!pause.isCompleted) pause.complete();
    }
    await _files.cancelTransfers();
    final running = [for (final download in _downloads.values) download.result];
    await Future.wait(running);
    _downloads.clear();
  }
}

/// One download and everyone waiting on it.
class _Download {
  late Future<RepositoryResult<String>> result;
  final List<TransferFraction> _listeners = <TransferFraction>[];

  /// The messages this file belongs to. One, in practice - a file is named by
  /// one message - but a caller without one must not erase another's.
  final Set<String> messageIds = <String>{};

  /// Where it stands, for whoever joins late.
  double? _last;

  void join(String? messageId, TransferFraction? listener) {
    if (messageId != null) messageIds.add(messageId);
    if (listener == null) return;
    _listeners.add(listener);
    final last = _last;
    if (last != null) listener(last);
  }

  void report(double fraction) {
    _last = fraction;
    for (final listener in List<TransferFraction>.of(_listeners)) {
      listener(fraction);
    }
  }
}
