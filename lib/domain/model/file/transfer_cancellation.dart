import 'dart:async';

/// Ends ONE transfer from outside it (phase 043): the message whose file is
/// going up was thrown away.
///
/// The queue is one strictly ordered line, so an upload nobody wants any more
/// held every later message in every chat for as long as its bytes kept going
/// - through Tor, tens of minutes. Ending every transfer instead would cost the
/// downloads under way their connections for a decision that had nothing to do
/// with them.
class TransferCancellation {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  /// Completes once [cancel] is called; never with an error.
  Future<void> get whenCancelled => _cancelled.future;

  /// Idempotent: a second call changes nothing.
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}
