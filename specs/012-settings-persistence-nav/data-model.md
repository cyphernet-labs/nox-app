# Data Model: Персистентность настроек

## SettingsPreferences (domain, Freezed)

Локальные пользовательские предпочтения. Не sensitive → `shared_preferences`.

| Поле | Тип | Дефолт | Ключ (prefs) | Валидация |
|---|---|---|---|---|
| `themeMode` | `ThemeMode` (system/light/dark) | `system` | `settings_theme_mode` | неизвестное имя → `system` |
| `notificationsEnabled` | `bool` | `true` | `settings_notifications_enabled` | отсутствует → `true` |
| `language` (уже есть) | `AppLanguage` | `system` | `ui_language` (LocaleController) | вне scope этой сущности |

Сериализация: enum → `.name`-строка; bool → bool. Чтение повреждённого значения → дефолт (FR-005).

## Взаимодействие

- `AppRootBloc` — источник истины `themeMode` для UI; читает стартовое значение из `SettingsRepository`, пишет при `SetTheme`.
- `NotificationsBody` — читает/пишет `notificationsEnabled` через `SettingsRepository`.
- `LocaleController` — владеет `language` (персист уже есть).

Никаких серверных сущностей: всё локально, backend TBD (вне scope).
