@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/presentation/pages/file_view_page/file_view_page.dart';

import '../../../utils/golden.dart';

void main() {
  // Golden surface is the mobile design width; the desktop lightbox is covered by a
  // wide-surface widget test. settle: true lets the fake download finish (Loaded).
  goldenTest(
    'file_view_page',
    () => const FileViewPage(
      file: MessageAttachment(id: 'f', type: FileType.pdf, name: 'design-spec.pdf', sizeBytes: 2516582),
    ),
  );
}
