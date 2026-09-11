import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_model.freezed.dart';

/// Domain model for a chat row (5.1) — @freezed, no JSON (.freezed.dart only).
/// A chat carries no membership and no permissions: this machine holds ONE
/// person, so every chat on it is theirs and there is nobody to tell apart.
/// `unreadCount` is computed from this device's last open (0 → no badge).
@freezed
abstract class ChatModel with _$ChatModel {
  const factory ChatModel({
    required String id,
    required String name,
    required String lastMessagePreview,
    required DateTime lastMessageAt,
    @Default(0) int unreadCount,

    /// Chat creation time from the wire (contract created_at) - feeds the
    /// future client-rendered genesis line. Null for legacy local rows.
    DateTime? createdAt,

    /// Creator's label from the wire (contract created_by_label).
    String? createdByLabel,
  }) = _ChatModel;
}
