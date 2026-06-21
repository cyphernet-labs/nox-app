import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';

/// Chat thread repository (5.2) — the blueprint's second **network-only** feature
/// after the chats list. A paginated history (older messages paged in as the user
/// scrolls up) plus a one-shot send (optimistic on the caller side). UI-phase impl
/// is mock-backed (no real transport/cache).
abstract class MessageRepository {
  Future<RepositoryResult<(List<MessageModel>, PageMetadata)>> getMessages({required GetMessagesConfig config});

  /// One-shot send. Returns the accepted (server) message on success.
  Future<RepositoryResult<MessageModel>> sendMessage({required String chatId, String? text, MessageAttachment? attachment});

  /// Resets any cached state (called on logout).
  Future<void> clean();
}
