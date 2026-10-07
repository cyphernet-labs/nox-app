// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'upload_ticket_wire_entity.freezed.dart';
part 'upload_ticket_wire_entity.g.dart';

/// Wire DTO for the reply to `file.uploadBegin`, 1:1 with contract v0 §7:
/// `{file_id, upload_url, upload_token, max_attachment_bytes, received}`.
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

    /// How many leading bytes of the file the server holds safely (phase 043):
    /// 0 for a new upload, the whole size for one already there. A server
    /// older than the phase does not send it, and cannot continue an upload -
    /// the field's presence IS the feature flag (contract §2.1).
    @JsonKey(name: 'received') int? received,
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
