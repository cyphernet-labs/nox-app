# Implementation Plan: client-outbox

**Branch**: `027-client-outbox` | **Date**: 2026-08-30 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/027-client-outbox/spec.md`

## Summary

Очередь исходящих переезжает из состояния экрана треда в data-слой и становится долговечной. Сегодня неотправленное живёт в поле `outgoing` у `ChatThreadBloc`, а ключ идемпотентности минтится там же и существует только в памяти: уход с экрана и перезапуск приложения его уничтожают. Фаза вводит store `outbox` в Sembast, репозиторий поверх него и один сливающий сервис, подписанный на фазу сессии; `outgoing` становится **проекцией** очереди, а не её хранилищем.

Ключевое следствие для UI: экран не меняется вовсе. Пузырь в состоянии `pending`/`error` рисуется из той же `MessageModel`, что и сегодня, — просто источником строк становится очередь. Это то, что делает SC-006 (эталонные снимки без перегенерации) достижимым, а не пожеланием.

## Technical Context

**Language/Version**: Dart / Flutter 3.44.1 (FVM-pinned), пакет `nox_app`

**Primary Dependencies**: sembast (store очереди), freezed + json_serializable (сущность), injectable + get_it (DI), bloc + bloc_concurrency, uuid (ключ идемпотентности)

**Storage**: Sembast, новый store `outbox`; ключ записи — сам `client_message_id`

**Testing**: `flutter_test` + `bloc_test` + `mockito`; гейт `make gate`, снимки `make golden-verify`

**Target Platform**: iOS / Android / macOS / Windows / Linux (одно приложение, обе ширины)

**Project Type**: mobile+desktop Flutter app, Clean Architecture слоями-папками

**Performance Goals**: слив очереди — строго последовательный, одна команда за раз; повторная попытка по нарастающей паузе 1s→30s, не чаще

**Constraints**: очередь хранит тексты сообщений — умирает вместе с остальными локальными данными при выходе; никакой новой микрокопии и ни одного нового экрана

**Scale/Scope**: одна сущность, один DAO, один репозиторий, один сервис, один изменённый BLoC

## Constitution Check

*GATE: пройден до Phase 0, перепроверен после Phase 1.*

| Принцип | Оценка | Обоснование |
|---|---|---|
| I. Приватность и E2EE | ✅ | Очередь не расширяет поверхность хранения: тексты уже лежат в `messages`. Логи фазы не пишут ни текстов, ни меток, ни идентификаторов — только `client_message_id` и код ошибки. Выход из аккаунта стирает store (FR-010). |
| II. Спека — истина | ✅ | Артефакты пишутся до кода; `docs/blueprints/mobile/` и §9 контракта приводятся в соответствие в том же change-set. |
| III. Обязательный blueprint | ✅ | Никаких новых схем: сущность повторяет плоский идиом `MessageEntity`, DAO — идиом `SyncDao`, сервис — идиом `SyncService` (сериализующая цепочка `_queue`), привязки DI — `@LazySingleton(env: [...])`. |
| IV. Верность дизайн-системе | ✅ | Ни одного нового виджета, токена или строки l10n. Проверяется SC-006. |
| V. Языковая дисциплина | ✅ | Код и коммиты — английские, артефакты фазы — русские. |
| VI. Паритет mobile↔desktop | ✅ | Изменение целиком за пределами вёрстки: оба варианта треда читают `outgoing` из одного состояния. Обе ширины подтверждаются снимками. |
| VII. Контракт — закон | ✅ | Провод не меняется. Фаза выполняет §9 пункты 3 и 8 в точности: ключ назначается **при постановке в очередь**, персистится с записью и переживает рестарт. |

Нарушений нет; раздел Complexity Tracking не нужен.

## Project Structure

### Documentation (this feature)

```text
specs/027-client-outbox/
├── spec.md
├── plan.md              # этот файл
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── outbox-repository.md
├── checklists/
│   └── requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
lib/
├── domain/
│   ├── model/chat/
│   │   ├── outbox_entry.dart          # NEW  доменная запись очереди
│   │   └── outbox_status.dart         # NEW  pending | error
│   └── repository/chat/
│       └── outbox_repository.dart     # NEW  контракт очереди
├── data/
│   ├── entity/chat/
│   │   └── outbox_entity.dart         # NEW  freezed DTO, плоское вложение
│   ├── local/chat/
│   │   └── outbox_dao.dart            # NEW  store 'outbox'
│   ├── mapper/chat/
│   │   └── outbox_mapper.dart         # NEW  entity <-> model
│   ├── repository/chat/
│   │   └── outbox_repository_impl.dart# NEW
│   ├── sync/
│   │   └── outbox_service.dart        # NEW  сливающий сервис
│   └── repository/app/
│       └── auth_repository_impl.dart  # EDIT очередь входит в вайп логаута
├── presentation/
│   ├── pages/chat_thread_page/bloc/
│   │   ├── chat_thread_bloc.dart      # EDIT outgoing = проекция очереди
│   │   └── chat_thread_event.dart     # EDIT + OutboxChanged, SendDiscarded
│   └── widgets/chat/
│       └── app_thread_view_widget.dart# EDIT второй жест по отказавшему пузырю
├── l10n/app_en.arb, l10n/app_uk.arb   # EDIT tooltipRetry называет оба жеста
└── main.dart                          # EDIT старт сервиса очереди

