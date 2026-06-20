import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/pages/notifications_page/notifications_page.dart';
import 'package:nox_app/presentation/widgets/settings/app_info_banner_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  testWidgets('push switch is on by default with no permission banner', (tester) async {
    await pumpApp(tester, const NotificationsPage());

    expect(find.text(TextConstants.notificationsPushTitle), findsOneWidget);
    expect(find.byType(AppInfoBannerWidget), findsNothing);

    final row = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(row.value, isTrue);
  });

  testWidgets('denied permission shows the banner and disables the switch', (tester) async {
    await pumpApp(tester, const NotificationsPage());

    await tester.tap(find.text('Denied')); // dev permission control
    await tester.pump();

    expect(find.byType(AppInfoBannerWidget), findsOneWidget);
    final row = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(row.value, isFalse);
    expect(row.onChanged, isNull);
  });
}
