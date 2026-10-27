import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/outbox_entry.dart';
import 'package:nox_app/domain/model/file/unfinished_upload.dart';
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
  ///
  /// The attachment's file is copied into the app's own storage and the entry
  /// names the copy (phase 043): the file the person picked may not be
  /// readable, or the same, by the time its bytes go - after a restart above
  /// all. When no copy can be made, the entry names the picked file.
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
  /// raises `refusals` only when [serverAnswered]; moves the entry to `error`
  /// only when [terminal].
  ///
  /// Two counters because there are two questions. `attempts` decides how long
  /// to wait before trying again, and every failure delays that equally. Only
  /// `refusals` may decide to give up, because giving up on a message the
  /// server never even saw would punish it for the network.
  Future<void> recordFailure({required String clientMessageId, required String code, required bool terminal, required bool serverAnswered});

  /// Remembers that this send's attachment is on the server.
  ///
  /// Called only after the bytes are confirmed, which is what makes a restart
  /// skip the upload instead of repeating it. Passing null forgets it again —
  /// the server sweeps uploads never bound to a message after a day, and a
  /// remembered id can outlive its file.
  Future<void> attachFile({required String clientMessageId, required String? fileId});

  /// Remembers - or, with null, forgets - the upload of this send's attachment
  /// that the server holds part of (phase 043).
  ///
  /// Written as soon as the server names the upload, before the first byte, so
  /// a restart goes on from what the server has. [attachFile] forgets it: once
  /// the bytes are confirmed there is nothing left to continue.
  Future<void> noteUpload({required String clientMessageId, required UnfinishedUpload? upload});

  /// Puts a failed entry back in line (manual retry) and resets BOTH counters.
  ///
  /// A tap is the user saying "try again now", so the ladder starts over: the
  /// pause goes back to its shortest, and the automatic retries are replenished.
  /// Keeping the history would make every later tap a single shot that fails
  /// straight back to `error`.
  Future<void> markPending({required String clientMessageId});

  /// Moves this send's own copy of its file to [at] - where the bytes of the
  /// uploaded file live on this device - and names it there (phase 043). True
  /// once the bytes are at [at]; false when the entry has no copy of its own,
  /// and then it names what it named before.
  Future<bool> keepCopy({required String clientMessageId, required String at});

  /// Drops one entry — the server accepted it, or the user discarded it — and
  /// its copy of the attachment's file with it.
  Future<void> remove({required String clientMessageId});

  /// Drops one chat's queue (the debug-scenario reset).
  Future<void> removeForChat({required String chatId});

  /// Moves one chat's queue to another chat id, order and keys kept (phase
  /// 041: a server older than the phase gave a new chat an id of its own).
  Future<void> moveChat({required String from, required String to});

  /// Empties the queue (logout). The rows hold message texts, and the copies
  /// the files being sent.
  Future<void> clean();
}
