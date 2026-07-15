# Quickstart / Definition of Done — 012

## Проверка вручную

1. Settings → Appearance: сменить тему → hot-restart → тема сохранилась.
2. Settings → Language: сменить на Українська → hot-restart → язык сохранился (LocaleController, уже есть).
3. Settings → Notifications: выключить → hot-restart → выключено.
4. Login → Scan QR → назад: введённый id сохранён.
5. Login с новым id → попадаем на Set username; завершить → попадаем на Shell (без экранов-заглушек).
6. (Форс) сбой сохранения настройки → snackbar `Could not save. Try again.`, контрол откатился.

## Definition of Done

- FR-001..FR-012 выполнены; SC-001..SC-006 подтверждены.
- `SettingsRepository` (domain+data) на `shared_preferences`, DI, `RepositoryResult`.
- `RoutePlaceholderPage`-заглушки онбординга (login/set_username) удалены; навигация через app-state spine.
- `settingsSaveError` в ARB (EN+UK).
- Тесты: bloc/widget для persist + inline-error + навигации; парити mobile/desktop.
- `make gate` + `make golden-verify` зелёные.
