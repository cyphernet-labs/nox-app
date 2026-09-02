import 'dart:async';
import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/file/file_repository.dart';

/// Fetches the bytes of received IMAGES so they render in the thread.
///
/// Why images and nothing else: the design corpus says an image with a real
/// local file draws a thumbnail and every other type draws a type chip. Without
/// this, a received picture would stay a chip forever and the shipped screen
/// would quietly stop matching its own spec. Other types can be large and may
/// never be opened, so they wait for a tap.
///
/// Nothing in the presentation layer changes as a result. `AppImageAttachmentWidget`
/// already asks one question — is this an image with a local path — and the
/// existing `watchMessages` tick redraws the thread once the path is written.
@LazySingleton(env: [Environment.dev, Environment.prod, Environment.test])
class AttachmentPrefetchService {
  AttachmentPrefetchService(this._files, this._messages);

  final FileRepository _files;
  final MessageRepository _messages;

  /// Fetches currently running, so the same file is not pulled twice at once.
  ///
  /// Load-bearing rather than defensive: writing the path wakes the very
  /// `watchMessages` stream that led here, so without it a prefetch would call
  /// itself forever.
  final Set<String> _inFlight = <String>{};

  /// Files the server will never hand over. Only a terminal refusal lands here
  /// — a network failure has to stay retryable, or one bad moment would cost
  /// every picture in the thread until the app restarts.
  final Set<String> _hopeless = <String>{};

  /// Fetches anything in [messages] that needs it. Safe to call on every tick.
  Future<void> prefetch(List<MessageModel> messages) async {
    for (final message in messages) {
      final attachment = message.attachment;
      if (attachment == null) continue;
      if (attachment.type != FileType.image) continue;
      // Existence, not just a non-null string — a stored path can outlive the
      // file it named (an iOS container rename, a cleared cache).
      final stored = attachment.localPath;
      if (stored != null && File(stored).existsSync()) continue;
      if (_hopeless.contains(message.id)) continue; // it is not coming
      if (!_inFlight.add(message.id)) continue; // one fetch at a time per file

      try {
        final result = await _files.download(fileId: attachment.id, suggestedName: attachment.name);
        final path = result.data;
        if (path == null) {
          // A refusal the bytes will never survive is worth remembering; a lost
          // connection is not. Marking a network failure permanent would mean
          // one bad moment costs every picture in the thread until the app is
          // restarted.
          if (result.exception == RepositoryException.attachmentGone || result.exception == RepositoryException.notFound) {
            _hopeless.add(message.id);
          }
          continue;
        }
        await _messages.attachLocalFile(messageId: message.id, localPath: path);
      } catch (error, stackTrace) {
        // A picture nobody asked for is not worth surfacing: the chip stays,
        // and a tap still offers the real thing.
        logRepository.error(target: this, error: error, stackTrace: stackTrace);
      } finally {
        _inFlight.remove(message.id);
      }
    }
  }

  /// Forgets what was tried (logout, or a change of server). The next identity
  /// starts with no memory of this one's files.
  void reset() {
    _inFlight.clear();
    _hopeless.clear();
  }
}
