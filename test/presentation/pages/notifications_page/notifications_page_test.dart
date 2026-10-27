import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/notifications_page/notifications_page.dart';
import 'package:nox_app/presentation/widgets/settings/app_info_banner_widget.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('push switch is on by default with no permission banner', (tester) async {
    await pumpApp(tester, const NotificationsPage());

    expect(find.text(l10nEn.notificationsPushTitle), findsOneWidget);
    expect(find.byType(AppInfoBannerWidget), findsNothing);

    final row = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(row.value, isTrue);
  });

  // The denied case is covered by notifications_permission_test.dart, which drives it
  // through NotificationPermissionService - the thing that actually decides it. The
  // test that used to live here reached the same state by tapping the dev override,
  // which is no longer part of the product on any flavour.
}
