import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/shell/app_window_titlebar_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  testWidgets('AppWindowTitlebarWidget renders the NOX wordmark and the subtitle', (tester) async {
    await pumpApp(tester, const AppWindowTitlebarWidget(subtitle: 'Sign in'));

    expect(find.text('NOX'), findsOneWidget); // styled wordmark
    expect(find.textContaining('Sign in'), findsOneWidget); // subtitle
  });
}
