import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/file/attachment_transfer.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/widgets/chat/app_file_chip_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/file_type.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  group('AppFileChipWidget', () {
    testWidgets('renders name and size', (tester) async {
      await pumpApp(tester, const AppFileChipWidget(type: FileType.pdf, name: 'report.pdf', size: '2.4 MB'));

      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.text('2.4 MB'), findsOneWidget);
    });

    testWidgets('shows a remove action only when removable, and fires onRemove', (tester) async {
      await pumpApp(tester, const AppFileChipWidget(type: FileType.pdf, name: 'a.pdf', size: '1 KB'));
      expect(find.byType(IconButton), findsNothing);

      var removed = 0;
      await pumpApp(tester, AppFileChipWidget(type: FileType.pdf, name: 'a.pdf', size: '1 KB', removable: true, onRemove: () => removed++));
      expect(find.byType(IconButton), findsOneWidget);
      await tester.tap(find.byType(IconButton));
      expect(removed, 1);
    });

    testWidgets('while its bytes are being sent, the size line is the progress over a bar', (tester) async {
      // The same pair the file view uses for a download: words, then a bar.
      await pumpApp(
        tester,
        const AppFileChipWidget(
          type: FileType.pdf,
          name: 'report.pdf',
          size: '2.4 MB',
          inBubble: true,
          transfer: AttachmentTransfer(direction: TransferDirection.upload, fraction: 0.456),
        ),
        settle: false,
      );

      expect(find.text(l10nEn.transferSendingProgress(45)), findsOneWidget);
      expect(find.text('2.4 MB'), findsNothing);
      expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0.456);
    });

    testWidgets('before the first byte moves it says so, over a bar that does not pretend to know how far', (tester) async {
      await pumpApp(
        tester,
        const AppFileChipWidget(
          type: FileType.pdf,
          name: 'report.pdf',
          size: '2.4 MB',
          transfer: AttachmentTransfer(direction: TransferDirection.upload),
        ),
        settle: false,
      );

      expect(find.text(l10nEn.transferSending), findsOneWidget);
      expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, isNull);
    });

    testWidgets('with nothing moving there is no bar', (tester) async {
      await pumpApp(tester, const AppFileChipWidget(type: FileType.pdf, name: 'report.pdf', size: '2.4 MB'));

      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('renders the in-bubble variant with the bubble text color applied to the name', (tester) async {
      const onColor = Color(0xFF112233);
      await pumpApp(tester, const AppFileChipWidget(type: FileType.pdf, name: 'doc.pdf', size: '3.1 MB', inBubble: true, onColor: onColor));

      expect(find.text('doc.pdf'), findsOneWidget);
      expect(find.text('3.1 MB'), findsOneWidget);

      final name = tester.widget<Text>(find.text('doc.pdf'));
      expect(name.style?.color, onColor);
    });
  });
}
