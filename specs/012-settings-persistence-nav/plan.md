# Implementation Plan: Персистентность настроек и реальная навигация онбординга

**Branch**: `012-settings-persistence-nav` | **Date**: 2026-07-18 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/012-settings-persistence-nav/spec.md`

## Summary

Добавляем локальную персистентность настроек (тема + уведомления; язык уже персистится `LocaleController`) через новый доменный `SettingsRepository` поверх `shared_preferences`, с оптимистичным UI и inline-error `Could not save. Try again.` при сбое сохранения. Заменяем `RoutePlaceholderPage`-заглушки онбординга реальной навигацией через существующий app-state spine (009): `2.1 → 2.3` (новый id) и `2.3 → 4.1` (успех) — сменой app-state, `2.1 ↔ 2.2` (QR) — push/pop. Всё на моках, без бэкенда; парити mobile/desktop.

## Technical Context

**Language/Version**: Dart `>=3.12 <4.0`, Flutter 3.44.1 (FVM)
**Primary Dependencies**: `shared_preferences` (есть), `flutter_bloc`/Freezed, `injectable`+`get_it`, existing `AppStateRepository`/`AppRootBloc`/`LocaleController`
**Storage**: `shared_preferences` (локальные, не sensitive настройки — storage-policy). Идентификатор — `flutter_secure_storage` (вне scope)
**Testing**: `flutter_test`, `bloc_test`, golden (`goldenTest`/`goldenTestDesktop`), `mockito`
**Target Platform**: iOS/Android/Windows/Linux/macOS; парити `_narrow`/`_wide`
**Project Type**: single Flutter package `nox_app`
**Constraints**: no backend — мок/локально; blueprint-архитектура (Freezed BLoC для страниц с реальным async/mutable-стейтом, `RepositoryResult<T>`, DI, design-токены)
**Scale/Scope**: 3 настройки + 3 онбординг-перехода + inline-error

## Constitution Check

*GATE: соответствие принципам I–V (constitution v1.1.0).*

- **I. Приватность/E2EE** — PASS: локальные не-sensitive настройки в `shared_preferences`; идентификатор не трогаем; крипто/сеть не затрагиваются.
- **II. Спека — источник истины** — PASS: spec/clarify зафиксированы; расхождений с `docs/design/spec/` (7.2/7.3/7.4 экраны, онбординг 2.x) не вносим; заглушки заменяются согласно уже зафиксированному флоу.
- **III. Архитектурный блюпринт** — PASS: `SettingsRepository` = доменный контракт + data-impl, `RepositoryResult<T>`, DI (`@LazySingleton`), никаких сырых `print` (LogRepository). Никаких новых нативных/desktop-специфичных частей — только cross-platform `shared_preferences`.
- **IV. Дизайн-система** — PASS: UI без хардкода — токены; inline-error через существующий `showAppSnackBar` + l10n-строку `settingsSaveError` (`Could not save. Try again.`). Новых визуалов минимум.
- **V. Языковая дисциплина** — PASS: код/коммиты — EN; спека — RU; UI-микрокопия — EN (l10n EN+UK).

**Итог: PASS.** Complexity Tracking не требуется.

## Project Structure

### Documentation (this feature)

```
specs/012-settings-persistence-nav/
├── spec.md
├── plan.md              # этот файл
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── settings-repository.md
│   └── onboarding-navigation.md
└── checklists/requirements.md
```

### Source Code (repository root)

```
lib/
├── domain/repository/settings/
│   └── settings_repository.dart            # NEW: контракт (watch/read/set theme+notifications)
├── data/repository/settings/
│   └── settings_repository_impl.dart       # NEW: @LazySingleton, shared_preferences
├── domain/model/settings/
│   └── settings_preferences.dart           # NEW: Freezed (themeMode, notificationsEnabled) [+ language опц.]
├── di/global_aliases.dart                  # (опц.) alias settingsRepository
├── presentation/app/bloc/app_root_bloc.dart  # CHANGE: init читает сохранённую тему; _onSetTheme персистит
├── presentation/pages/notifications_page/notifications_body.dart # CHANGE: toggle → SettingsRepository + inline-error
├── presentation/pages/login_page/login_page.dart       # CHANGE: убрать RoutePlaceholder; навигация через app-state spine
├── presentation/pages/set_username_page/set_username_page.dart # CHANGE: убрать RoutePlaceholder; app-state → authorized
├── presentation/pages/appearance_page/appearance_body.dart  # (persist уже через AppRootBloc; проверить)
└── lib/l10n/*.arb                          # NEW string: settingsSaveError = "Could not save. Try again."
```

## Design notes

- **SettingsRepository** — доменный контракт: `Stream<ThemeMode> watchThemeMode()` / `Future<RepositoryResult<void>> setThemeMode(ThemeMode)`, `watchNotificationsEnabled()`/`setNotificationsEnabled(bool)`; читает дефолты при отсутствии/повреждении. Data-impl на `shared_preferences`, `@LazySingleton(as:, env:[dev,prod,test])`, ошибки → `RepositoryResult.error` + LogRepository. (Cache-first-watch допустим через `BehaviorSubject`; для настроек достаточно read+set с локальным нотифаем.)
- **Тема**: `AppRootBloc._onInitialize` читает сохранённую тему (default System); `_onSetTheme` пишет через репозиторий, при ошибке — эмит прежней темы + сигнал inline-error.
- **Уведомления**: `NotificationsBody` переходит с in-memory `_enabled` на чтение/запись через репозиторий (или тонкий Freezed-BLoC, если появляется реальный async/стейт — 05 §5.1); оптимистичный тумблер, откат + snackbar при ошибке.
- **Язык**: уже персистится `LocaleController` (l10n-фича). Опционально маршрутизировать через `SettingsRepository` для единообразия — не обязательно (FR-002 выполнен).
- **Онбординг**: заменяем `RoutePlaceholderPage.push` в `login_page._onStatus` (navNewId/navRegistered) и `set_username_page._onStatus` (navSuccess) на смену app-state (`AuthRepository`/`AppStateRepository` → `registrationPending`/`authorized`), которую `AppRoot` уже превращает в подмену корневого роута (009). `2.1 ↔ 2.2` (QR push/pop) уже работает (010). `create_chat_page`/`splash_page` RoutePlaceholder — вне scope (chat-thread dev-переход / gallery), не трогаем.
- **Inline-error строка**: добавить в ARB `settingsSaveError` (EN `Could not save. Try again.`, UK перевод).

## Complexity Tracking

Нет нарушений Constitution Check — раздел не требуется.
