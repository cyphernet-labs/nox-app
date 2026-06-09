import 'package:injectable/injectable.dart';
import 'package:intl/intl.dart';
import 'package:nox_app/general/constants.dart';

/// Formats numeric values with locale-aware separators using intl's NumberFormat.
/// Skeleton: fixed default locale. The settings-coupled variant (watching a
/// SettingsRepository for the active locale) arrives with the settings feature.
@lazySingleton
class ValueFormatter {
  ValueFormatter();

  /// Format a number with fixed fraction digits and locale-aware separators.
  String format({required num value, int precision = 2, String? locale}) {
    final formatter = NumberFormat.decimalPatternDigits(
      locale: locale ?? Constants.defaultLocale,
      decimalDigits: precision,
    );
    return formatter.format(value);
  }

  String formatDouble({required double value, int precision = 2, String? locale}) =>
      format(value: value, precision: precision, locale: locale);
}
