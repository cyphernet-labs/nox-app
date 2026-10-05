import 'dart:io';

import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/file/upload_ticket_wire_entity.dart';

/// Reports how much of a transfer has happened, so a determinate progress bar
/// can exist at all. Without it the screen could only show "working", and the
/// bar 5.3 already draws would have nothing truthful to fill it with.
typedef TransferProgress = void Function(int done, int total);

/// The file chain's network boundary (contract v0 §7, feature 016 seam).
///
/// Two halves on purpose. The declarations travel over the socket, because they
/// are commands like any other; the BYTES travel over HTTP, because the
/// contract says so and says why — on the socket a large file blocks every
/// interactive command behind it, cannot resume, and buffers into memory.
abstract class FileRemoteDataSource {
  /// Declares a file and asks for somewhere to put it — or, with [fileId],
  /// asks to continue the unfinished upload of that file (contract §7, phase
  /// 043). `mime` is derived from the name's extension — the picker never reads
  /// bytes (§9.2). The declaration stays whole when continuing: a server older
  /// than the phase skips the unknown field and declares a new file.
  Future<ResponseEntity<UploadTicketWireEntity>> uploadBegin({
    required String name,
    required int sizeBytes,
    required String mime,
    String? fileId,
  });

  /// Sends the file from [offset] to its end — possibly nothing, when the
  /// server already holds every byte and only has to be told the upload is
  /// complete. Whatever arrives stays on the server, so a broken transfer is
  /// continued, not repeated. Ends with a connection failure once no byte has
  /// moved for the stall limit.
  Future<void> putBytes({required String uploadPath, required File file, required int offset, TransferProgress? onProgress});

  Future<ResponseEntity<DownloadTicketWireEntity>> downloadBegin({required String fileId});

  Future<void> getBytes({required String downloadPath, required File destination, TransferProgress? onProgress});

  /// Ends every byte transfer under way: a logout, a change of server, a path
  /// the socket has left. Each ends as a broken connection would, and each was
  /// resumable, so nothing is lost but the bytes in flight.
  void cancelTransfers();
}
