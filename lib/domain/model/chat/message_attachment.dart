import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/model/file/file_type.dart';

part 'message_attachment.freezed.dart';

/// A file attached to a message / shared in a chat (5.2 / 5.3 / 5.4). No content
/// preview — only the type glyph, name and size are shown. `sizeBytes` is formatted
/// for display by `FileSizeFormatter`. @freezed, no JSON (mock data in the UI phase).
@freezed
abstract class MessageAttachment with _$MessageAttachment {
  const factory MessageAttachment({required String id, required FileType type, required String name, required int sizeBytes}) =
      _MessageAttachment;
}
