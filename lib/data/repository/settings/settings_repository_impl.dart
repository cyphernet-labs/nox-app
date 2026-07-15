import 'package:flutter/material.dart' show ThemeMode;
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/settings/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local settings store (theme + notifications) over shared_preferences — no backend
/// (storage-policy: fully-open, non-sensitive preferences). Reads coerce a
/// missing/unrecognized value to the default (never an error, FR-005); writes run
/// through [execute] so a failure returns a RepositoryResult.error the UI can surface.
@LazySingleton(as: SettingsRepository, env: [Environment.dev, Environment.prod, Environment.test])
class SettingsRepositoryImpl with BaseRepositoryHelper implements SettingsRepository {
  SettingsRepositoryImpl(this._prefs);

  final SharedPreferences _prefs;

  static const String _kThemeMode = 'settings.theme_mode';
  static const String _kNotificationsEnabled = 'settings.notifications_enabled';

  @override
  Future<RepositoryResult<ThemeMode>> readThemeMode() {
    return execute<ThemeMode>(() async {
      final name = _prefs.getString(_kThemeMode);
      final mode = ThemeMode.values.firstWhere((m) => m.name == name, orElse: () => ThemeMode.system);
      return RepositoryResult<ThemeMode>.success(data: mode);
    });
  }

  @override
  Future<RepositoryResult<bool>> setThemeMode(ThemeMode mode) {
    return execute<bool>(() async {
      await _prefs.setString(_kThemeMode, mode.name);
      return const RepositoryResult<bool>.success(data: true);
    });
  }

  @override
  Future<RepositoryResult<bool>> readNotificationsEnabled() {
    return execute<bool>(() async {
      return RepositoryResult<bool>.success(data: _prefs.getBool(_kNotificationsEnabled) ?? true);
    });
  }

  @override
  Future<RepositoryResult<bool>> setNotificationsEnabled(bool enabled) {
    return execute<bool>(() async {
      await _prefs.setBool(_kNotificationsEnabled, enabled);
      return const RepositoryResult<bool>.success(data: true);
    });
  }
}
