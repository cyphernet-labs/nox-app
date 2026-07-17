import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/remote/api/chat/get_chat_files_api.dart';
import 'package:nox_app/domain/model/file/file_type.dart';

void main() {
  final api = GetChatFilesApi();

  test('returns an empty list for the empty-state carve-out chat id', () async {
    final files = await api.execute(chatId: 'chat_empty');

    expect(files, isEmpty);
  });

  test('returns the fixed set of 8 attachments for any other chat id', () async {
    final files = await api.execute(chatId: 'chat_1');

    expect(files, hasLength(8));
    expect(files.map((f) => f.id).toList(), ['f0', 'f1', 'f2', 'f3', 'f4', 'f5', 'f6', 'f7']);
  });

  test('covers every non-other FileType branch across the attachment set', () async {
    final files = await api.execute(chatId: 'chat_1');

    expect(files.map((f) => f.type).toSet(), {
      FileType.pdf,
      FileType.image,
      FileType.sheet,
      FileType.archive,
      FileType.audio,
      FileType.doc,
      FileType.video,
      FileType.text,
    });
  });

  test('includes the intentionally long attachment name that should truncate', () async {
    final files = await api.execute(chatId: 'chat_1');

    expect(files.any((f) => f.name == 'a-rather-long-attachment-name-that-should-truncate.docx'), isTrue);
  });
}
