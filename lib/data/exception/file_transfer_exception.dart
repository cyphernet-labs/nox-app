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

  /// The channel broke. Retryable like any other connection failure.
  connection,
}

class FileTransferException implements Exception {
  const FileTransferException(this.failure);

  final FileTransferFailure failure;

  @override
  String toString() => 'FileTransferException: ${failure.name}';
}
