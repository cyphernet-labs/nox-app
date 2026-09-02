import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/di/global_aliases.dart';
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

  /// Messages already handled, so a fetch runs once per file.
  ///
  /// This guard is load-bearing, not defensive: writing the path wakes the very
  /// `watchMessages` stream that led here, so an unguarded prefetch would call
  /// itself forever. Keyed by message id — a failed fetch is not retried until
  /// the app restarts, which is the quiet behaviour for something the user did
  /// not ask for.
  final Set<String> _handled = <String>{};

  /// Fetches anything in [messages] that needs it. Safe to call on every tick.
  Future<void> prefetch(List<MessageModel> messages) async {
    for (final message in messages) {
      final attachment = message.attachment;
      if (attachment == null) continue;
      if (attachment.type != FileType.image) continue;
      if (attachment.localPath != null) continue; // already here
      if (!_handled.add(message.id)) continue; // already tried

      try {
        final result = await _files.download(fileId: attachment.id, suggestedName: attachment.name);
        final path = result.data;
        if (path == null) continue;
        await _messages.attachLocalFile(messageId: message.id, localPath: path);
      } catch (error, stackTrace) {
        // A picture nobody asked for is not worth surfacing: the chip stays,
        // and a tap still offers the real thing.
        logRepository.error(target: this, error: error, stackTrace: stackTrace);
      }
    }
  }

  /// Forgets what was tried (logout, or a change of server).
  void reset() => _handled.clear();
}
