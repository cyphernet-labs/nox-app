import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/settings/app_settings_group_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  group('AppSettingsGroupWidget', () {
    testWidgets('renders a single child with no divider', (tester) async {
      await pumpApp(tester, const AppSettingsGroupWidget(children: [SizedBox(key: Key('row-0'))]));

      expect(find.byKey(const Key('row-0')), findsOneWidget);
      expect(find.byType(Divider), findsNothing);
    });

    testWidgets('inserts a single divider between two children', (tester) async {
      await pumpApp(
        tester,
        const AppSettingsGroupWidget(
          children: [
            SizedBox(key: Key('row-0')),
            SizedBox(key: Key('row-1')),
          ],
        ),
      );

      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('inserts a divider between each pair but never at the edges (three children -> two dividers)', (tester) async {
      await pumpApp(
        tester,
        const AppSettingsGroupWidget(
          children: [
            SizedBox(key: Key('row-0')),
            SizedBox(key: Key('row-1')),
            SizedBox(key: Key('row-2')),
          ],
        ),
      );

      expect(find.byType(Divider), findsNWidgets(2));
      expect(find.byKey(const Key('row-0')), findsOneWidget);
      expect(find.byKey(const Key('row-1')), findsOneWidget);
      expect(find.byKey(const Key('row-2')), findsOneWidget);
    });

    testWidgets('wraps the children in a single rounded Card', (tester) async {
      await pumpApp(tester, const AppSettingsGroupWidget(children: [SizedBox(key: Key('row-0'))]));

      expect(find.byType(Card), findsOneWidget);
      final card = tester.widget<Card>(find.byType(Card));
      expect(card.shape, isA<RoundedRectangleBorder>());
      expect(find.descendant(of: find.byType(Card), matching: find.byKey(const Key('row-0'))), findsOneWidget);
    });
  });
}
