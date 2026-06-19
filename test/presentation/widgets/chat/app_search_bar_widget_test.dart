import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/chat/app_search_bar_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  group('AppSearchBarWidget', () {
    testWidgets('shows the hint when empty and the value when set', (tester) async {
      await pumpApp(tester, const AppSearchBarWidget());
      expect(find.text(TextConstants.searchHint), findsOneWidget);

      await pumpApp(tester, const AppSearchBarWidget(value: 'teal'));
      expect(find.text('teal'), findsOneWidget);
    });

    testWidgets('fires onTap', (tester) async {
      var taps = 0;
      await pumpApp(tester, AppSearchBarWidget(onTap: () => taps++));

      await tester.tap(find.byType(AppSearchBarWidget));
      expect(taps, 1);
    });

    testWidgets('exposes a button role with the search label, independent of the displayed value', (tester) async {
      // The visible value ("teal") differs from the announced label, which stays the hint.
      await pumpApp(tester, const AppSearchBarWidget(value: 'teal'));

      final semantics = tester
          .widgetList<Semantics>(find.descendant(of: find.byType(AppSearchBarWidget), matching: find.byType(Semantics)))
          .firstWhere((s) => s.properties.button ?? false);
      expect(semantics.properties.label, TextConstants.searchHint);
    });
  });
}
