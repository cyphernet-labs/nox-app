@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/service/notification_permission_service.dart';
import 'package:nox_app/presentation/pages/notifications_page/notifications_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/golden.dart';
import 'notifications_permission_test.mocks.dart';

void main() {
  // NotificationsBody now reads/persists its toggle via SettingsRepository, so the
  // render needs the test-env DI (empty prefs → the default enabled state).
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
  });

  tearDownAll(() async {
    await getIt.reset();
  });

  // Default (granted) state.
  goldenTest('notifications_page', () => const NotificationsPage());
  goldenTestDesktop('notifications_page', () => const NotificationsPage());

  // The OS-denied state had no baseline at all - only a widget test asserting the
  // banner was present - which is how its action could sit left-aligned in the
  // middle of the banner for as long as it did. Driven through the permission
  // service, the thing that actually decides this state.
  group('denied by the OS', () {
    setUp(() {
      final permission = MockNotificationPermissionService();
      when(permission.status()).thenAnswer((_) async => NotificationPermissionStatus.denied);
      when(permission.openSettings()).thenAnswer((_) async {});
      getIt.allowReassignment = true;
      getIt.registerSingleton<NotificationPermissionService>(permission);
    });

    goldenTest('notifications_page_denied', () => const NotificationsPage());
    goldenTestDesktop('notifications_page_denied', () => const NotificationsPage());
  });
}
