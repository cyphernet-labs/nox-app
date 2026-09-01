import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/base/error_wire_entity.dart';
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

  /// Where a declared upload agreed to put its bytes, by pass. Mirrors the
  /// server's one-shot semantics: a pass is removed once it is used.
  final Map<String, String> _passes = <String, String>{};

  /// Bytes the "server" holds, by file id.
  final Map<String, String> _stored = <String, String>{};

  @override
  Future<ResponseEntity<UploadTicketWireEntity>> uploadBegin({required String name, required int sizeBytes, required String mime}) async {
    // The server validates these before issuing anything (§7); refusing here
    // too keeps the mock honest about what the real one rejects.
    if (name.trim().isEmpty || name.length > 255 || mime.trim().isEmpty || mime.length > 128) {
      return const ResponseEntity<UploadTicketWireEntity>(
        success: false,
        error: ErrorWireEntity(code: 'invalid_request', message: 'name or mime out of bounds'),
      );
    }
    if (sizeBytes > ServerLimits.contractDefaults.maxAttachmentBytes) {
      return const ResponseEntity<UploadTicketWireEntity>(
        success: false,
        error: ErrorWireEntity(code: 'payload_too_large', message: 'attachment exceeds the limit'),
      );
    }
    final id = 'f_mock_${_counter++}';
    final pass = 'pass_$id';
    _passes[pass] = id;
    return ResponseEntity<UploadTicketWireEntity>(
      success: true,
      data: UploadTicketWireEntity(
        fileId: id,
        uploadUrl: '/files/$pass',
        uploadToken: pass,
        maxAttachmentBytes: ServerLimits.contractDefaults.maxAttachmentBytes,
      ),
    );
  }

  @override
  Future<void> putBytes({required String uploadPath, required File file, TransferProgress? onProgress}) async {
    final pass = uploadPath.split('/').last;
    // One-shot, like the real one: taking it here is what makes a second
    // attempt with the same pass behave as it does against the server.
    final id = _passes.remove(pass);
    if (id == null) return; // a spent pass; the repository asks for a new one
    final total = await file.length();
    onProgress?.call(total, total);
    _stored[id] = file.path;
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
  Future<void> getBytes({required String downloadPath, required File destination, TransferProgress? onProgress}) async {
    final id = downloadPath.split('/').last.replaceFirst('get_', '');
    final source = _stored[id];
    if (source == null || !File(source).existsSync()) return;
    await File(source).copy(destination.path);
    final total = await destination.length();
    onProgress?.call(total, total);
  }
}
