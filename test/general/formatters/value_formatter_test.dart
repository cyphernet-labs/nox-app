import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/formatters/value_formatter.dart';

void main() {
  group('ValueFormatter.format', () {
    late ValueFormatter formatter;

    setUp(() => formatter = ValueFormatter());

    test('applies the en_US default locale with fixed fraction digits', () {
      expect(formatter.format(value: 1234.5, precision: 2), '1,234.50');
    });

    test('precision zero rounds to an integral, grouped value', () {
      expect(formatter.format(value: 1234.5, precision: 0), '1,235');
    });
  });

  group('ValueFormatter.formatDouble', () {
    late ValueFormatter formatter;

    setUp(() => formatter = ValueFormatter());

    test('delegates to format identically', () {
      expect(formatter.formatDouble(value: 1234.5, precision: 2), '1,234.50');
      expect(formatter.formatDouble(value: 1234.5, precision: 2), formatter.format(value: 1234.5, precision: 2));
    });
  });
}
