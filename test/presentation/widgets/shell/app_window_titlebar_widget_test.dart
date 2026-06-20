import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/shell/app_window_titlebar_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  testWidgets('AppWindowTitlebarWidget renders its title', (tester) async {
    await pumpApp(tester, const AppWindowTitlebarWidget(title: 'NOX'));

    expect(find.text('NOX'), findsOneWidget);
  });
}
