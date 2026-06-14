import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/nox_icons.dart';

// US3 / FR-011: file-type -> icon mapping covers the design-system.md §8 /
// overview «Файлы» table and defaults to fileOther for unknown types.
void main() {
  test('extension classification', () {
    expect(noxFileTypeFromExtension('photo.PNG'), NoxFileType.image);
    expect(noxFileTypeFromExtension('clip.mp4'), NoxFileType.video);
    expect(noxFileTypeFromExtension('song.flac'), NoxFileType.audio);
    expect(noxFileTypeFromExtension('doc.pdf'), NoxFileType.pdf);
    expect(noxFileTypeFromExtension('report.docx'), NoxFileType.document);
    expect(noxFileTypeFromExtension('data.csv'), NoxFileType.spreadsheet);
    expect(noxFileTypeFromExtension('notes.txt'), NoxFileType.text);
    expect(noxFileTypeFromExtension('bundle.zip'), NoxFileType.archive);
    expect(noxFileTypeFromExtension('weird.xyz'), NoxFileType.other);
    expect(noxFileTypeFromExtension('noext'), NoxFileType.other);
  });

  test('every file type maps to an icon; unknown -> fileOther', () {
    for (final t in NoxFileType.values) {
      expect(noxFileTypeIcon(t), isNotNull);
    }
    expect(noxFileTypeIcon(NoxFileType.other), NoxIcons.fileOther);
    expect(noxFileTypeIcon(NoxFileType.image), NoxIcons.fileImage);
  });
}
