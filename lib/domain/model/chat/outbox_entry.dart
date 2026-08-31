import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/outbox_status.dart';

part 'outbox_entry.freezed.dart';

/// One intent to send, held until the server accepts it (contract v0 §9.3/§9.8).
///
/// [clientMessageId] is the idempotency key AND the store's record key: minting
/// it at enqueue time and persisting it with the row is what lets a retry after
/// a lost reply — or after a full restart — be recognised as the same message
/// instead of stored twice. In a space with no deletion a duplicate cannot be
/// taken back, so the key is the whole point of this model.
@freezed
abstract class OutboxEntry with _$OutboxEntry {
  const factory OutboxEntry({
    required String clientMessageId,
    required String chatId,

    /// Position in the queue. Assigned at enqueue as `max + 1`, NOT derived
    /// from [createdAt]: goldens freeze the clock, so a burst of sends shares a
    /// timestamp to the millisecond and time alone cannot order them.
    required int ordinal,
    required DateTime createdAt,
    required OutboxStatus status,

    /// How many attempts have failed — by any cause, including a channel that
    /// died before the server said anything. Drives the backoff.
    @Default(0) int attempts,

    /// How many times the SERVER answered with a refusal. Drives the cap on
    /// automatic retries, and only this counter may: a broken connection is not
    /// the message's fault, and counting it would let a flapping link set aside
    /// a perfectly good message in seconds.
    @Default(0) int refusals,
    String? text,
    MessageAttachment? attachment,

    /// Contract §2.1 code of the last refusal. Diagnostic only — the thread
    /// renders the same error bubble regardless of the reason.
    String? lastErrorCode,
  }) = _OutboxEntry;
}