test/
├── data/local/chat/outbox_dao_test.dart
├── data/repository/chat/outbox_repository_impl_test.dart
├── data/sync/outbox_service_test.dart
└── presentation/pages/chat_thread_page/bloc/chat_thread_bloc_test.dart  # EDIT
```

**Structure Decision**: слои остаются папками одного пакета `nox_app`; очередь ложится в существующие директории чата (`*/chat/`), сервис — рядом с `SyncService` в `data/sync/`, потому что это тот же род вещи: фоновой процесс, живущий по фазе сессии.

## Design decisions

### Кто отправляет

**Ровно один отправитель — `OutboxService`.** Сегодня отправляют два места (`_deliver` при вводе и `_redeliverQueued` при реконнекте), и они уже однажды дали дубль. Слив сериализован цепочкой `Future _queue` (идиом `SyncService`): параллельный вызов не начинает второй проход, а пристраивается в хвост первого. BLoC больше не отправляет — он ставит в очередь и просит слить.

### Почему проекция, а не вторая копия

`outgoing` пересчитывается из очереди по её тику. Держать список и в состоянии BLoC, и в store — значит завести две правды и синхронизировать их вручную; ровно на этом сегодня построены `_updateOutgoing` и `_adoptOutgoing`. Проекция убирает их обе.

### Пузырь появляется сразу, а не по тику

`MessageSent` эмитит оптимистичную строку **сразу после возврата постановки в очередь**, не дожидаясь тика наблюдения. Ждать тик — значит поставить появление пузыря в зависимость от планировщика потоков; снимки состояний отправки пумпаются ограниченным числом кадров и стали бы плавающими. Тик, придя следом, пересчитает ту же строку с тем же ключом — состояние получится равным, и BLoC его отбросит.

### Почему нет мигания при успехе

Успешная отправка — это два события: сообщение появилось в `messages`, запись исчезла из `outbox`. Если BLoC отреагирует на них раздельно, между ними пузырь пропадёт. Поэтому обработчик тика очереди **в одном обходе** читает записи и перечитывает сообщения из кэша, а `emit` делает один раз. Порядок записи гарантирует корректность: сервис удаляет запись только **после** того, как репозиторий персистировал сообщение.

### Порядок

Сортировка по полю `ordinal` — целому, которое назначается внутри транзакции постановки как `max(ordinal) + 1`. Не по времени: под замороженными в снимках часами у нескольких сообщений совпадает `createdAt`, и порядок стал бы неопределённым.

### Что повторять, а что нет

Повтор исправляет только те отказы, которые от повтора зависят. Коды `connection`, `rate_limited`, `internal` и неизвестный отказ — повторяются с нарастающей паузой; `invalid_request`, `not_found`, `payload_too_large`, `attachment_gone`, `unauthenticated`, `unsupported_schema` — окончательные: запись помечается ошибкой и ждёт человека. Это же и есть ответ на краевой случай «сообщение, которое не уйдёт никогда».

### Что делать с отказавшим пузырём

Касание по нему повторяет отправку — как сегодня. Долгое нажатие (мышью — вторичное нажатие) **убирает** запись из очереди: без выхода бесконечный повтор становится ловушкой, а отказавший пузырь после этой фазы переживает и уход с экрана, и перезапуск, то есть висел бы вечно. Новых виджетов и экранов это не вводит: жест вешается на тот же `GestureDetector`, а подсказка на пузыре — единственная строка интерфейса, которую фаза меняет, — называет оба жеста. Подсказка всплывает по наведению и долгому нажатию и ни в один эталонный снимок не попадает.

### Отладочные состояния

Сценарии `offline` и `sendError` остаются достижимыми и дают тот же вид: `offline` ставит в очередь и не сливает, `sendError` ставит и сразу помечает ошибкой. Без этого снимки состояний отправки перестали бы воспроизводиться.

## Phases

- **Phase 0 — research**: [research.md](./research.md) — решения по хранению, порядку, повтору, месту слива.
- **Phase 1 — design**: [data-model.md](./data-model.md), [contracts/outbox-repository.md](./contracts/outbox-repository.md), [quickstart.md](./quickstart.md).
- **Phase 2 — tasks**: `/speckit-tasks`.

## Post-Design Constitution Re-check

Пересмотр после Phase 1 ничего не изменил: новых виджетов нет, провод не тронут, слои не пересечены (`domain` по-прежнему ничего не импортирует). Единственная точка внимания — Принцип I: `OutboxService` логирует только ключ и код ошибки, тексты в логи не попадают.
