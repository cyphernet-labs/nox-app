/// Where a queued send stands.
///
/// There is deliberately no `sending`: that state lives exactly as long as one
/// `await` inside the drain, and persisting it would leave a lie on disk after
/// a crash — a record nobody is sending, marked as being sent.
enum OutboxStatus {
  /// Waiting for its turn, or for the next attempt after a failure the retry
  /// can fix.
  pending,

  /// The server refused it in a way retrying cannot fix. It stays in the queue
  /// so the message is not silently lost, but nothing will send it again until
  /// a person acts.
  error,
}
