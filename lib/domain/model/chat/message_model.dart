import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_status.dart';

part 'message_model.freezed.dart';

/// A message in a chat thread (5.2). Belonging ("own vs other") and group-by-author
/// use the stable [authorId] (own = `authorId == IdentityMockData.currentUserId`),
/// never the display [authorLabel] (re-fetched at render). [status] is meaningful
/// only for own messages; others are always [MessageStatus.none]. The opening
/// "Chat created by …" line is a message with [isSystem] = true (not a real message).
/// @freezed, no JSON (mock data in the UI phase).
@freezed
abstract class MessageModel with _$MessageModel {
  const factory MessageModel({
    required String id,
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
