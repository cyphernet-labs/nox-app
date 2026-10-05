import 'dart:async';
import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/file/attachment_transfer.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/domain/service/attachment_download_service.dart';
import 'package:nox_app/domain/service/attachment_transfer_service.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';

/// Fetches the bytes of received IMAGES so they render in the thread.
///
/// Why images and nothing else: the design corpus says an image with a real
/// local file draws a thumbnail and every other type draws a type chip. Without
/// this, a received picture would stay a chip forever and the shipped screen
/// would quietly stop matching its own spec. Other types can be large and may
/// never be opened, so they wait for a tap.
///
/// `AppImageAttachmentWidget` asks one question — is this an image with a
/// local path — and the `watchMessages` tick redraws the thread once the path
/// is written. While the bytes are coming, the transfer it reports turns the
/// placeholder's spinner into a ring that fills.
///
/// The thread calls it on every load and refresh and whenever the channel
/// comes back, so a picture that arrives while the thread is open is fetched
/// at once. A broken link does not end a fetch: the download service keeps at
/// it and goes on from the bytes already here (phase 043), and it records the
/// path itself.
@LazySingleton(env: [Environment.dev, Environment.prod, Environment.test])
class AttachmentPrefetchService {
  AttachmentPrefetchService(this._downloads, this._phase, this._transfers);

  final AttachmentDownloadService _downloads;
  final SessionPhaseService _phase;
  final AttachmentTransferService _transfers;

  /// Pictures waiting their turn, oldest first. ONE worker takes them one at
  /// a time. The thread asks on every load, refresh and reconnect, and a walker
  /// per call grew to nine downloads at once: through Tor they split the
  /// bandwidth, and the first picture arrived last.
  final List<MessageModel> _queue = <MessageModel>[];

  /// Ids queued or being fetched: a picture is asked for once at a time.
  ///
  /// Load-bearing rather than defensive: writing the path wakes the very
  /// `watchMessages` stream that led here, so without it a prefetch would call
  /// itself forever.
  final Set<String> _wanted = <String>{};

  /// Files the server will never hand over. Only a terminal refusal lands here
  /// — a network failure has to stay retryable, or one bad moment would cost
  /// every picture in the thread until the app restarts.
  final Set<String> _hopeless = <String>{};

  /// Pictures the download service gave up on after the server kept refusing
  /// them. They wait for the channel to come back - or for a tap, which opens
  /// the file view and asks afresh - and not for the next refresh: every new
  /// message refreshes the thread, and each would start another whole ladder
  /// of refusals for a picture the automation has already given up on.
  final Set<String> _exhausted = <String>{};

  Future<void>? _worker;

  /// Queues anything in [messages] that needs fetching. Safe to call on every
  /// tick. [retryNow] gives the pictures the automation gave up on another go:
  /// the channel has just come back, which is the moment that deserves one.
  ///
  /// The future completes when the queue has run dry.
  Future<void> prefetch(List<MessageModel> messages, {bool retryNow = false}) {
    // The second downloader, and the one easiest to forget: it goes out over
    // Dio on its own schedule, without passing through the socket at all. A
    // machine that failed to prove who it is must not be asked for bytes -
    // and a refusal here would only be logged, so nothing would ever say why
    // the pictures stopped arriving.
    if (_phase.phase.isServerMismatch) return Future<void>.value();
    if (retryNow) _exhausted.clear();
    for (final message in messages) {
      final attachment = message.attachment;
      if (attachment == null) continue;
      if (attachment.type != FileType.image) continue;
      // Existence, not just a non-null string — a stored path can outlive the
      // file it named (an iOS container rename, a cleared cache).
      final stored = attachment.localPath;
      if (stored != null && File(stored).existsSync()) continue;
      if (_hopeless.contains(message.id)) continue; // it is not coming
      if (_exhausted.contains(message.id)) continue; // waits for the channel
      if (!_wanted.add(message.id)) continue; // already queued or on its way
      _queue.add(message);
    }
    return _worker ??= _work().whenComplete(() {
      _worker = null;
      // Queued while the last fetch was finishing: nobody would take it.
      if (_queue.isNotEmpty) unawaited(prefetch(const <MessageModel>[]));
    });
  }

  Future<void> _work() async {
    while (_queue.isNotEmpty) {
      final message = _queue.removeAt(0);
      try {
        await _fetch(message);
      } finally {
        _wanted.remove(message.id);
      }
    }
  }

  Future<void> _fetch(MessageModel message) async {
    final attachment = message.attachment!;
    _transfers.begin(message.id, TransferDirection.download, chatId: message.chatId);
    try {
      final result = await _downloads.fetch(
        messageId: message.id,
        attachment: attachment,
        onProgress: (fraction) => _transfers.report(message.id, fraction),
      );
      if (result.hasData) return;
      // A refusal the bytes will never survive is worth remembering for good;
      // a server that kept refusing waits for the channel to come back.
      if (result.exception == RepositoryException.attachmentGone || result.exception == RepositoryException.notFound) {
        _hopeless.add(message.id);
      } else {
        _exhausted.add(message.id);
      }
    } catch (error, stackTrace) {
      // A picture nobody asked for is not worth surfacing: the placeholder
      // stays, and a tap still offers the real thing.
      _exhausted.add(message.id);
      logRepository.error(target: this, error: error, stackTrace: stackTrace);
    } finally {
      _transfers.end(message.id);
    }
  }

  /// Forgets what was tried (logout, or a change of server). The next identity
  /// starts with no memory of this one's files.
  void reset() {
    _queue.clear();
    _wanted.clear();
    _hopeless.clear();
    _exhausted.clear();
  }
}
