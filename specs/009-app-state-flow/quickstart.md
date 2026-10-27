# Quickstart: проверка App-state flow

**Feature**: `009-app-state-flow` | **Phase**: 1

Runnable-сценарии, доказывающие, что spine работает end-to-end. Детали интерфейсов — в `contracts/`, модель — в `data-model.md`. Здесь — как запустить и что ожидать. Реализация — в `tasks.md`.

## Предусловия

- FVM-Flutter `3.44.1`; `make deps`.
- macOS: в `macos/Runner/*.entitlements` добавлен `keychain-access-groups` (иначе `flutter_secure_storage` бросит на macOS).
- Кодоген прогнан: `make generate` (freezed для `AppStateModel`/`SessionModel`/`AppRootState`/`AppRootEvent` + injectable для новых repo/модуля).

## Сборка/прогон

```bash
make gate                                   # generate → format → analyze → test (goldens исключены)
fvm flutter run --dart-define-from-file=config/stage.json          # mobile
fvm flutter run --dart-define-from-file=config/stage.json -d macos # desktop (явное устройство)
```

## Сценарий 1 — Cold-start резолюция (US1, SC-001/SC-002/SC-007)

1. Свежая установка (хранилище пусто) → запуск.
2. **Ожидание**: проигрывается reveal-анимация Splash (брендовый тёмный canvas), затем открывается **Login (2.1)**. Launcher/галерея не показываются. Навигация не происходит до завершения анимации.
3. Отключить сеть и повторить → поведение идентично (резолюция cache-only, SC-007).

## Сценарий 2 — Sign-in → правильный экран + немедленный переход (US2, SC-009)

1. На Login ввести `newid` (любой не из `registeredIds`) → `Sign in`.
   - **Ожидание**: переход на **Set username (2.3)**; «назад» не возвращает на Login (стек обнулён).
2. Завершить `Set username` (`Done`).
   - **Ожидание**: переход на **Chats shell (4.1)**.
3. Logout (Settings → `Log out` → подтвердить) → на Login ввести `registered` → `Sign in`.
   - **Ожидание**: сразу **Chats shell (4.1)** (registered-set → `authorized`), минуя 2.3.

## Сценарий 3 — Переживание перезапуска (US1, SC-004)

1. Находясь в `authorized` (Chats), убить и перезапустить приложение.
   - **Ожидание**: после Splash открывается **Chats**, не Login.
2. В состоянии `registrationPending` (ввели new id, но не прошли 2.3) убить/перезапустить.
   - **Ожидание**: после Splash открывается **Set username (2.3)**.

## Сценарий 4 — Logout: полный wipe (US2, SC-005)

1. В `authorized` → `Log out` → подтвердить.
   - **Ожидание**: переход на **Login**; в secure storage и SharedPreferences не осталось `session.*`-ключей; повторный cold-start → Login.

## Сценарий 5 — sessionExpired one-shot (US3, SC-006)

1. Вызвать программный/dev `forceLogout` (`authRepository.logout(forced: true)`) из установленной сессии.
   - **Ожидание**: переход на **Login** + **один раз** snackbar `Your session expired`; при дальнейших переходах сообщение не повторяется.
2. Обычный `Log out` → Login **без** сообщения.

## Сценарий 6 — Галерея как dev-вход цела (SC-008)

1. Открыть dev-affordance (`kDebugMode`) → `ScreensGalleryPage`.
   - **Ожидание**: каждый экран (Splash/Login/Set username/Chats/Settings/Error) открывается в demo-режиме как раньше; demo-переходы не пишут в реальное хранилище и не дёргают spine.
2. `make gate` зелёный.

## Автотесты (привязка)

| Уровень | Что проверяет | Файл (целевой) |
|---|---|---|
| unit | резолюция всех веток + fail-safe | `test/data/repository/app/app_state_repository_impl_test.dart` |
| unit | save/read/clear сессии | `test/data/repository/app/session_repository_impl_test.dart` |
| unit | signIn registered/new, logout forced/ordinary | `test/data/repository/app/auth_repository_impl_test.dart` |
| bloc | двухфазное применение (`updateAppState`/`applyAppState`/`isReady`) | `test/presentation/app/bloc/app_root_bloc_test.dart` |
| widget | state→экран (`pushReplacement`/`pushAndRemoveUntil`), sessionExpired snackbar один раз | `test/presentation/app/app_root_test.dart` |

mockito подменяет `SessionRepository`/secure-storage; прочее — против test-env DI (`Environment.test`). Goldens не затрагиваются.
