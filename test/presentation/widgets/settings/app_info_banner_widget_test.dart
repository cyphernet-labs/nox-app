import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/presentation/widgets/settings/app_info_banner_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  testWidgets('renders the message + action and fires onAction', (tester) async {
    var tapped = false;
    await pumpApp(
      tester,
      AppInfoBannerWidget(
        icon: NoxIcons.error,
        message: 'Notifications are off.',
        actionLabel: 'Open settings',
        onAction: () => tapped = true,
      ),
    );

    expect(find.text('Notifications are off.'), findsOneWidget);

    await tester.tap(find.text('Open settings'));
    expect(tapped, isTrue);
  });
}
