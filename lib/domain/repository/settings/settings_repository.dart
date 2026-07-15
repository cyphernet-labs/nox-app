import 'package:flutter/material.dart' show ThemeMode;
import 'package:nox_app/domain/repository/base/repository_result.dart';

/// Local, non-sensitive user preferences (theme + notifications) persisted on the
/// device — no backend. Reads coerce a missing/unrecognized stored value to the
/// default (never an error), so a corrupt value can't crash startup; writes return
/// a [RepositoryResult] so a save failure surfaces to the UI (inline-error). Language
/// is persisted separately by LocaleController and is out of this contract's scope.
abstract class SettingsRepository {
  /// Stored theme, or [ThemeMode.system] when absent/unrecognized.
  Future<RepositoryResult<ThemeMode>> readThemeMode();

  /// Persist [mode]; error result on a write failure.
  Future<RepositoryResult<bool>> setThemeMode(ThemeMode mode);

  /// Stored notifications toggle, or `true` when absent.
  Future<RepositoryResult<bool>> readNotificationsEnabled();

  /// Persist [enabled]; error result on a write failure.
  Future<RepositoryResult<bool>> setNotificationsEnabled(bool enabled);
}
