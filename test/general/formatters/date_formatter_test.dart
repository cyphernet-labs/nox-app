import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/formatters/date_formatter.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  group('DateFormatter.relative', () {
    final now = DateTime(2026, 6, 20, 12);

    String rel(DateTime when) => DateFormatter.relative(when, now: now, l10n: l10nEn);

    test('under a minute → now', () {
      expect(rel(now.subtract(const Duration(seconds: 30))), l10nEn.timeNow);
    });

    test('minutes → "N min"', () {
      expect(rel(now.subtract(const Duration(minutes: 5))), '5 ${l10nEn.timeMinuteSuffix}');
    });

    test('hours → "N h"', () {
      expect(rel(now.subtract(const Duration(hours: 2))), '2 ${l10nEn.timeHourSuffix}');
    });

    test('previous calendar day → Yesterday', () {
      expect(rel(DateTime(2026, 6, 19, 23)), l10nEn.timeYesterday);
    });

    test('earlier this year → "d MMM"', () {
      expect(rel(DateTime(2026, 5, 12, 9)), '12 May');
    });

    test('a previous year → "d MMM y"', () {
      expect(rel(DateTime(2025, 5, 12, 9)), '12 May 2025');
    });

    test('a future timestamp (clock skew) clamps to now, never a negative value', () {
      expect(rel(now.add(const Duration(minutes: 10))), l10nEn.timeNow);
      expect(rel(now.add(const Duration(hours: 3))), l10nEn.timeNow);
    });
  });
}
