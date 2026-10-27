import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/shell/app_side_sheet_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  testWidgets('showRightSideSheet slides a panel in and shows its child', (tester) async {
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showRightSideSheet<void>(context, child: const Text('sheet content')),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('sheet content'), findsOneWidget);

    // Dismiss via the barrier so no route is left pending.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('sheet content'), findsNothing);
  });
}
