import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/file/file_type.dart';

void main() {
  group('FileType.fromExtension', () {
    test('maps each class from a representative extension', () {
      expect(FileType.fromExtension('jpg'), FileType.image);
      expect(FileType.fromExtension('png'), FileType.image);
      expect(FileType.fromExtension('mp4'), FileType.video);
      expect(FileType.fromExtension('mp3'), FileType.audio);
      expect(FileType.fromExtension('pdf'), FileType.pdf);
      expect(FileType.fromExtension('docx'), FileType.doc);
      expect(FileType.fromExtension('xlsx'), FileType.sheet);
      expect(FileType.fromExtension('csv'), FileType.sheet);
      expect(FileType.fromExtension('md'), FileType.text);
      expect(FileType.fromExtension('zip'), FileType.archive);
      expect(FileType.fromExtension('gz'), FileType.archive);
    });

    test('is case-insensitive', () {
      expect(FileType.fromExtension('PDF'), FileType.pdf);
      expect(FileType.fromExtension('JPEG'), FileType.image);
      expect(FileType.fromExtension('Mp4'), FileType.video);
    });

    test('an unknown, empty, or null extension falls back to other', () {
      expect(FileType.fromExtension('xyz'), FileType.other);
      expect(FileType.fromExtension('exe'), FileType.other);
      expect(FileType.fromExtension(''), FileType.other);
      expect(FileType.fromExtension(null), FileType.other);
    });
  });
}
