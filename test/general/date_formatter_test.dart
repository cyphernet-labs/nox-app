import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/formatters/date_formatter.dart';

// US3 / FR-012: relative ladders match overview §«Форматы времени и даты».
void main() {
  final now = DateTime(2025, 5, 12, 14, 0); // Mon 12 May 2025, 14:00

  group('chatListTimestamp', () {
    test('now / min / h', () {
      expect(DateFormatter.chatListTimestamp(now.subtract(const Duration(seconds: 30)), now: now), 'now');
      expect(DateFormatter.chatListTimestamp(now.subtract(const Duration(minutes: 5)), now: now), '5 min');
      expect(DateFormatter.chatListTimestamp(now.subtract(const Duration(hours: 2)), now: now), '2 h');
    });
    test('yesterday / this-year date / past-year date', () {
      expect(DateFormatter.chatListTimestamp(DateTime(2025, 5, 11, 9), now: now), 'Yesterday');
      expect(DateFormatter.chatListTimestamp(DateTime(2025, 3, 3, 9), now: now), '3 Mar');
      expect(DateFormatter.chatListTimestamp(DateTime(2024, 5, 12, 9), now: now), '12 May 2024');
    });
  });

  group('daySeparator', () {
    test('today / yesterday / weekday / dates', () {
      expect(DateFormatter.daySeparator(DateTime(2025, 5, 12, 1), now: now), 'Today');
      expect(DateFormatter.daySeparator(DateTime(2025, 5, 11, 1), now: now), 'Yesterday');
      expect(DateFormatter.daySeparator(DateTime(2025, 5, 8, 1), now: now), 'Thursday'); // within a week
      expect(DateFormatter.daySeparator(DateTime(2025, 4, 1, 1), now: now), '1 Apr');
      expect(DateFormatter.daySeparator(DateTime(2024, 12, 31, 1), now: now), '31 Dec 2024');
    });
  });
}
