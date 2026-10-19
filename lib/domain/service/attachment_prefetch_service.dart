import 'package:nox_app/domain/model/chat/message_model.dart';

/// Fetches the bytes of received IMAGES so they render in the thread: an image
/// with a local file draws a thumbnail, every other type waits for a tap.
abstract class AttachmentPrefetchService {
  /// Queues anything in [messages] that needs fetching. Safe to call on every
  /// tick. [retryNow] gives the pictures the automation gave up on another go:
  /// the channel has just come back. Completes when the queue has run dry.
  Future<void> prefetch(List<MessageModel> messages, {bool retryNow = false});

  /// Forgets what was tried - a logout, or a change of server.
  void reset();
}
