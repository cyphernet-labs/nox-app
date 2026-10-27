import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_status.dart';

part 'message_model.freezed.dart';

/// Sentinel [MessageModel.seq] of an optimistic (not yet acknowledged) send:
/// larger than any real journal number, so seq ordering keeps pending rows at
/// the newest end of the thread until the server echo assigns the real seq.
const int kPendingSeq = 0x7ffffffffffff;

/// A message in a chat thread (5.2). Belonging ("own vs other") and group-by-author
/// use the stable [authorId] (own = `authorId ==` the signed-in identity resolved from
/// the session, see `resolveIdentity`), never the display [authorLabel] (re-fetched at
/// render). [status] is meaningful
/// only for own messages; others are always [MessageStatus.none]. The opening
/// "Chat created by …" line is a message with [isSystem] = true (not a real message).
/// @freezed, no JSON (mock data in the UI phase).
@freezed
abstract class MessageModel with _$MessageModel {
  const factory MessageModel({
    required String id,

    /// Global journal number (contract v0 seq) - THE ordering and pagination
    /// key. Sparse inside a chat; [kPendingSeq] marks optimistic sends.
    @Default(kPendingSeq) int seq,
    required String chatId,
    required String authorId,
    required String authorLabel,
    String? text,
    MessageAttachment? attachment,
    required DateTime sentAt,
    @Default(MessageStatus.none) MessageStatus status,
    @Default(false) bool isSystem,
  }) = _MessageModel;
}
