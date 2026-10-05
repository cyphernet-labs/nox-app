import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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
///
/// No transfer has a time limit (phase 043): through Tor 100 MiB take tens of
/// minutes, and a limit on the whole transfer cut exactly the slow path it was
/// supposed to survive. A transfer ends only when its bytes STOP moving for
/// [defaultStallLimit] - and, being resumable, it then goes on from where it
/// stopped.
@LazySingleton(as: FileRemoteDataSource, env: [Environment.dev])
class RealFileRemoteDataSource implements FileRemoteDataSource {
  RealFileRemoteDataSource(this._socket, this._apiClient) : _stallLimit = defaultStallLimit, _answerWait = defaultAnswerWait;

  @visibleForTesting
  RealFileRemoteDataSource.forTest(
    this._socket,
    this._apiClient, {
    this._stallLimit = defaultStallLimit,
    this._answerWait = defaultAnswerWait,
  });

  /// How long bytes may stop moving before a transfer counts as broken.
  ///
  /// Shorter than the server's 60 seconds on purpose: the side that runs the
  /// retry should be the one to give up first, and the server ends the request
  /// it was still holding as soon as the retry reaches it.
  static const Duration defaultStallLimit = Duration(seconds: 45);

  /// How long a PUT waits for the server's answer once its last byte has been
  /// handed to the socket.
  ///
  /// Longer than the stall limit, and for a reason that only shows on a slow
  /// path: "handed to the socket" is not "arrived". Through Tor the socket,
  /// the bridge and the circuit hold megabytes between them, draining at tens
  /// of kilobytes a second, and nothing on this side can see them drain - the
  /// stall limit would cut a healthy upload in its last minute. A path that
  /// really died ends sooner anyway: the socket notices, the path changes, and
  /// the change ends every transfer on the old one.
  static const Duration defaultAnswerWait = Duration(minutes: 3);

  final NoxSocketClient _socket;
  final ApiClient _apiClient;
  final Duration _stallLimit;
  final Duration _answerWait;

  @override
  Future<ResponseEntity<UploadTicketWireEntity>> uploadBegin({
    required String name,
    required int sizeBytes,
    required String mime,
    String? fileId,
  }) async {
    final reply = await _socket.send('file.uploadBegin', <String, dynamic>{
      'name': name,
      'size': sizeBytes,
      'mime': mime,
      // Only when continuing: an absent field is a new upload, to this server
      // and to one that has never heard of continuing.
      'file_id': ?fileId,
    });
    return reply.toEnvelope(UploadTicketWireEntity.fromJson);
  }

  @override
  Future<ResponseEntity<DownloadTicketWireEntity>> downloadBegin({required String fileId}) async {
    final reply = await _socket.send('file.downloadBegin', <String, dynamic>{'file_id': fileId});
    return reply.toEnvelope(DownloadTicketWireEntity.fromJson);
  }

  @override
  Future<void> putBytes({required String uploadPath, required File file, required int offset, TransferProgress? onProgress}) async {
    final total = await file.length();
    final cancel = _apiClient.beginTransfer();
    // Dio's own sendTimeout bounds the WHOLE body, which is the limit this
    // phase removes. What it needs instead is a bound on silence: every chunk
    // the socket takes rearms the watch.
    final watch = _StallWatch(_stallLimit, () => cancel.cancel('stalled'));
    try {
      final response = await _apiClient.dio.put<void>(
        uploadPath,
        data: file.openRead(offset), // streamed from where the server stopped; never in RAM
        cancelToken: cancel,
        options: Options(
          headers: <String, dynamic>{Headers.contentLengthHeader: total - offset},
          // The answer comes only once the bytes still in the buffers have
          // drained to the server (see [defaultAnswerWait]).
          receiveTimeout: _answerWait,
          // The server answers 204 and every token failure as a bare 404; let
          // this method decide what those mean rather than letting Dio throw a
          // shape the general mapper would misread.
          validateStatus: (status) => status != null && status < 500,
        ),
        onSendProgress: (sent, _) {
          if (offset + sent >= total) {
            watch.wait(_answerWait);
          } else {
            watch.moved();
          }
          onProgress?.call(offset + sent, total);
        },
      );
      _checkTransfer(response);
    } on DioException {
      // Every status this method cares about is handled above without throwing;
      // reaching here means the transport itself failed, the bytes stopped, the
      // transfer was ended from outside, or the server answered 5xx. All of it
      // is the same thing to the caller: try again later, from where it got to.
      throw const FileTransferException(FileTransferFailure.connection);
    } finally {
      watch.stop();
      _apiClient.endTransfer(cancel);
    }
  }

