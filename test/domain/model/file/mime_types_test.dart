import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/file/mime_types.dart';

/// Contract §7: the CLIENT derives `mime` from the file name extension via a
/// local table (unknown → application/octet-stream); the picker never reads
/// bytes and the server echoes what uploadBegin was told.
void main() {
  group('extensionOf', () {
    test('returns the extension without the dot, case preserved', () {
      expect(MimeTypes.extensionOf('design-spec.PDF'), 'PDF');
      expect(MimeTypes.extensionOf('archive.tar.gz'), 'gz'); // the LAST segment
    });

    test('a name with no usable extension has none', () {
      expect(MimeTypes.extensionOf('README'), isNull);
      expect(MimeTypes.extensionOf('.gitignore'), isNull); // hidden file, not an extension
      expect(MimeTypes.extensionOf('trailing.'), isNull);
    });
  });

  group('forFileName / forExtension', () {
    test('known extensions map to their contract mime, case-insensitively', () {
      expect(MimeTypes.forFileName('design-spec.pdf'), 'application/pdf');
      expect(MimeTypes.forFileName('SHOT.PNG'), 'image/png');
      expect(MimeTypes.forFileName('clip.mov'), 'video/quicktime');
      expect(MimeTypes.forFileName('notes.md'), 'text/markdown');
      expect(MimeTypes.forExtension('xlsx'), 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    });

    test('an unknown or absent extension falls back to the contract default', () {
      expect(MimeTypes.forFileName('blob.zzz'), MimeTypes.fallback);
      expect(MimeTypes.forFileName('README'), MimeTypes.fallback);
      expect(MimeTypes.forExtension(null), 'application/octet-stream');
    });

    test('every mime is a non-empty type/subtype within the contract 128-char cap', () {
      const names = [
        'a.jpg',
        'a.png',
        'a.gif',
        'a.webp',
        'a.heic',
        'a.bmp',
        'a.svg',
        'a.mp4',
        'a.mov',
        'a.mkv',
        'a.avi',
        'a.webm',
        'a.mp3',
        'a.m4a',
        'a.wav',
        'a.aac',
        'a.flac',
        'a.ogg',
        'a.pdf',
        'a.doc',
        'a.docx',
        'a.odt',
        'a.xls',
        'a.xlsx',
        'a.ods',
        'a.csv',
        'a.txt',
        'a.log',
        'a.md',
        'a.rtf',
        'a.zip',
        'a.rar',
        'a.7z',
        'a.tar',
        'a.gz',
      ];
      for (final name in names) {
        final mime = MimeTypes.forFileName(name);
        expect(mime.trim(), mime, reason: '$name: no padding (the server trims and rejects empties)');
        expect(mime.split('/').length, 2, reason: '$name: type/subtype');
        expect(mime.length, lessThanOrEqualTo(128), reason: '$name: contract §7 cap');
        expect(mime, isNot(MimeTypes.fallback), reason: '$name: the table must actually know it');
      }
    });
  });
}
