import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/repository/settings/settings_repository_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<SettingsRepositoryImpl> repoWith(Map<String, Object> seed) async {
    SharedPreferences.setMockInitialValues(seed);
    return SettingsRepositoryImpl(await SharedPreferences.getInstance());
  }

  group('SettingsRepositoryImpl', () {
    test('theme defaults to system when nothing is stored', () async {
      final repo = await repoWith({});
      expect((await repo.readThemeMode()).data, ThemeMode.system);
    });

    test('theme round-trips through the store', () async {
      final repo = await repoWith({});
      await repo.setThemeMode(ThemeMode.dark);
      expect((await repo.readThemeMode()).data, ThemeMode.dark);
    });

    test('an unrecognized stored theme falls back to system (corrupt-safe)', () async {
      final repo = await repoWith({'settings.theme_mode': 'plasma'});
      expect((await repo.readThemeMode()).data, ThemeMode.system);
    });

    test('notifications default to enabled when nothing is stored', () async {
      final repo = await repoWith({});
      expect((await repo.readNotificationsEnabled()).data, isTrue);
    });

    test('notifications round-trip through the store', () async {
      final repo = await repoWith({});
      await repo.setNotificationsEnabled(false);
      expect((await repo.readNotificationsEnabled()).data, isFalse);
    });
  });
}
