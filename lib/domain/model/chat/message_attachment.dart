import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/model/file/file_type.dart';

part 'message_attachment.freezed.dart';

/// A file attached to a message / shared in a chat (5.2 / 5.3 / 5.4). Non-image types
/// show the type glyph, name and size; an IMAGE with a real [localPath] renders an
/// inline thumbnail (feature F4). `sizeBytes` is formatted for display by
/// `FileSizeFormatter`. @freezed, no JSON (mock data in the UI phase).
@freezed
abstract class MessageAttachment with _$MessageAttachment {
  const factory MessageAttachment({
    required String id,
    required FileType type,
    required String name,
    required int sizeBytes,
    // Device-local file path of the picked/sent file (feature F4/F2). Drives the image
    // thumbnail + the real Save. Null for seeded / backend attachments (no local file →
    // type-icon chip / mock save). Persisted in Sembast; NOT carried on the S4 wire.
    String? localPath,
  }) = _MessageAttachment;
}
