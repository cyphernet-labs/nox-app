import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/chat/app_segmented_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  group('AppSegmentedWidget', () {
    testWidgets('reports the newly selected value', (tester) async {
      int? picked;
      await pumpApp(
        tester,
        AppSegmentedWidget<int>(options: const {0: 'One', 1: 'Two'}, selected: 0, onChanged: (value) => picked = value),
      );

      await tester.tap(find.text('Two'));
      expect(picked, 1);
    });

    testWidgets('marks the selected segment with the M3 selected-state check icon', (tester) async {
      await pumpApp(tester, AppSegmentedWidget<int>(options: const {0: 'One', 1: 'Two'}, selected: 1, onChanged: (_) {}));

      final button = tester.widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>));
      expect(button.selected, {1});
      // showSelectedIcon renders a check glyph for the active segment, distinguishing it visually.
      expect(button.showSelectedIcon, isTrue);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('does not re-fire onChanged when the already-selected option is tapped', (tester) async {
      var changes = 0;
      await pumpApp(tester, AppSegmentedWidget<int>(options: const {0: 'One', 1: 'Two'}, selected: 0, onChanged: (_) => changes++));

      // Single-select with empty selection disallowed: tapping the active segment is a no-op.
      await tester.tap(find.text('One'));
      expect(changes, 0);
    });
  });
}
