import 'package:nox_app/domain/model/chat/chat_creation.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/pending_chat_creation.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';

/// Chats repository (5.1) — cache-first over the local Sembast store (013). The
/// first page is read from the cache and the server's page lands there in the
/// background (040); later pages go to the server. Returns a page slice paired
/// with contract-shaped metadata (`hasMore`, feature 025). Since phase 041 a
/// chat is created on this device first and on the server when there is a
/// channel - the outbox drain does the second half.
abstract class ChatRepository {
  Future<RepositoryResult<(List<ChatModel>, PageMetadata)>> getChats({required GetChatsConfig config});

  /// Reactive stream of the cached chats (newest first) for live-updating views.
  Stream<List<ChatModel>> watchChats();

  /// Reactive stream of ONE chat by id (live name/avatar after a rename); emits null when
  /// the chat is absent. Consumed by the chat card + thread header so a rename reflects
  /// everywhere without manual propagation.
  Stream<ChatModel?> watchChat({required String chatId});

  /// Creates a chat on this device, at once, whatever the connection is doing
  /// (phase 041): an id minted here, the row marked [ChatCreation.pending] and
  /// the opening "Chat created by" line. The server learns of it from the
  /// outbox drain ([createOnServer]); nothing here waits for it.
  Future<RepositoryResult<ChatModel>> createChat({required String name});

  /// Renames a chat and returns it. A chat the server has goes through the
  /// server, which owns name uniqueness. A chat it does not have yet is renamed
  /// here only and waits to be created again under the new name - which is how
  /// a taken name is fixed (phase 041). Errors when the chat is absent.
  Future<RepositoryResult<ChatModel>> updateChatName({required String chatId, required String name});

  /// Chats waiting to be created on the server, the oldest first (phase 041).
  Future<List<PendingChatCreation>> pendingCreations();

  /// Asks the server to create [chat] under its own id and returns the chat as
  /// the server has it. When the id is the same, the stored row becomes the
  /// server's, without a creation state; a DIFFERENT id is a server older than
  /// phase 041, and the caller adopts it ([adoptServerChat]).
  Future<RepositoryResult<ChatModel>> createOnServer({required ChatModel chat});

  /// Records how creating [chatId] on the server went.
  Future<void> markCreation({required String chatId, required ChatCreation creation, required int attempts});

  /// Puts a chat the server refused back in line, the person having asked.
  Future<void> retryCreation({required String chatId});

  /// The server made [localId] under an id of its own: its chat is kept and
  /// the local copy goes, with its opening line (phase 041, old server).
  Future<void> adoptServerChat({required String localId, required ChatModel serverChat});

  /// Whether the server has [chatId]. A chat this device does not know counts
  /// as on the server: only a chat waiting to be created is known not to be.
  Future<bool> isOnServer({required String chatId});

  /// Whether a chat name is already taken, checked case-INSENSITIVELY against the
  /// ACCUMULATING local DB (seeded + user-created chats) — not a frozen mock set (D4).
  /// [excludeChatId] omits one chat from the check (rename: a chat never collides with
  /// its own current name).
  Future<RepositoryResult<bool>> isChatNameTaken({required String name, String? excludeChatId});

  /// All files shared in a chat (5.4) — chat-owned, not paginated.
  Future<RepositoryResult<List<MessageAttachment>>> getChatFiles({required String chatId, bool refresh = false});

  /// Records that the chat has been seen up to what is cached for it. The
  /// badge is a recount from this mark, never a stored total: the protocol
  /// permits the same event twice at the replay/live boundary, and counting a
  /// set is idempotent where incrementing is not (contract §6/§8.3).
  Future<void> markChatRead({required String chatId});

  /// Drops every read mark. Called before the sync cursor is cleared, because
  /// a mark that outlived the cursor would sit above a rebuilt seq space and
  /// suppress every badge with nothing to ever repair it.
  Future<void> clearReadMarks();

  /// Resets any cached state (called on logout).
  Future<void> clean();
}
