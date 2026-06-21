import 'package:intl/intl.dart';
import 'package:nox_app/general/text_constants.dart';

/// Static date-formatting helpers for consistent display app-wide.
class DateFormatter {
  DateFormatter._();

  static final _short = DateFormat('MMM dd, yyyy', 'en_US');
  static final _time = DateFormat('HH:mm', 'en_US');
  static final _dayMonth = DateFormat('d MMM', 'en_US');
  static final _dayMonthYear = DateFormat('d MMM y', 'en_US');

  static String short(DateTime date) => _short.format(date);

  static String time(DateTime date) => _time.format(date);

  /// Relative-time ladder for the chats list (5.1) and file/card screens (M4):
  /// `now` (<1 min) / `N min` (<1 h) / `N h` (<1 day) / `Yesterday` / `d MMM` (same
  /// year) / `d MMM y` (older). Source: `overview.md`. [now] is injectable for tests.
  static String relative(DateTime when, {DateTime? now}) {
    final ref = now ?? DateTime.now();
    final diff = ref.difference(when);
    // Clamp future timestamps (clock skew / a server time slightly ahead) to "now".
    if (diff.isNegative || diff.inSeconds < 60) return TextConstants.timeNow;
    if (diff.inMinutes < 60) return '${diff.inMinutes} ${TextConstants.timeMinuteSuffix}';
    // Hours only within the same calendar day; a previous day is Yesterday / a date.
    final today = DateTime(ref.year, ref.month, ref.day);
    final thatDay = DateTime(when.year, when.month, when.day);
    final dayDiff = today.difference(thatDay).inDays;
    if (dayDiff == 0) return '${diff.inHours} ${TextConstants.timeHourSuffix}';
    if (dayDiff == 1) return TextConstants.timeYesterday;
    return when.year == ref.year ? _dayMonth.format(when) : _dayMonthYear.format(when);
  }

  /// Date-separator label for the chat thread (5.2): `Today` / `Yesterday` /
  /// `12 May` (same year) / `12 May 2025` (older). [now] is injectable for tests.
  static String daySeparator(DateTime when, {DateTime? now}) {
    final ref = now ?? DateTime.now();
    final today = DateTime(ref.year, ref.month, ref.day);
    final thatDay = DateTime(when.year, when.month, when.day);
    final dayDiff = today.difference(thatDay).inDays;
    if (dayDiff <= 0) return TextConstants.dateToday;
    if (dayDiff == 1) return TextConstants.dateYesterday;
    return when.year == ref.year ? _dayMonth.format(when) : _dayMonthYear.format(when);
  }
}
