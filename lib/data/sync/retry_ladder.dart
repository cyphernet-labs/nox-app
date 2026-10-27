import 'dart:math';

/// The pause before an automatic retry, and the number of refusals that ends
/// one - a single ladder for everything the app retries on its own: the
/// outgoing queue, the creation of a chat, and the download of a file.
///
/// One ladder on purpose. Two would drift apart, and a person whose message
/// waits thirty seconds while the picture beside it is asked for every second
/// would see a fault where there is only a difference nobody chose.
class RetryLadder {
  RetryLadder({Random? random}) : _random = random ?? Random();

  static const Duration minPause = Duration(seconds: 1);
  static const Duration maxPause = Duration(seconds: 30);

  /// How many times the SERVER may refuse before the automation gives up.
  ///
  /// Counted against refusals only, never against a broken connection. That
  /// distinction is the whole point: a flapping link produces failure after
  /// failure through no fault of the work, and counting those would give up on
  /// perfectly good work within seconds of a bad tunnel.
  ///
  /// Giving up is not discarding - the work stays, visible, and a tap starts
  /// the ladder over. What the cap buys is that work the server keeps refusing
  /// with a retryable code (a persistent `internal`) cannot hold everything
  /// behind it forever.
  static const int refusalLimit = 10;

  final Random _random;

  /// `min(30s, 1s * 2^(attempts - 1))` with ±20% jitter. [attempts] counts the
  /// failures so far, the first one included.
  Duration pause(int attempts) {
    final exponent = (attempts - 1).clamp(0, 16);
    final raw = minPause * pow(2, exponent).toDouble();
    final capped = raw > maxPause ? maxPause : raw;
    // Jitter keeps a herd of clients from hitting a recovering server in step.
    return capped * (0.8 + _random.nextDouble() * 0.4);
  }
}
