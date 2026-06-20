import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/shell/app_list_detail_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  group('AppListDetailWidget', () {
    testWidgets('lays out a fixed-width list pane and an expanded detail pane', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(
        tester,
        const AppListDetailWidget(
          listPaneWidth: 360,
          listPane: Center(key: Key('listPane'), child: Text('list')),
          detailPane: Center(key: Key('detailPane'), child: Text('detail')),
        ),
      );

      expect(find.text('list'), findsOneWidget);
      expect(find.text('detail'), findsOneWidget);
      expect(find.byType(VerticalDivider), findsOneWidget);
      // List pane is pinned to listPaneWidth; detail pane takes the rest.
      expect(tester.getSize(find.byKey(const Key('listPane'))).width, 360);
      expect(tester.getSize(find.byKey(const Key('detailPane'))).width, greaterThan(360));
    });

    testWidgets('AppDetailEmptyWidget renders the no-selection title and message', (tester) async {
      await pumpApp(tester, const AppDetailEmptyWidget(title: 'Select a chat', message: 'Choose a conversation on the left.'));

      expect(find.text('Select a chat'), findsOneWidget);
      expect(find.text('Choose a conversation on the left.'), findsOneWidget);
    });
  });
}
