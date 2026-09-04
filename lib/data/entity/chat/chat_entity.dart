// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_entity.freezed.dart';
part 'chat_entity.g.dart';

/// DTO for a chat (5.1) — @freezed + json_serializable, BASIC TYPES ONLY
/// (DateTime encoded as ISO-8601 String, sortable lexicographically). All coercion
/// lives in [ChatMapper].
@freezed
abstract class ChatEntity with _$ChatEntity {
  const factory ChatEntity({
    required String id,
    required String name,
    required String lastMessagePreview,
    required String lastMessageAt, // DateTime encoded as ISO-8601 String
    required int unreadCount,

    /// The highest message seq that was on screen when this chat was last
    /// opened; null means it was never opened, which the product spec says
    /// must show no badge at all.
    ///
    /// `required` while nullable, deliberately. The stored counter this
    /// replaces was kept alive by the compiler - `required int unreadCount`
    /// would not let a new construction site forget it. A bare `int?` accepts
    /// the omission silently, and the first site that forgot would get null,
    /// meaning "never opened", meaning no badge where a badge belongs. No test
    /// that is not looking for it would catch that.
    required int? lastOpenedSeq,
    // Wire creation metadata (contract §4). Optional: pre-025 records decode
    // with null (the attachmentLocalPath back-compat pattern).
    int? createdAt, // unix seconds
    String? createdByLabel,
  }) = _ChatEntity;

  factory ChatEntity.fromJson(Map<String, dynamic> json) => _$ChatEntityFromJson(json);
}
