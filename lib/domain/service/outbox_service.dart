/// Drains the outgoing queue - and is the ONLY thing in the app that sends.
///
/// Single sender is the load-bearing rule: a duplicate in a journal with no
/// deletion cannot be taken back, so every send goes through one serialised
/// drain. Screens enqueue through the outbox repository and ask for a pass;
/// they never send themselves.
abstract class OutboxService {
  /// Starts draining whenever the channel turns current. Idempotent.
  void start();

  /// Runs a drain pass, chained after any pass already running.
  Future<void> flush();

  /// Throws a message away before it is sent: its record goes, and an upload
  /// of its file still under way is ended.
  Future<void> discard({required String clientMessageId});

  /// Stops draining and waits for a pass under way - before a logout wipes
  /// the stores a pass would write.
  Future<void> stop();
}
