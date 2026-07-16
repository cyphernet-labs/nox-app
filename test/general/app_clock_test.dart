import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/app_clock.dart';

void main() {
  group('AppClock', () {
    tearDown(AppClock.reset);

    test('now returns exactly the pinned instant after freeze', () {
      final pinned = DateTime(2026, 7, 18, 9, 30, 15, 500);
      AppClock.freeze(pinned);
      expect(AppClock.now(), pinned);
      // A frozen clock does not advance — repeated reads are identical.
      expect(AppClock.now(), pinned);
    });

    test('a second freeze overwrites the previous pin', () {
      final first = DateTime(2026, 1, 1);
      final second = DateTime(2027, 12, 31, 23, 59, 59);
      AppClock.freeze(first);
      expect(AppClock.now(), first);
      AppClock.freeze(second);
      expect(AppClock.now(), second);
    });

    test('reset clears the pin so now returns the real wall clock', () {
      AppClock.freeze(DateTime(2000));
      expect(AppClock.now(), DateTime(2000));

      AppClock.reset();

      // After reset the clock is live again: within a small window of the real
      // wall clock — never an equality assertion against DateTime.now().
      final before = DateTime.now();
      final observed = AppClock.now();
      final after = DateTime.now();
      expect(observed.isBefore(before.subtract(const Duration(seconds: 2))), isFalse);
      expect(observed.isAfter(after.add(const Duration(seconds: 2))), isFalse);
    });

    test('without any freeze now tracks the real wall clock within a small window', () {
      final before = DateTime.now();
      final observed = AppClock.now();
      final after = DateTime.now();
      expect(observed.difference(before).inMilliseconds >= -2000, isTrue);
      expect(after.difference(observed).inMilliseconds >= -2000, isTrue);
    });
  });
}
