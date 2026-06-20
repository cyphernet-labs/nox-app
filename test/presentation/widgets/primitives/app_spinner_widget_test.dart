import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/primitives/app_spinner_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  testWidgets('AppSpinnerWidget shows an indeterminate indicator', (tester) async {
    // settle: false — the indicator animates forever, so pumpAndSettle would time out.
    await pumpApp(tester, const AppSpinnerWidget(), settle: false);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
