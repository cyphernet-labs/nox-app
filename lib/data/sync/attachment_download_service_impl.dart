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
  AttachmentDownloadServiceImpl(this._files, this._messages, this._phase)
    : _ladder = RetryLadder(),
      _pauseFor = null,
      _resetWait = defaultResetWait;

  /// [pause] stands in for the ladder's pause, so a test does not sit out
  /// thirty seconds per attempt; [resetWait] for the bound on a reset.
  @visibleForTesting
  AttachmentDownloadServiceImpl.forTest(
    this._files,
    this._messages,
    this._phase, {
    required Duration Function(int attempts) pause,
    this._resetWait = defaultResetWait,
  }) : _ladder = RetryLadder(),
       _pauseFor = pause;

  /// How long a reset waits for the downloads it stopped to finish. Bounded,
  /// because a logout waits on it: a download caught between two steps ends
  /// at its next one, and the repository makes sure that whatever it does
  /// after the reset, it writes nothing.
  static const Duration defaultResetWait = Duration(seconds: 5);

  final FileRepository _files;
  final MessageRepository _messages;
  final SessionPhaseService _phase;
  final RetryLadder _ladder;
  final Duration Function(int attempts)? _pauseFor;
  final Duration _resetWait;

  /// Downloads under way, by file id: one per file, joined by everyone who
  /// asks for it while it runs.
  final Map<String, _Download> _downloads = <String, _Download>{};

  /// Pauses being waited out, so a reset can end them at once.
  final Set<Completer<void>> _pauses = <Completer<void>>{};

  /// Raised by every [reset]: a download begun before it stops at its next
  /// step instead of writing into what the reset is wiping.
  int _generation = 0;

  /// Set while a [reset] runs: a download asked for then belongs to the world
  /// being wiped, and starting it would write into that wipe.
  bool _resetting = false;

  @override
  Future<RepositoryResult<String>> fetch({String? messageId, required MessageAttachment attachment, TransferFraction? onProgress}) {
    if (_resetting) {
      return Future<RepositoryResult<String>>.value(RepositoryResult<String>.error(exception: RepositoryException.connection));
    }
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
          try {
            await _messages.attachLocalFile(messageId: messageId, localPath: path);
          } catch (error, stackTrace) {
            // The bytes are here all the same, and the next look finds them by
            // file id. A throw would end this download as a failure - and a
            // reset waiting on it with it.
            logRepository.error(target: this, error: error, stackTrace: stackTrace);
          }
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
  void stopListening(TransferFraction onProgress) {
    for (final download in _downloads.values) {
      download.leave(onProgress);
    }
  }

  @override
  Future<void> reset() async {
    _resetting = true;
    try {
      _generation++;
      for (final pause in List<Completer<void>>.of(_pauses)) {
        if (!pause.isCompleted) pause.complete();
      }
      await _files.cancelTransfers();
      final running = [for (final download in _downloads.values) download.result];
      await Future.wait(running).timeout(
        _resetWait,
        onTimeout: () {
          logRepository.debug(target: this, message: 'download: a stopped download did not end within the reset wait');
          return const <RepositoryResult<String>>[];
        },
      );
    } finally {
      _downloads.clear();
      _resetting = false;
    }
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

  void leave(TransferFraction listener) => _listeners.remove(listener);

  void report(double fraction) {
    _last = fraction;
    for (final listener in List<TransferFraction>.of(_listeners)) {
      listener(fraction);
    }
  }
}
