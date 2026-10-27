# Contract: Navigation & shell coordination

UI-контракт переходов и координации shell ↔ страницы.

## Аккаунт-аватар → Settings / Account

**Триггер:** тап по аккаунт-аватару в desktop-rail.

**Эффект (в `TabBarShell`):**
1. `setState(_active = AppTab.settings)` — переключить активный destination.
2. `_settingsJumpToAccount.value++` — бамп сигнала.

**Приём (в `SettingsRootPage`):** слушает `jumpToAccount` (`ValueListenable<int>?`); по бампу `setState(_selected = _Section.account)` (desktop) / гарантирует показ identity-карточки (mobile корень). Идемпотентно; на первом заходе избыточно (дефолт уже `account`), но покрывает сохранённое состояние вкладки.

**Контракт-тест (widget):** на широкой поверхности тап аватара в смонтированном `TabBarShell` → активна вкладка `Settings` И видна секция `Account` (`Your ID` / identity-карточка), даже если до этого была выбрана другая секция.

## Row tap (parity — без изменений)

| Вёрстка | Действие | Эффект |
|---|---|---|
| mobile (`_narrow`) | тап по строке | `Navigator.push(ChatThreadPage.route(chat))` (5.2) |
| desktop (`_wide`) | тап по строке | `ChatsListEvent.chatSelected(id)` — выбор без push; подсветка + тред в detail-панели |

**Инвариант desktop:** выбор строки НЕ делает navigation push (`ChatThreadPage` не появляется в дереве; `AppThreadViewWidget` рендерится в панели). Уже покрыто `chats_list_page_test.dart` — сохранить зелёным.

## Прочие переходы (без изменений)

- `+` (FAB mobile / leading rail desktop) → `CreateChatPage.route()` (6.1).
- `Search` → live-фильтрация списка; нет совпадений → `No chats found`.
- Ре-тап активной вкладки `Chats` → `scrollToTop` бамп (скролл вверх).

## Acceptance

- FR-010 (Settings → Account), FR-012/FR-013 (parity), spec US3 сценарий 3.
