import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/formatters/date_formatter.dart';
import 'package:nox_app/general/text_constants.dart';

void main() {
  group('DateFormatter.relative', () {
    final now = DateTime(2026, 6, 20, 12);

    String rel(DateTime when) => DateFormatter.relative(when, now: now);

    test('under a minute → now', () {
      expect(rel(now.subtract(const Duration(seconds: 30))), TextConstants.timeNow);
    });

    test('minutes → "N min"', () {
      expect(rel(now.subtract(const Duration(minutes: 5))), '5 ${TextConstants.timeMinuteSuffix}');
    });

    test('hours → "N h"', () {
      expect(rel(now.subtract(const Duration(hours: 2))), '2 ${TextConstants.timeHourSuffix}');
    });

    test('previous calendar day → Yesterday', () {
      expect(rel(DateTime(2026, 6, 19, 23)), TextConstants.timeYesterday);
    });

    test('earlier this year → "d MMM"', () {
      expect(rel(DateTime(2026, 5, 12, 9)), '12 May');
    });

    test('a previous year → "d MMM y"', () {
      expect(rel(DateTime(2025, 5, 12, 9)), '12 May 2025');
    });
  });
}
