import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';

/// Chats list repository (5.1) — the open chats list is the blueprint's first real
/// **network-only** server-owned paginated feature. Returns a page slice paired
/// with offset metadata. UI-phase impl is mock-backed (no real transport/cache).
abstract class ChatRepository {
  Future<RepositoryResult<(List<ChatModel>, PageMetadata)>> getChats({required GetChatsConfig config});

  /// All files shared in a chat (5.4) — chat-owned, not paginated.
  Future<RepositoryResult<List<MessageAttachment>>> getChatFiles({required String chatId});

  /// Resets any cached state (called on logout).
  Future<void> clean();
}
