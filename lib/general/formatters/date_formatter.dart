import 'package:intl/intl.dart';

/// Static date-formatting helpers for consistent display app-wide.
class DateFormatter {
  DateFormatter._();

  static final _short = DateFormat('MMM dd, yyyy', 'en_US');
  static final _time = DateFormat('HH:mm', 'en_US');

  static String short(DateTime date) => _short.format(date);

  static String time(DateTime date) => _time.format(date);
}
