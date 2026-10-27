import 'package:nox_app/general/app_clock.dart';

/// Monotonic journal-number minting for runtime-created MOCK rows (send echo,
/// simulated inbound, created-chat genesis). Mirrors what the real server's
/// AUTOINCREMENT journal guarantees: every minted seq exceeds all seeded seqs
/// (seed bases are small) and stays unique under the frozen golden clock via
/// the counter component. Mock-era only — dies with the 016 DI flip.
abstract final class MockSeq {
  static int _counter = 0;

  static int next() => AppClock.now().toUtc().millisecondsSinceEpoch * 1000 + (_counter++ % 1000);
}
