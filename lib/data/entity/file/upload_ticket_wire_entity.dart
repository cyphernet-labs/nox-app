// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'upload_ticket_wire_entity.freezed.dart';
part 'upload_ticket_wire_entity.g.dart';

/// Wire DTO for the reply to `file.uploadBegin`, 1:1 with contract v0 §7:
/// `{file_id, upload_url, upload_token, max_attachment_bytes}`.
///
/// `upload_url` and `upload_token` are the same string in the server's current
/// shape (the url IS `/files/<token>`), but both are carried because the
/// contract declares both — reading one and inventing the other would be this
/// client guessing at a wire it is supposed to take verbatim.
@freezed
abstract class UploadTicketWireEntity with _$UploadTicketWireEntity {
  const factory UploadTicketWireEntity({
    @JsonKey(name: 'file_id') required String fileId,
    @JsonKey(name: 'upload_url') required String uploadUrl,
    @JsonKey(name: 'upload_token') required String uploadToken,
    @JsonKey(name: 'max_attachment_bytes') required int maxAttachmentBytes,
  }) = _UploadTicketWireEntity;

  factory UploadTicketWireEntity.fromJson(Map<String, dynamic> json) => _$UploadTicketWireEntityFromJson(json);
}

/// Wire DTO for the reply to `file.downloadBegin`: `{download_url, download_token}`.
@freezed
abstract class DownloadTicketWireEntity with _$DownloadTicketWireEntity {
  const factory DownloadTicketWireEntity({
    @JsonKey(name: 'download_url') required String downloadUrl,
    @JsonKey(name: 'download_token') required String downloadToken,
  }) = _DownloadTicketWireEntity;

  factory DownloadTicketWireEntity.fromJson(Map<String, dynamic> json) => _$DownloadTicketWireEntityFromJson(json);
}
