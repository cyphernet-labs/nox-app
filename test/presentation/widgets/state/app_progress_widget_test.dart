import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/primitives/app_spinner_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_progress_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  testWidgets('AppProgressWidget centers a spinner', (tester) async {
    await pumpApp(tester, const AppProgressWidget(), settle: false);

    expect(find.byType(AppSpinnerWidget), findsOneWidget);
  });
}
