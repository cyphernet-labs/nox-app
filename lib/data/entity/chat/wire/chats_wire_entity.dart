// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/data/entity/chat/wire/chat_wire_entity.dart';

part 'chats_wire_entity.freezed.dart';
part 'chats_wire_entity.g.dart';

/// Page wrapper for the chats list, 1:1 with contract v0 §4:
/// `{chats: [...], has_more}`. The paged path keeps 1-based page numbers in
/// the REQUEST; the reply carries no page math and no total.
@freezed
abstract class ChatsWireEntity with _$ChatsWireEntity {
  const factory ChatsWireEntity({
    @Default(<ChatWireEntity>[]) List<ChatWireEntity> chats,
    @JsonKey(name: 'has_more') required bool hasMore,
  }) = _ChatsWireEntity;

  factory ChatsWireEntity.fromJson(Map<String, dynamic> json) => _$ChatsWireEntityFromJson(json);
}
