@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/presentation/pages/notifications_page/notifications_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/golden.dart';

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

  // Default (granted) state — the denied banner is covered by the widget test.
  goldenTest('notifications_page', () => const NotificationsPage());
  goldenTestDesktop('notifications_page', () => const NotificationsPage());
}
