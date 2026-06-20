import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/chat/app_file_chip_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/file_type.dart';

import '../../../utils/pump_app.dart';

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
