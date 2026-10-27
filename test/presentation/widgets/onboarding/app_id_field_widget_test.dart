import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_id_field_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  testWidgets('Paste is disabled when the clipboard is empty', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await pumpApp(tester, AppIdFieldWidget(controller: controller, canPaste: false, onPaste: () {}));

    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
  });

  testWidgets('Paste fires onPaste when the clipboard has text', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var pasted = false;

    await pumpApp(tester, AppIdFieldWidget(controller: controller, canPaste: true, onPaste: () => pasted = true));

    await tester.tap(find.byType(IconButton));
    expect(pasted, isTrue);
  });

  testWidgets('forwards onChanged and accepts any input', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    String? last;

    await pumpApp(tester, AppIdFieldWidget(controller: controller, canPaste: false, onPaste: () {}, onChanged: (value) => last = value));

    await tester.enterText(find.byType(TextField), 'NOX-id-123 with spaces');
    expect(last, 'NOX-id-123 with spaces');
  });
}
