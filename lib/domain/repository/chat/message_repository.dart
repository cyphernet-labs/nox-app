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

  /// Reactive stream of a chat's messages (chronological) — a change-signal for the
  /// live thread (Feature 014). Seeds the chat once if empty, then streams the cache.
  Stream<List<MessageModel>> watchMessages(String chatId);

  /// One-shot send. Returns the accepted (server) message on success.
  Future<RepositoryResult<MessageModel>> sendMessage({required String chatId, String? text, MessageAttachment? attachment});

  /// Seeds a freshly-created chat with its opening system line ("Chat created by
  /// {label}", authored by the signed-in label). Persisting it makes the new thread
  /// non-empty, so the generic mock history is NOT seeded on first open (D5).
  Future<void> seedCreatedChat({required String chatId});

  /// DEBUG ONLY (`kDebugMode`, Feature 014): persist an inbound message (author != me)
  /// into a chat and bump its unread — the deterministic stand-in for a server push.
  /// Callers MUST guard with `kDebugMode`.
  Future<void> simulateIncoming({required String chatId});

  /// Resets any cached state (called on logout).
  Future<void> clean();
}
