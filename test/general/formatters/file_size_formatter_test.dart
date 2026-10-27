import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/formatters/file_size_formatter.dart';

void main() {
  group('FileSizeFormatter.format', () {
    test('bytes below 1 KB render as integral bytes', () {
      expect(FileSizeFormatter.format(0), '0 B');
      expect(FileSizeFormatter.format(1), '1 B');
      expect(FileSizeFormatter.format(1023), '1023 B');
    });

    test('rolls up to KB / MB / GB with one fraction digit', () {
      expect(FileSizeFormatter.format(1024), '1.0 KB');
      expect(FileSizeFormatter.format(48211), '47.1 KB');
      expect(FileSizeFormatter.format(2516582), '2.4 MB');
      expect(FileSizeFormatter.format(18874368), '18.0 MB');
      expect(FileSizeFormatter.format(64487424), '61.5 MB');
    });

    test('a value that rounds to 1024 rolls up to the next unit (no "1,024.0 KB")', () {
      // 1048575 B = 1023.999 KB → must render as 1.0 MB, not 1,024.0 KB.
      expect(FileSizeFormatter.format(1048575), '1.0 MB');
    });
  });
}
