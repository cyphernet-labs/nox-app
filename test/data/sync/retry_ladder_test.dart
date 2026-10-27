import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/sync/retry_ladder.dart';

/// A random source that always answers the same fraction, so the jitter is a
/// known factor: 0.0 → 0.8, 0.5 → 1.0, just under 1.0 → just under 1.2.
class _Fixed implements Random {
  _Fixed(this.value);
  final double value;

  @override
  double nextDouble() => value;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}

void main() {
  test('the pause doubles from one second and stops at thirty', () {
    final ladder = RetryLadder(random: _Fixed(0.5));
    expect(ladder.pause(1), const Duration(seconds: 1));
    expect(ladder.pause(2), const Duration(seconds: 2));
    expect(ladder.pause(3), const Duration(seconds: 4));
    expect(ladder.pause(5), const Duration(seconds: 16));
    expect(ladder.pause(6), const Duration(seconds: 30), reason: '32 s is over the cap');
    expect(ladder.pause(40), const Duration(seconds: 30), reason: 'a long run of failures never waits longer');
  });

  test('no failure yet counts as the first', () {
    expect(RetryLadder(random: _Fixed(0.5)).pause(0), const Duration(seconds: 1));
  });

  test('the jitter stays within twenty percent either way', () {
    expect(RetryLadder(random: _Fixed(0)).pause(3), const Duration(milliseconds: 3200));
    final high = RetryLadder(random: _Fixed(0.999999)).pause(3);
    expect(high, lessThan(const Duration(milliseconds: 4800)));
    expect(high, greaterThan(const Duration(milliseconds: 4790)));
  });

  test('ten refusals end the automation', () {
    expect(RetryLadder.refusalLimit, 10);
  });
}
