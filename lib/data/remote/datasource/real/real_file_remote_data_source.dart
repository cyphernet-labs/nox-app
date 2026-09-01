import 'dart:io';

import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/file/upload_ticket_wire_entity.dart';
import 'package:nox_app/data/exception/file_transfer_exception.dart';
import 'package:nox_app/data/remote/api_client.dart';
import 'package:nox_app/data/remote/datasource/file_remote_data_source.dart';
import 'package:nox_app/data/remote/datasource/real/socket_envelope.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';

/// The file chain over the live channel (contract v0 §7).
///
/// The only place in the app where both transports meet: declarations go over
/// the socket, bytes over HTTP. This is also the first real consumer of
/// [ApiClient] — before this feature `initBase()` was never called from app
/// code at all, and Dio was held in reserve for exactly this.
@LazySingleton(as: FileRemoteDataSource, env: [Environment.dev])
class RealFileRemoteDataSource implements FileRemoteDataSource {
  RealFileRemoteDataSource(this._socket, this._apiClient);

  final NoxSocketClient _socket;
  final ApiClient _apiClient;

  @override
  Future<ResponseEntity<UploadTicketWireEntity>> uploadBegin({required String name, required int sizeBytes, required String mime}) async {
    final reply = await _socket.send('file.uploadBegin', <String, dynamic>{'name': name, 'size': sizeBytes, 'mime': mime});
    return reply.toEnvelope(UploadTicketWireEntity.fromJson);
  }

  @override
  Future<ResponseEntity<DownloadTicketWireEntity>> downloadBegin({required String fileId}) async {
    final reply = await _socket.send('file.downloadBegin', <String, dynamic>{'file_id': fileId});
    return reply.toEnvelope(DownloadTicketWireEntity.fromJson);
  }

  @override
  Future<void> putBytes({required String uploadPath, required File file, TransferProgress? onProgress}) async {
    final total = await file.length();
    try {
      await _apiClient.dio
          .put<void>(
            uploadPath,
            data: file.openRead(), // streamed: a large attachment never lands in RAM
            options: Options(
              headers: <String, dynamic>{Headers.contentLengthHeader: total},
              // The server answers 204 and every token failure as a bare 404; let
              // this method decide what those mean rather than letting Dio throw a
              // shape the general mapper would misread.
              validateStatus: (status) => status != null && status < 500,
            ),
            onSendProgress: onProgress == null ? null : (sent, _) => onProgress(sent, total),
          )
          .then(_checkTransfer);
    } on DioException {
      // Every status this method cares about is handled above without throwing;
      // reaching here means the transport itself failed, or the server answered
      // 5xx. Both are the same thing to the caller: try again later.
      throw const FileTransferException(FileTransferFailure.connection);
    }
  }

  @override
  Future<void> getBytes({required String downloadPath, required File destination, TransferProgress? onProgress}) async {
    try {
      final response = await _apiClient.dio.download(
        downloadPath,
        destination.path,
        options: Options(validateStatus: (status) => status != null && status < 500),
        onReceiveProgress: onProgress == null ? null : (received, total) => onProgress(received, total),
      );
      _checkTransfer(response);
    } on DioException {
      throw const FileTransferException(FileTransferFailure.connection);
    }
  }

  /// Turns a non-throwing HTTP status into the failure it actually means.
  void _checkTransfer(Response<dynamic> response) {
    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) return;
    // 404 is the contract's single answer for every token failure — spent,
    // expired, never existed. It is routine, not fatal: ask for a new pass.
    if (status == 404) throw const FileTransferException(FileTransferFailure.passRejected);
    // 413 too many bytes, 400 too few. Either way what is on disk is not what
    // was announced, and announcing it again would fail the same way.
    if (status == 413 || status == 400) throw const FileTransferException(FileTransferFailure.sizeMismatch);
    throw const FileTransferException(FileTransferFailure.connection);
  }
}
