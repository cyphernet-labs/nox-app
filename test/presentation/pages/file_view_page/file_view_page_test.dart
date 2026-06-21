import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/pages/file_view_page/file_view_page.dart';
import 'package:nox_app/presentation/widgets/primitives/app_file_glyph_widget.dart';

import '../../../utils/pump_app.dart';

const _file = MessageAttachment(id: 'f', type: FileType.pdf, name: 'design-spec.pdf', sizeBytes: 2516582);

void main() {
  group('FileViewPage (mobile)', () {
    testWidgets('shows the file glyph, name and size after the download finishes', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const FileViewPage(file: _file)); // settles the fake download timer

      expect(find.byType(AppFileGlyphWidget), findsOneWidget);
      expect(find.text('design-spec.pdf'), findsWidgets);
      expect(find.textContaining('MB'), findsWidgets);
    });

    testWidgets('Save shows the saved-to-downloads snackbar', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const FileViewPage(file: _file));

      await tester.tap(find.byTooltip(TextConstants.tooltipSave));
      await tester.pump();

      expect(find.text(TextConstants.savedToDownloads), findsOneWidget);
    });
  });

  group('FileViewPage (desktop lightbox)', () {
    testWidgets('renders a centered lightbox with a Download action', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const FileViewPage(file: _file));

      expect(find.byType(AppFileGlyphWidget), findsOneWidget);
      expect(find.widgetWithText(FilledButton, TextConstants.actionDownload), findsOneWidget);
    });
  });
}
