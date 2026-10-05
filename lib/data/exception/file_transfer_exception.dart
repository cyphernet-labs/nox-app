/// Why a byte transfer failed, in the only terms the caller can act on.
///
/// A separate type because the general Dio mapping gets this wire's main case
/// exactly backwards. Contract §7: "все отказы токена на HTTP — единый `404`
/// без раскрытия причин", and the contract calls that routine — ask for a new
/// pass. The general mapper turns 404 into `notFound`, which the outbox drain
/// treats as TERMINAL, so a pass that expired while the message waited its turn
/// would kill that message forever. That is precisely the case the durable
/// queue exists to survive.
enum FileTransferFailure {
  /// The pass is spent or expired. Routine: start again from a new declaration.
  passRejected,

  /// The bytes did not match what was declared. Nothing to retry — the file on
  /// disk is not the file we announced.
  sizeMismatch,

  /// The part this device holds is not shorter than the file on the server
  /// (416): it belongs to some other version of the file. Discard it and start
  /// over - nothing the server did is wrong.
  staleRange,

  /// The channel broke. Retryable like any other connection failure.
  connection,

  /// The path changed while the bytes were going (phase 043): the transfer
  /// ended with the old one, and the rest can go at once by the new one - no
  /// pause, nothing counted. A change of path is not a fault of the transfer.
  pathChanged,

  /// The server answered, and the answer was no use: a 5xx, a status the
  /// contract does not name, a body whose size cannot be told. Not a broken
  /// link - the server is there and said something - so it counts towards
  /// giving up, as a refusal of `message.send` does; until then the next
  /// attempt goes on from what is already there.
  serverError,

  /// The file on this device cannot be read: removed, locked by another
  /// program, or no longer permitted - a sandbox forgets a picked file when
  /// the app restarts. No retry reads it, so the message is done; letting it
  /// count as a broken link held the whole queue behind it for good.
  sourceUnreadable,
}

class FileTransferException implements Exception {
  const FileTransferException(this.failure);

  final FileTransferFailure failure;

  @override
  String toString() => 'FileTransferException: ${failure.name}';
}
