# Implementation Plan: Связь восстанавливается без перезапуска приложения

**Branch**: `042-connection-recovery` | **Date**: 2026-10-05 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/042-connection-recovery/spec.md`

## Summary

`Try again` на плашке `No connection` делает то же, что сегодня делает только перезапуск приложения: перезапускает канал — `SessionPhaseService.reconnect()` → `LiveSessionStarter.restart()`, тот же путь, что уже стоит за `Try again` на плашке «чужой сервер». Перезапуск канала заканчивает сессию выбора пути (селектор забывает всё, что держал в памяти, и снимает флаг неудачного круга, так что плашка уступает место «подключаемся») и начинает её заново с прямых адресов. Tor при этом сохраняется, только если он здоров: упавший клиент и клиент, который поднимается дольше бюджета готовности, останавливаются и в новом круге запускаются заново. Перезапуски не наслаиваются: нажатие во время перезапуска присоединяется к нему. Сокет ограничивает выбор пути 120 секундами — зависшее ожидание внутри выбора больше не может остановить попытки навсегда. Плашка получает действие в трёх местах (5.1, 5.2, 5.4) на обеих ширинах, кроме неподдерживаемого сервера. Возврат на передний план и смена сети уже начинают попытку сразу (фаза 040) — здесь это закрепляется тестами.

## Technical Context

**Language/Version**: Dart (Flutter `3.44.1`, FVM).

**Primary Dependencies**: flutter_bloc + freezed, injectable/get_it, rxdart — без новых зависимостей.

**Storage**: не меняется. Сохранённые вердикты (ключ доступа, помеченный незарегистрированным; вердикт сети Tor о версии клиента) не трогаются.

**Testing**: `flutter_test`, `bloc_test`, `mockito`, голдены трёх категорий (`make gate`, `make golden-verify`).

**Target Platform**: iOS, Android, macOS, Windows, Linux. На Linux Tor нет — там перезапуск касается только прямого пути.

**Project Type**: мобильное + десктопное приложение (сервер и контракт не меняются).

**Performance Goals**: новая попытка после `Try again` — меньше 1 с (SC-002); зависший выбор пути брошен не позже 120 с (SC-003).

**Constraints**: живое соединение не рвётся (FR-011); поднимающийся Tor не перезапускается нажатием (FR-004); два окончательных состояния остаются окончательными (FR-008).

**Scale/Scope**: три экрана с плашкой, два сервиса связи (сокет, селектор пути), один стартер канала.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Принцип | Проверка | Итог |
|---|---|---|
| I. Приватность | Новых данных и логов с содержимым нет; в логах — только причина перезапуска и путь, как сегодня (onion-адрес по-прежнему скрыт). | ✅ |
| II. Спека — источник истины | Обновляются `docs/design/spec/screens/{chats-list,chat,chat-card}.md` и оба корпуса экранов (плашка с действием) в том же change-set'е. | ✅ |
| III. Блюпринт | Действие идёт по существующему пути: виджет → событие блока → `SessionPhaseService` (домен) → `LiveSessionStarter` (данные). `14-networking-and-auth.md` получает предел выбора пути и правило «перезапуск канала сохраняет только здоровый Tor». | ✅ |
| IV. Дизайн-система | Существующий `AppNoticeStripWidget` с действием (так уже выглядит плашка «чужой сервер»), существующий текст `actionTryAgain`. | ✅ |
| V. Языки | Документы — русский; код и коммиты — английский; микрокопия — существующая EN + UK. | ✅ |
| VI. Паритет | Действие на обеих ширинах; голдены mobile + desktop для списка, ленты и карточки. | ✅ |
| VII. Контракт — закон | Провод не меняется. | ✅ |

Повторная проверка после дизайна (Phase 1): нарушений нет, таблица сложности не нужна.

## Project Structure

### Documentation (this feature)

```text
specs/042-connection-recovery/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── no-connection-strip.md
├── checklists/requirements.md
└── tasks.md            # /speckit-tasks
```

### Source Code (repository root)

```text
lib/
├── data/remote/socket/nox_socket_client.dart            # предел выбора пути (pathChoiceBudget)
├── data/sync/connection/connection_path_selector.dart   # end(keepTor:) сохраняет только здоровый Tor
├── data/sync/live_session_starter.dart                  # restart() не наслаивается
└── presentation/
    ├── pages/chats_list_page/{chats_list_page.dart, bloc/chats_list_{bloc,state}.dart}
    ├── pages/chat_card_page/{chat_card_page.dart, bloc/chat_card_{bloc,state}.dart}
    ├── pages/chat_thread_page/bloc/chat_thread_{bloc,state}.dart
    └── widgets/chat/app_thread_view_widget.dart

test/
├── data/remote/socket/nox_socket_client_test.dart
├── data/sync/connection/connection_path_selector_test.dart
├── data/sync/live_session_starter_test.dart
├── presentation/pages/{chats_list_page,chat_card_page,chat_thread_page}/   # bloc, widget, golden
└── presentation/widgets/chat/app_thread_view_widget_test.dart

docs/
├── design/spec/screens/{chats-list,chat,chat-card}.md
├── design/system/nox-mobile-screens/screens/{5-1-chats,5-2-thread,5-4-card}.md + specs.js
├── design/system/nox-desktop-screens/screens/{01-chats,09-drawer}.md + specs.js
└── blueprints/mobile/14-networking-and-auth.md
```

**Structure Decision**: изменения только в клиенте; сервер, контракт и хранилище не трогаются.

## Complexity Tracking

Не требуется.
