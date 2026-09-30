import 'package:nox_app/data/sync/connection/direct_prober.dart';

/// Direct addresses, scripted: which answer as home, which answer with another
/// key, and which say nothing. Every round is recorded.
class FakeDirectProber implements DirectProber {
  FakeDirectProber({this.home});

  /// Addresses that answer with the right key. Null means every candidate does.
  Set<String>? home;

  /// Addresses that answer with ANOTHER key - not home.
  Set<String> otherKey = <String>{};

  /// The candidates of every round, in order.
  final List<List<String>> rounds = <List<String>>[];

  @override
  Future<DirectProbeResult> probe(List<String> candidates, {required String fingerprint}) async {
    rounds.add(List<String>.of(candidates));
    final notHome = candidates.where(otherKey.contains).toList();
    for (final candidate in candidates) {
      if (otherKey.contains(candidate)) continue;
      final answers = home;
      if (answers == null || answers.contains(candidate)) return DirectProbeResult(address: candidate, notHome: notHome);
    }
    return DirectProbeResult(notHome: notHome);
  }
}
