import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/service/notification_permission_service.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/notifications_page/notifications_page.dart';
import 'package:nox_app/presentation/widgets/settings/app_info_banner_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/pump_app.dart';
import 'notifications_permission_test.mocks.dart';

final l10nEn = AppLocalizationsEn();

/// The REAL OS-permission wiring (P5): the 7.2 screen queries [NotificationPermissionService]
/// on open (not a hardcoded `granted`), and the banner's Open settings deep-links through it.
@GenerateMocks([NotificationPermissionService])
void main() {
  late MockNotificationPermissionService permission;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    permission = MockNotificationPermissionService();
    when(permission.openSettings()).thenAnswer((_) async {});
    getIt.allowReassignment = true;
    getIt.registerSingleton<NotificationPermissionService>(permission);
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('a denied OS permission queried on open shows the banner and disables the switch', (tester) async {
    when(permission.status()).thenAnswer((_) async => NotificationPermissionStatus.denied);

    await pumpApp(tester, const NotificationsPage());

    expect(find.byType(AppInfoBannerWidget), findsOneWidget); // no dev-control tap — driven by the service
    final row = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(row.value, isFalse);
    expect(row.onChanged, isNull);
  });

  testWidgets('tapping Open settings deep-links through the permission service', (tester) async {
    when(permission.status()).thenAnswer((_) async => NotificationPermissionStatus.denied);

    await pumpApp(tester, const NotificationsPage());
    await tester.tap(find.text(l10nEn.actionOpenSettings));
    await tester.pump();

    verify(permission.openSettings()).called(1);
  });

  testWidgets('a granted OS permission shows no banner and enables the switch', (tester) async {
    when(permission.status()).thenAnswer((_) async => NotificationPermissionStatus.granted);

    await pumpApp(tester, const NotificationsPage());

    expect(find.byType(AppInfoBannerWidget), findsNothing);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
  });
}
