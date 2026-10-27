---
description: "Task list — settings persistence + onboarding navigation (mocks)"
---

# Tasks: Персистентность настроек и реальная навигация онбординга

**Prerequisites**: spec.md, plan.md, data-model.md, contracts/{settings-repository,onboarding-navigation}.md, quickstart.md
**Tests**: включены (persist/inline-error/навигация — ядро; blueprint-гейт).

## Phase 1: Setup

- [x] T001 Добавить l10n-строку `settingsSaveError` (EN `Could not save. Try again.`, UK перевод) в `lib/l10n/app_en.arb` + `app_uk.arb`; `make generate` (gen-l10n).

## Phase 2: Foundational — SettingsRepository (blocking US1/US3)

- [x] T002 Доменный контракт `lib/domain/repository/settings/settings_repository.dart` (readThemeMode/setThemeMode/readNotificationsEnabled/setNotificationsEnabled → `RepositoryResult`), по `contracts/settings-repository.md`.
- [x] T003 Data-impl `lib/data/repository/settings/settings_repository_impl.dart` на `shared_preferences`, `@LazySingleton(as: SettingsRepository, env: [dev,prod,test])`; дефолты + corrupt-safe чтение; ошибки записи → `RepositoryResult.error` + LogRepository. `make generate` (DI).
- [x] T004 [P] (опц.) alias `settingsRepository` в `lib/di/global_aliases.dart`.
- [x] T005 Unit/bloc-тест репозитория `test/data/repository/settings/settings_repository_impl_test.dart`: persist round-trip (theme/notifications), дефолты при отсутствии, откат к дефолту при повреждённом значении, write-error путь (mockito). Без `@Tags`.

**Checkpoint**: локальный стор настроек готов и покрыт.

## Phase 3: User Story 1 — Persistence (P1)

- [x] T006 [US1] `AppRootBloc`: в `_onInitialize` читать сохранённую тему через `SettingsRepository` (дефолт system); в `_onSetTheme` — персистить; при ошибке — оставить прежнюю тему + сигнал inline-error (US3).
- [x] T007 [US1] `AppRootBloc`-тест: стартовая тема из стора; `SetTheme` персистит; невалидное сохранённое → system.
- [x] T008 [US1] `NotificationsBody`: заменить in-memory `_enabled` на чтение/запись через `SettingsRepository` (оптимистичный тумблер).
- [x] T009 [US1] Widget-тест уведомлений: тумблер сохраняется и восстанавливается (пересоздание body с сид-значением в сторе).
- [x] T010 [P] [US1] Verify: язык уже персистится `LocaleController` (l10n) — добавить/подтвердить тест восстановления языка (регрессионный).

**Checkpoint**: все три настройки переживают «перезапуск».

## Phase 4: User Story 3 — Inline-error (P2)

- [x] T011 [US3] Показ `settingsSaveError`-snackbar + откат контрола при ошибке сохранения — тема (AppRoot listener) и уведомления (NotificationsBody). Через существующий `showAppSnackBar` + `context.l10n.settingsSaveError`.
- [x] T012 [US3] Тест inline-error: форс write-error (mockito `SettingsRepository`) → snackbar показан, контрол отражает прежнее значение.

**Checkpoint**: сбой сохранения виден и безопасен.

## Phase 5: User Story 2 — Onboarding navigation (P1)

- [x] T013 [US2] `login_page._onStatus`: заменить `RoutePlaceholderPage.push` (navNewId → 2.3, navRegistered → 4.1) на смену app-state через spine (`AuthRepository`/`AppStateRepository` → `registrationPending`/`authorized`), которую `AppRoot` превращает в подмену роута. Проверить, что login-BLoC реально обновляет сессию/app-state (иначе — доработать BLoC/репозиторий).
- [x] T014 [US2] `set_username_page._onStatus`: заменить `RoutePlaceholderPage.push` (navSuccess → 4.1) на app-state → `authorized`.
- [x] T015 [US2] Навигационные тесты: `2.1 → 2.3` (новый id), `2.3 → 4.1` (успех), `2.1 ↔ 2.2` (QR back сохраняет id). Через смонтированный `AppRoot`/app-state spine или прямую проверку триггеров.
- [x] T016 [P] [US2] Убедиться, что `create_chat_page`/`splash_page` `RoutePlaceholderPage` НЕ затронуты (вне scope).

**Checkpoint**: онбординг проходит реальными переходами без заглушек.

## Phase 6: Polish & Gates

- [x] T017 [P] Goldens: если визуал экранов не изменился (EN идентичен) — новых baseline не нужно; при изменении — обновить/добавить по правилам (widget/page-mobile/page-desktop). Inline-error — поведенчески.
- [x] T018 Формат изменённых файлов (`fvm dart format -l 140 <paths>`), `make gate`, `make golden-verify` — зелёные.
- [x] T019 Пройти `quickstart.md` DoD (FR-001..FR-012, SC-001..SC-006), парити mobile/desktop.

## Dependencies

- Setup (T001) → Foundational (T002–T005) → US1 (T006–T010) / US3 (T011–T012, зависит от T006/T008) / US2 (T013–T016, независим от settings) → Polish (T017–T019).
- US2 не зависит от settings-стора → может идти параллельно US1/US3.
