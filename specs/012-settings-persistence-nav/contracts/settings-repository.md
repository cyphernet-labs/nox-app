# Contract: SettingsRepository

Доменный контракт локального стора настроек (no backend). Реализация — `shared_preferences`.

```dart
abstract class SettingsRepository {
  // Theme
  Future<RepositoryResult<ThemeMode>> readThemeMode();          // дефолт system при отсутствии/повреждении
  Future<RepositoryResult<void>> setThemeMode(ThemeMode mode);  // error → RepositoryResult.error + LogRepository

  // Notifications
  Future<RepositoryResult<bool>> readNotificationsEnabled();    // дефолт true
  Future<RepositoryResult<void>> setNotificationsEnabled(bool enabled);
}
```

- Регистрация: `@LazySingleton(as: SettingsRepository, env: [Environment.dev, Environment.prod, Environment.test])`.
- Ошибки чтения повреждённого значения НЕ пробрасываются как error — молча дефолт (FR-005).
- Ошибки записи → `RepositoryResult.error(RepositoryException.unknown)` (+ лог); UI показывает inline-error и откатывает контрол.
- Тест-env: тот же impl поверх `SharedPreferences.setMockInitialValues({})`; форс-ошибка записи — через `mockito`-мок репозитория (`getIt.allowReassignment`).

## Acceptance

- FR-001/FR-003/FR-004/FR-005 (persist + defaults + corrupt-safe), FR-006 (write-error surfacing).
