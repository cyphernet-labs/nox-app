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
  /// Declares a file and asks for somewhere to put it. `mime` is derived from
  /// the name's extension — the picker never reads bytes (§9.2).
  Future<ResponseEntity<UploadTicketWireEntity>> uploadBegin({required String name, required int sizeBytes, required String mime});

  /// Sends exactly [sizeBytes] bytes. More is refused with 413, fewer with 400,
  /// and neither is stored — so a torn transfer leaves nothing behind.
  Future<void> putBytes({required String uploadPath, required File file, TransferProgress? onProgress});

  Future<ResponseEntity<DownloadTicketWireEntity>> downloadBegin({required String fileId});

  Future<void> getBytes({required String downloadPath, required File destination, TransferProgress? onProgress});
}