  @override
  Future<FetchedBytes> openBytes({required String downloadPath, required int offset, String? validator}) async {
    final cancel = _apiClient.beginTransfer();
    // Only with a validator: bytes whose version nobody wrote down could be the
    // start of another file, and the server is the only one who can say.
    final resuming = offset > 0 && validator != null;
    final Response<ResponseBody> response;
    try {
      response = await _apiClient.dio.get<ResponseBody>(
        downloadPath,
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.stream,
          // Dio counts this between chunks of the body, not over the whole of
          // it: silence ends the transfer, time alone never does.
          receiveTimeout: _stallLimit,
          headers: resuming ? <String, dynamic>{'range': 'bytes=$offset-', 'if-range': validator} : null,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
    } on DioException {
      _apiClient.endTransfer(cancel);
      throw const FileTransferException(FileTransferFailure.connection);
    }

    final status = response.statusCode ?? 0;
    final body = response.data;
    if ((status == 200 || status == 206) && body != null) {
      final whole = status == 200;
      final total = whole ? _lengthOf(response, body) : _rangeTotalFrom(response, offset);
      if (total != null) {
        // Armed now, not at the first byte: Dio starts its own clock only once
        // a chunk arrives, so a body that never sends one would wait forever.
        final watch = _StallWatch(_stallLimit, () => cancel.cancel('stalled'));
        return FetchedBytes(
          whole: whole,
          total: total,
          validator: response.headers.value('last-modified'),
          bytes: _guarded(body.stream, cancel, watch),
          abandon: () {
            watch.stop();
            cancel.cancel('abandoned');
            _apiClient.endTransfer(cancel);
          },
        );
      }
    }
    // Anything else carries no bytes worth reading; let the connection go.
    cancel.cancel('not a body this download can use');
    _apiClient.endTransfer(cancel);
    // 404 is every token failure (ask for a new pass); 416 says the bytes here
    // are not shorter than the file there - another version of it.
    if (status == 404) throw const FileTransferException(FileTransferFailure.passRejected);
    // A range that does not start where this device stopped fits nothing here
    // either: start the file over rather than ask the same question forever.
    if (status == 416 || status == 206) throw const FileTransferException(FileTransferFailure.staleRange);
    throw const FileTransferException(FileTransferFailure.connection);
  }

  /// The body, with every way it can break turned into a broken connection,
  /// silence ended by [watch], and the transfer handed back however it ends.
  Stream<List<int>> _guarded(Stream<List<int>> source, CancelToken cancel, _StallWatch watch) async* {
    try {
      await for (final chunk in source) {
        watch.moved();
        yield chunk;
      }
    } on Object {
      throw const FileTransferException(FileTransferFailure.connection);
    } finally {
      watch.stop();
      _apiClient.endTransfer(cancel);
    }
  }

  static int? _lengthOf(Response<ResponseBody> response, ResponseBody body) {
    final declared = int.tryParse(response.headers.value(Headers.contentLengthHeader) ?? '');
    return declared ?? (body.contentLength >= 0 ? body.contentLength : null);
  }

  /// The whole size from `Content-Range: bytes <start>-<end>/<total>`, or null
  /// when the range does not start where this device stopped - the rest of the
  /// file only fits here if it begins exactly there.
  static int? _rangeTotalFrom(Response<ResponseBody> response, int offset) {
    final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(response.headers.value('content-range') ?? '');
    if (match == null || int.parse(match.group(1)!) != offset) return null;
    return int.parse(match.group(3)!);
  }

  @override
  void cancelTransfers() => _apiClient.cancelTransfers();

  /// Turns a non-throwing HTTP status into the failure it actually means.
  void _checkTransfer(Response<dynamic> response) {
    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) return;
    // 404 is the contract's single answer for every token failure — spent,
    // expired, never existed. It is routine, not fatal: ask for a new pass.
    if (status == 404) throw const FileTransferException(FileTransferFailure.passRejected);
    // 413 too many bytes, 400 too few. Either way what was sent is not what
    // was announced, and announcing it again would fail the same way.
    if (status == 413 || status == 400) throw const FileTransferException(FileTransferFailure.sizeMismatch);
    // 408 (the server saw the bytes stop), 409 (an earlier attempt still held
    // the file) and anything else: the transfer broke, and the next attempt
    // goes on from what the server has.
    throw const FileTransferException(FileTransferFailure.connection);
  }
}

/// Fires once bytes have not moved for [limit]. Rearmed by every sign that
/// they did.
class _StallWatch {
  _StallWatch(this._limit, this._onStall) {
    _arm();
  }

  final Duration _limit;
  final void Function() _onStall;
  Timer? _timer;

  void moved() => _arm(_limit);

  /// Nothing more will move on this side: allow [wait] for what follows.
  void wait(Duration wait) => _arm(wait);

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _arm([Duration? limit]) {
    _timer?.cancel();
    _timer = Timer(limit ?? _limit, () {
      _timer = null;
      _onStall();
    });
  }
}
