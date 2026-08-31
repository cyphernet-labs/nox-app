import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/outbox_entry.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

/// The durable queue of outgoing sends (contract v0 §9.3/§9.8).
///
/// It exists because the queue used to live in the chat thread's bloc state:
/// leaving the screen or restarting the app destroyed both the unsent message
/// and its idempotency key. Here the key is minted at enqueue time and stored
/// with the row, which is what lets a retry — after a reconnect or after a full
/// restart — be recognised by the server as the same message rather than
/// written twice. In a space with no deletion a duplicate cannot be undone.
abstract class OutboxRepository {
  /// Puts a send in the queue and returns the stored entry.
  ///
  /// Minting `client_message_id` is deliberately the repository's job, not the
  /// caller's: a key minted on a screen dies with the screen, which is the very
  /// defect this feature removes.
  Future<RepositoryResult<OutboxEntry>> enqueue({required String chatId, String? text, MessageAttachment? attachment});

  /// The queue in send order — a snapshot on listen, then every change.
  /// Without [chatId] the whole queue; with it, one chat's slice.
  Stream<List<OutboxEntry>> watchQueue({String? chatId});

  /// Entries still awaiting a send, in queue order, across every chat — the
  /// drain's input.
  Future<List<OutboxEntry>> pending();

  /// One entry as it stands right now, or null if it is gone.
  ///
  /// The drain re-reads each entry immediately before sending it: a pass can
  /// span seconds, and a message the user discarded while it waited its turn
  /// must not go out. In a space with no deletion, sending something the user
  /// cancelled cannot be undone.
  Future<OutboxEntry?> find({required String clientMessageId});

  /// Records a failed attempt: always raises `attempts` and stores [code];
  /// moves the entry to `error` only when [terminal].
  ///
  /// One method rather than two because the backoff grows off `attempts`, so a
  /// retryable failure has to count exactly like a terminal one — otherwise the
  /// pause after the first refusal would stay one second forever.
  Future<void> recordFailure({required String clientMessageId, required String code, required bool terminal});

  /// Puts a failed entry back in line (manual retry). Deliberately does NOT
  /// reset `attempts`: the history of failures is what the pause is based on.
  Future<void> markPending({required String clientMessageId});

  /// Drops one entry — the server accepted it, or the user discarded it.
  Future<void> remove({required String clientMessageId});

  /// Drops one chat's queue (the debug-scenario reset).
  Future<void> removeForChat({required String chatId});

  /// Empties the queue (logout). The rows hold message texts.
  Future<void> clean();
}
