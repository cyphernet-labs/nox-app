import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/base/error_wire_entity.dart';
import 'package:nox_app/data/exception/file_transfer_exception.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/file/upload_ticket_wire_entity.dart';
import 'package:nox_app/data/remote/datasource/file_remote_data_source.dart';
import 'package:nox_app/domain/model/app_config/server_limits.dart';

/// Stands in for the server's file chain in the mock-backed ENVIRONMENTS
/// `[prod, test]`. `Environment.dev` — the one the `stage` flavor boots —
/// resolves [RealFileRemoteDataSource] instead. There is no `dev` flavor.
///
/// It keeps bytes in a temp directory and hands out ids the way the server
/// would, so the repository runs the SAME code on both paths — and so the test
/// suite and the goldens never need a server to be running.
@LazySingleton(as: FileRemoteDataSource, env: [Environment.prod, Environment.test])
class MockFileRemoteDataSource implements FileRemoteDataSource {
  int _counter = 0;

  /// Where a pass lets bytes go, by pass: the upload and the offset the pass
  /// was issued for. Mirrors the server's one-shot semantics — a pass is removed
  /// once it is used.
  final Map<String, ({String fileId, int offset})> _passes = <String, ({String fileId, int offset})>{};

  /// Uploads the "server" knows, by file id: the size declared and how many
  /// bytes it holds (phase 043).
  final Map<String, ({int size, int received})> _uploads = <String, ({int size, int received})>{};

  /// Bytes the "server" holds, by file id.
  final Map<String, String> _stored = <String, String>{};

  @override
  Future<ResponseEntity<UploadTicketWireEntity>> uploadBegin({
    required String name,
    required int sizeBytes,
    required String mime,
    String? fileId,
  }) async {
    // The server validates these before issuing anything (§7); refusing here
    // too keeps the mock honest about what the real one rejects.
    if (name.trim().isEmpty || name.length > 255 || mime.trim().isEmpty || mime.length > 128) {
      return _refusal('invalid_request', 'name or mime out of bounds');
    }
    if (sizeBytes > ServerLimits.contractDefaults.maxAttachmentBytes) {
      return _refusal('payload_too_large', 'attachment exceeds the limit');
    }
    final String id;
    if (fileId != null) {
      final known = _uploads[fileId];
      if (known == null) return _refusal('not_found', 'no unfinished upload with this id');
      if (known.size != sizeBytes) return _refusal('invalid_request', 'not the file this upload declared');
      id = fileId;
    } else {
      id = 'f_mock_${_counter++}';
      _uploads[id] = (size: sizeBytes, received: 0);
    }
    final received = _uploads[id]!.received;
    final pass = 'pass_${id}_${_counter++}';
    _passes[pass] = (fileId: id, offset: received);
    return ResponseEntity<UploadTicketWireEntity>(
      success: true,
      data: UploadTicketWireEntity(
        fileId: id,
        uploadUrl: '/files/$pass',
        uploadToken: pass,
        maxAttachmentBytes: ServerLimits.contractDefaults.maxAttachmentBytes,
        received: received,
      ),
    );
  }

  @override
  Future<void> putBytes({required String uploadPath, required File file, required int offset, TransferProgress? onProgress}) async {
    final pass = uploadPath.split('/').last;
    // One-shot, like the real one: taking it here is what makes a second
    // attempt with the same pass behave as it does against the server - a 404,
    // which the repository answers by asking for another. Returning quietly
    // instead would tell it the bytes are there when they are not.
    final granted = _passes.remove(pass);
    if (granted == null || granted.offset != offset) throw const FileTransferException(FileTransferFailure.passRejected);
    final total = await file.length();
    onProgress?.call(total, total);
    _uploads[granted.fileId] = (size: total, received: total);
    _stored[granted.fileId] = file.path;
  }

  @override
  Future<ResponseEntity<DownloadTicketWireEntity>> downloadBegin({required String fileId}) async {
    if (!_stored.containsKey(fileId)) {
      return const ResponseEntity<DownloadTicketWireEntity>(
        success: false,
        error: ErrorWireEntity(code: 'attachment_gone', message: 'attachment bytes are no longer stored'),
      );
    }
    return ResponseEntity<DownloadTicketWireEntity>(
      success: true,
      data: DownloadTicketWireEntity(downloadUrl: '/files/get_$fileId', downloadToken: 'get_$fileId'),
    );
  }

  @override
  Future<FetchedBytes> openBytes({required String downloadPath, required int offset, String? validator}) async {
    final id = downloadPath.split('/').last.replaceFirst('get_', '');
    final source = _stored[id];
    // The server answers a bare 404 here; returning quietly would let the
    // repository treat an empty destination as a complete download, and the
    // suite would be green over a defect.
    if (source == null || !File(source).existsSync()) {
      throw const FileTransferException(FileTransferFailure.passRejected);
    }
    final file = File(source);
    final total = await file.length();
    final version = 'v-${(await file.lastModified()).millisecondsSinceEpoch}';
    // The rest only for bytes of this very version - as the server does with
    // If-Range - and the whole file for anything else.
    final rest = offset > 0 && validator == version;
    if (rest && offset >= total) throw const FileTransferException(FileTransferFailure.staleRange);
    return FetchedBytes(whole: !rest, total: total, validator: version, bytes: file.openRead(rest ? offset : 0), abandon: () {});
  }

  /// Nothing here outlives the call that started it, so there is nothing to end.
  @override
  void cancelTransfers() {}

  ResponseEntity<UploadTicketWireEntity> _refusal(String code, String message) => ResponseEntity<UploadTicketWireEntity>(
    success: false,
    error: ErrorWireEntity(code: code, message: message),
  );
}
