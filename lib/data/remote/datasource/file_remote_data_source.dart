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

  /// Opens the file's bytes: the rest of it from [offset] when [validator] says
  /// which version of the file the bytes on this device came from, the whole
  /// file otherwise - or when the server holds another version now. The caller
  /// writes them; [FetchedBytes.whole] says which of the two arrived. Ends with
  /// a connection failure once no byte has arrived for the stall limit.
  Future<FetchedBytes> openBytes({required String downloadPath, required int offset, String? validator});

  /// Ends every byte transfer under way: a logout, a change of server, a path
  /// the socket has left. Each ends as a broken connection would, and each was
  /// resumable, so nothing is lost but the bytes in flight.
  void cancelTransfers();
}

/// What a download request brought (phase 043): the rest of the file from
/// where this device stopped, or the whole file over again.
class FetchedBytes {
  const FetchedBytes({required this.whole, required this.total, required this.validator, required this.bytes, required this.abandon});

  /// The whole file, from its first byte: the server ignored the range,
  /// because the bytes here belong to another version of the file.
  final bool whole;

  /// The size of the whole file, however much of it is coming.
  final int total;

  /// What the server calls this version of the file (`Last-Modified`): the
  /// next request for the rest names it, so bytes of two versions can never
  /// meet in one file. Null when the server named none - the bytes then cannot
  /// be continued.
  final String? validator;

  /// The bytes, as they arrive. Errors are [FileTransferException]s.
  final Stream<List<int>> bytes;

  /// Lets the bytes go without reading them - the file turned out to be one
  /// this device does not want - and hands the transfer back.
  final void Function() abandon;
}
