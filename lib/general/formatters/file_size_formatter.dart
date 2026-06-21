import 'package:intl/intl.dart';
import 'package:nox_app/general/constants.dart';

/// Formats a byte count as a human-readable size (`B` / `KB` / `MB` / `GB` / `TB`).
/// Used by the file view (5.3), the chat card (5.4) and attachment chips. Bytes are
/// integral; KB and up show one fraction digit with locale-aware separators (intl).
class FileSizeFormatter {
  FileSizeFormatter._();

  static const List<String> _units = ['B', 'KB', 'MB', 'GB', 'TB'];
  static const int _step = 1024;

  static String format(int bytes, {String? locale}) {
    if (bytes < _step) return '$bytes ${_units.first}';
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= _step && unit < _units.length - 1) {
      value /= _step;
      unit++;
    }
    final formatter = NumberFormat.decimalPatternDigits(locale: locale ?? Constants.defaultLocale, decimalDigits: 1);
    return '${formatter.format(value)} ${_units[unit]}';
  }
}
