import 'package:intl/intl.dart';

/// Static date-formatting helpers for consistent display app-wide.
class DateFormatter {
  DateFormatter._();

  static final _short = DateFormat('MMM dd, yyyy', 'en_US');
  static final _time = DateFormat('HH:mm', 'en_US');
  static final _dMonth = DateFormat('d MMM', 'en_US'); // 12 May
  static final _dMonthYear = DateFormat('d MMM yyyy', 'en_US'); // 12 May 2025
  static final _weekday = DateFormat('EEEE', 'en_US'); // Monday

  static String short(DateTime date) => _short.format(date);

  static String time(DateTime date) => _time.format(date);

  /// Calendar-day difference (DST-safe): UTC midnights are exactly 24h apart, so
  /// this is not skewed by spring-forward/fall-back like a local-time `Duration`.
  static int _calendarDaysAgo(DateTime now, DateTime date) =>
      DateTime.utc(now.year, now.month, now.day).difference(DateTime.utc(date.year, date.month, date.day)).inDays;

  /// Chat-list relative timestamp (overview §«Форматы времени и даты», 5.1):
  /// `now` / `N min` / `N h` (relative, <24h) / `Yesterday` / `12 May` / `12 May 2025`.
  static String chatListTimestamp(DateTime date, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final diff = n.difference(date);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    if (diff.inHours < 24) return '${diff.inHours} h'; // relative hours, regardless of calendar day
    if (_calendarDaysAgo(n, date) == 1) return 'Yesterday';
    return date.year == n.year ? _dMonth.format(date) : _dMonthYear.format(date);
  }

  /// Chat-feed day separator (overview §«Форматы времени и даты», 5.2):
  /// `Today` / `Yesterday` / weekday (within a week) / `12 May` / `12 May 2025`.
  static String daySeparator(DateTime date, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final deltaDays = _calendarDaysAgo(n, date);
    if (deltaDays == 0) return 'Today';
    if (deltaDays == 1) return 'Yesterday';
    if (deltaDays > 1 && deltaDays < 7) return _weekday.format(date);
    return date.year == n.year ? _dMonth.format(date) : _dMonthYear.format(date);
  }
}
