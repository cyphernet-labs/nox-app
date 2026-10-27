import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/settings/settings_repository.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/notifications_page/notifications_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

/// Settings store whose reads succeed but whose writes always fail — exercises the
/// optimistic-revert + save-error notice path (US3 / FR-006).
class _WriteFailingSettingsRepository implements SettingsRepository {
  @override
  Future<RepositoryResult<ThemeMode>> readThemeMode() async => const RepositoryResult.success(data: ThemeMode.system);

  @override
  Future<RepositoryResult<bool>> setThemeMode(ThemeMode mode) async => const RepositoryResult.error(exception: RepositoryException.unknown);

  @override
  Future<RepositoryResult<bool>> readNotificationsEnabled() async => const RepositoryResult.success(data: true);

  @override
  Future<RepositoryResult<bool>> setNotificationsEnabled(bool enabled) async =>
      const RepositoryResult.error(exception: RepositoryException.unknown);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    getIt.allowReassignment = true;
    getIt.registerSingleton<SettingsRepository>(_WriteFailingSettingsRepository());
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('a failed save reverts the switch and shows the save-error notice', (tester) async {
    await pumpApp(tester, const NotificationsPage());

    final switchFinder = find.byType(Switch);
    expect(tester.widget<Switch>(switchFinder).value, isTrue); // starts enabled (read ok)

    await tester.tap(switchFinder); // toggle off → write fails
    await tester.pumpAndSettle();

    expect(find.text(l10nEn.settingsSaveError), findsOneWidget); // the notice is shown
    expect(tester.widget<Switch>(switchFinder).value, isTrue); // and the switch reverted
  });
}
