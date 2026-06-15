import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/shell/app_splash_hairline_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  testWidgets('AppSplashHairlineWidget has a preferred size and renders', (tester) async {
    const widget = AppSplashHairlineWidget();
    expect(widget.preferredSize.height, 3 + 14);

    await pumpApp(tester, const AppSplashHairlineWidget());
    expect(find.byType(AppSplashHairlineWidget), findsOneWidget);
  });
}
