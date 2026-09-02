import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';

/// Chat thread repository (5.2) — cache-first over the local Sembast store (013),
/// seeded once per chat from the remote data source. History is CURSOR-paginated by
/// the server journal number (`before_seq`, contract §5, feature 025); send is
/// one-shot (optimistic on the caller side). The impl stays mock-backed until the
/// 016 DI flip swaps in the real transport.
abstract class MessageRepository {
  Future<RepositoryResult<(List<MessageModel>, PageMetadata)>> getMessages({required GetMessagesConfig config});

  /// Reactive stream of a chat's messages (chronological) — a change-signal for the
  /// live thread (Feature 014). Seeds the chat once if empty, then streams the cache.
  Stream<List<MessageModel>> watchMessages(String chatId);

  /// One-shot send. Returns the accepted (server) message on success.
  ///
  /// [clientMessageId] is the idempotency key and belongs to the CALLER: a
  /// retry of the same message must carry the same key, which is what lets the
  /// server recognise a resend after a lost reply instead of storing it twice
  /// (contract §5). Minting it here would defeat that — every retry would look
  /// like a new message.
  Future<RepositoryResult<MessageModel>> sendMessage({
    required String chatId,
    required String clientMessageId,
    String? text,
    MessageAttachment? attachment,
  });

  /// Seeds a freshly-created chat with its opening system line ("Chat created by
  /// {label}", authored by the signed-in label). Persisting it makes the new thread
  /// non-empty, so the generic mock history is NOT seeded on first open (D5).
  Future<void> seedCreatedChat({required String chatId});

  /// The chat's shared files (5.4) — every attachment across its persisted messages,
  /// newest-first. Derived from the local message cache, not a remote fetch (feature 017).
  /// The chat's shared files, newest-first.
  ///
  /// [refresh] pulls the newest window from the source first, which is what an
  /// OPEN wants. The live re-derive must leave it false: fetching there would
  /// persist, wake the change-signal, and fetch again — a loop that never
  /// settles.
  Future<List<MessageAttachment>> chatFiles({required String chatId, bool refresh = false});

  /// Records where an attachment's bytes now live on this device (feature 028).
  ///
  /// The same `localPath` a picked file has always used, reached a second way:
  /// before, it meant "the file the user chose"; now also "the file we fetched".
  /// Keeping one answer to "where are the bytes" is what lets the thumbnail and
  /// Save keep working with no change at all.
  Future<void> attachLocalFile({required String messageId, required String localPath});

  /// DEBUG ONLY (`kDebugMode`, Feature 014): persist an inbound message (author != me)
  /// into a chat and bump its unread — the deterministic stand-in for a server push.
  /// Callers MUST guard with `kDebugMode`.
  Future<void> simulateIncoming({required String chatId});

  /// Resets any cached state (called on logout).
  Future<void> clean();
}
