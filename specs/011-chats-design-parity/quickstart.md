# Quickstart: валидация Chats list (design parity + golden)

Гайд проверки, что фича работает end-to-end. Детали реализации — в `tasks.md` / коде; здесь — как запустить и что ожидать.

## Предусловия

- FVM-pinned Flutter `3.44.1`; `make deps` выполнен.
- claude_design MCP подключён (`/design-login`) — для пиксельной сверки с `NOX - Mobile.html` / `NOX - Desktop.html` (проект `d9e022e3-07fb-4fae-9147-226210933448`).

## 1. Импорт целевых макетов (источник истины)

Через claude_design MCP импортировать оба файла проекта и держать открытыми как референс при сверке:
- `NOX - Mobile.html` → таргет узкой (`_narrow`) вёрстки.
- `NOX - Desktop.html` → таргет широкой (`_wide`) вёрстки.

## 2. Запуск приложения и визуальная сверка

```bash
# Mobile-вёрстка (узкое окно/симулятор)
fvm flutter run --dart-define-from-file=config/stage.json

# Desktop-вёрстка (широкое окно)
fvm flutter run --dart-define-from-file=config/stage.json -d macos   # | windows | linux
```

Боот идёт в launcher; экран Chats доступен через live-shell. Сверить со светлым и тёмным макетом:

- **Mobile:** wordmark `NOX` + brand-hairline, поле `Search`, строки (аватар+кольцо / имя / превью / время / бейдж), bottom bar (`Chats` / докнутый `+` / `Settings`). Состояния: `filled` / `empty` / `loading` / `offline` / `inline-error` / `search` / `search-empty`.
- **Desktop:** window-titlebar `NOX · Chats` + hairline, rail (`+` / `Chats` / `Settings` + **аккаунт-аватар внизу**), панель списка (заголовок `Chats` + `Search` + строки), detail-панель (`Select a chat` empty-state; при выборе — подсветка строки + тред без push).

## 3. Проверка аккаунт-аватара (desktop)

На широком окне:
1. Внизу rail виден аватар с инициалами текущего label (дефолт `User7421` → `U`).
2. Тап по аватару → активна вкладка `Settings`, показана секция `Account` (`Your ID` / username / `Show QR`).
3. На узком окне (bottom-bar) аватара нет.

Инициалы (ручная проверка/юнит): `john.doe`→`JD`, `User7421`→`U`, `Alice`→`A`.

## 4. Тесты

```bash
# Юнит правила инициалов
make test FILE=test/design/theme/nox_account_initials_test.dart

# Widget/функциональные тесты страницы и rail (без golden)
make test FILE=test/presentation/pages/chats_list_page/chats_list_page_test.dart

# Полный гейт (goldens исключены)
make gate
```

Ожидание: всё зелёное, `flutter analyze` без ошибок, формат `-l 140` чистый.

## 5. Golden-валидация (mobile + desktop)

```bash
# Сгенерировать baseline после правок (Apple Silicon/macOS)
make golden-update FILE=test/presentation/pages/chats_list_page/chats_list_page_golden_test.dart
make golden-update FILE=test/presentation/widgets/shell/app_navigation_rail_widget_golden_test.dart

# Проверить, что baseline соответствуют рендеру
make golden-verify
```

Ожидание:
- Созданы `goldens/chats_list_page_*_{light,dark}.png` (mobile) и `goldens/chats_list_page*_desktop_{light,dark}.png` (desktop), плюс rail-widget golden — см. `contracts/golden-coverage.md`.
- `make golden-verify` зелёный.
- Намеренная регрессия (сдвиг отступа/цвета) ловится `make golden-verify` (SC-005).

## 6. Drift-fix дизайн-корпуса (Принцип II)

Убедиться, что `docs/design/system/nox-desktop-screens/screens/01-chats.md` обновлён: trailing аккаунт-аватар в анатомии rail + поведение перехода в `Settings`/`Account`.

## Definition of Done

- Обе вёрстки совпадают с `NOX - Mobile/Desktop.html` (light+dark) — SC-001/SC-002.
- Аккаунт-аватар: инициалы корректны, тап → Settings/Account (SC-003/SC-004).
- Golden-покрытие в двух категориях зелёное; `make gate` + `make golden-verify` без падений (SC-005/SC-006).
- Desktop-корпус обновлён (Принцип II).
