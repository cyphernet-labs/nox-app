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

  /// Calendar-day difference for two LOCAL DateTimes (DST-safe): UTC midnights are
  /// exactly 24h apart, so the count is not skewed by spring-forward/fall-back.
  /// Callers normalize operands via toLocal() first (server timestamps are UTC).
  static int _calendarDaysAgo(DateTime localNow, DateTime localDate) => DateTime.utc(
    localNow.year,
    localNow.month,
    localNow.day,
  ).difference(DateTime.utc(localDate.year, localDate.month, localDate.day)).inDays;

  /// Chat-list relative timestamp (overview §«Форматы времени и даты», 5.1):
  /// `now` / `N min` / `N h` (relative, <24h) / `Yesterday` / `12 May` / `12 May 2025`.
  static String chatListTimestamp(DateTime date, {DateTime? now}) {
    final n = (now ?? DateTime.now()).toLocal();
    final d = date.toLocal(); // server timestamps are UTC (see ItemMapper); compare in local time
    final diff = n.difference(d);
    if (diff.isNegative) {
      // Future timestamp (clock skew): same local day -> 'now', otherwise show its date.
      return _calendarDaysAgo(n, d) == 0 ? 'now' : (d.year == n.year ? _dMonth.format(d) : _dMonthYear.format(d));
    }
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    if (diff.inHours < 24) return '${diff.inHours} h'; // relative hours, regardless of calendar day
    if (_calendarDaysAgo(n, d) == 1) return 'Yesterday';
    return d.year == n.year ? _dMonth.format(d) : _dMonthYear.format(d);
  }

  /// Chat-feed day separator (overview §«Форматы времени и даты», 5.2):
  /// `Today` / `Yesterday` / weekday (within a week) / `12 May` / `12 May 2025`.
  static String daySeparator(DateTime date, {DateTime? now}) {
    final n = (now ?? DateTime.now()).toLocal();
    final d = date.toLocal();
    final deltaDays = _calendarDaysAgo(n, d);
    if (deltaDays == 0) return 'Today';
    if (deltaDays == 1) return 'Yesterday';
    if (deltaDays > 1 && deltaDays < 7) return _weekday.format(d);
    return d.year == n.year ? _dMonth.format(d) : _dMonthYear.format(d);
  }
}
