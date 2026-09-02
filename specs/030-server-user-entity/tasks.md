---

description: "Task list for feature 030 — persisted server user entity"
---

# Tasks: Постоянная личность пользователя на сервере

**Input**: `/specs/030-server-user-entity/` — [spec.md](./spec.md), [plan.md](./plan.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests**: обязательны. Спека требует девять проверяемых инвариантов опознания ([identity-resolution.md](./contracts/identity-resolution.md) §7), а три места сравнения личности молча ломают контракт §5, если пропущено хоть одно.

## Формат: `[ID] [P?] [Story] Описание`

- **[P]** — можно вести параллельно (разные файлы, нет незакрытых зависимостей)
- **[Story]** — US1 (вернувшийся остаётся собой), US2 (переустановка не стирает человека), US3 (переименование не переписывает прошлое), US4 (опора для этапа 2)

---

## Phase 1: Контракт (первым, до кода — Принцип VII)

Правка контракта предшествует коду. Готовый текст — в [contracts/hello-handshake.md](./contracts/hello-handshake.md).

- [ ] T001 Заменить пункт `identity` в §3 `docs/client-backend/protocol/contract-draft.md`: снять «формат — за Q11», задать форму `u_` + 16 hex, добавить обязанность не усваивать личность подключением без вошедшего человека
- [ ] T002 Заменить пункт `label` в §3 `docs/client-backend/protocol/contract-draft.md` на формулировку «заявление о переименовании, а не состояние»; снять фразу «Личности на этапе 1 не персистятся»; зафиксировать `User<случайное четырёхзначное>` и невозможность отказа из-за имени
- [ ] T003 Добавить пункт `login_ref` в §3 `docs/client-backend/protocol/contract-draft.md` с закреплённой формулой, контрольным вектором и запретом появляться где-либо, кроме `session.hello`
- [ ] T004 Заменить пункт `device_key`/`signature` в §3 `docs/client-backend/protocol/contract-draft.md`: этап 1 записывает непрозрачный идентификатор установки, игнорируется только `signature`
- [ ] T005 Добавить пункт `journal_id` в §3 `docs/client-backend/protocol/contract-draft.md` и обновить оба JSON-примера §3 (запрос и ответ)
- [ ] T006 Добавить в §3 `docs/client-backend/protocol/contract-draft.md` датированную пометку о смене смысла `identity.id`/`author_id` при неизменном `schema: 1`
- [ ] T007 Обновить §5 `docs/client-backend/protocol/contract-draft.md`: реальный `author_id` в примере, пункт про вмороженность `author_label`, уточнение «своё — это личность, а не устройство»
- [ ] T008 Снять пометку «Q11 блокирует» в §8.1 `docs/client-backend/protocol/contract-draft.md` и отметить схему личностей/устройств выполненной; добавить в §9 строку о чистом старте хранилища

**Контрольная точка:** контракт описывает целевое поведение целиком. Дальше код приводится к нему, а не наоборот.

---

## Phase 2: Основание (блокирует все истории)

- [ ] T009 Добавить таблицы `users`, `devices` и `journal` в `client_backend/migrations/001_init.sql` перед `chats` (DDL — [data-model.md](./data-model.md) §1), правя файл **на месте**
- [ ] T010 Изменить `messages` в `client_backend/migrations/001_init.sql`: внешний ключ `author_id` → `users(user_id)`, снять `UNIQUE` с `client_message_id`, добавить `idx_messages_cmid (author_id, client_message_id)`, комментарий про вмороженность `author_label`
- [ ] T011 Добавить в `client_backend/internal/store/store.go` тип `Identity` и скелет `ResolveIdentity` с путями по следу человека и по устройству (инварианты I1, I2 — [identity-resolution.md](./contracts/identity-resolution.md) §2); правило конфликта и ленивый путь — T031, T032
- [ ] T011a Добавить в `client_backend/internal/store/store.go` ленивый путь I5 (личность в памяти без записи) и `MaterialiseUser` — фаза 3 на них опирается, поэтому они принадлежат основанию, а не US2
- [ ] T011b Добавить в `client_backend/internal/store/store.go` `JournalID` и `EnsureJournal`
- [ ] T012 Обновить пакетный комментарий `client_backend/internal/store/store.go:1-7`: запись личности — **второе** осознанно бессобытийное исключение наряду с файловой метадатой
- [ ] T013 Добавить в `client_backend/internal/server/server.go` проверку схемы сразу после `db.Migrate`: отсутствие `users`/`devices`/`journal` → отказ старта с сообщением о причине и лекарстве; там же вставка строки `journal` при первом старте
- [ ] T014 Удалить `userSeq atomic.Int64` из `client_backend/internal/server/server.go` и все его использования
- [ ] T015 [P] Обновить `client_backend/CLAUDE.md`: инвариант 3 (второе бессобытийное исключение) и абзац этапа 1 (разрешить таблицы личностей/устройств без проверок, сохранить запрет подписи, токенов и криптографии)

**Контрольная точка:** схема и хранилище готовы; сервер отказывается стартовать на устаревшей базе.

---

## Phase 3: US1 — вернувшийся остаётся собой (P1) 🎯 MVP

**Цель:** то же устройство узнаётся при каждом подключении; личность переживает перезапуск сервера.

**Независимая проверка:** подключиться, отправить сообщение, перезапустить сервер и приложение, подключиться снова — прежние сообщения остаются собственными.

- [ ] T016 [US1] Добавить `loginRef`, `deviceKey` в `helloRequest` и `journalID` в `helloReply` в `client_backend/internal/server/handlers.go`; `identity` строится из результата разрешения
- [ ] T017 [US1] Вызвать `ResolveIdentity` в `handleSessionHello` **до** `hub.NewSubscriber` (`client_backend/internal/server/handlers.go`), сохранить результат в поле соединения; при ошибке — `internal`, без регистрации в хабе
- [ ] T018 [US1] Добавить поле `userID` в `client_backend/internal/server/client.go` рядом с `label` и обновить докстринг про безопасность кросс-горутинного чтения — он называет конкретное поле
- [ ] T019 [US1] Перевести три места сравнения личности на `userID`: `handlers.go:125` (replay), `handlers.go:338` (`messages.list`), `client.go:140` (live)
- [ ] T020 [US1] Передавать `identity.UserID` и `identity.Label` как **разные** аргументы в `store.SendMessage` (`client_backend/internal/server/handlers.go:401`); там же материализовать ленивую личность
- [ ] T021 [US1] Реализовать `User<случайное четырёхзначное>` через `crypto/rand` с ограниченным числом попыток избежать занятого имени (`client_backend/internal/store/store.go`); исчерпание попыток — не отказ
- [ ] T022 [US1] Проверить журналирование `handleSessionHello` и разрешения личности: ни `login_ref`, ни `device_key`, ни `user_id`, ни `label` не попадают в записи (Принцип I)
- [ ] T023 [P] [US1] Минт идентификатора установки в `lib/data/repository/app/session_repository_impl.dart`: один раз при первом запросе, в `flutter_secure_storage`, через `uuid`
- [ ] T024 [P] [US1] Добавить `crypto` в `pubspec.yaml` и создать `lib/general/identity/identifier_digest.dart` — производная по формуле контракта с ссылкой на закреплённый пункт
- [ ] T025 [US1] Заменить `labelProvider` на провайдер учётных данных в `lib/data/sync/live_session_starter.dart` и `lib/data/remote/socket/nox_socket_client.dart`: отдаёт `loginRef`, `deviceKey` и `label`; при **ошибке** чтения сессии не приветствовать, а перепланировать попытку
- [ ] T026 [US1] Отправлять новые поля в `_greet` (`lib/data/remote/socket/nox_socket_client.dart`) и разбирать `journal_id` из ответа
- [ ] T027 [P] [US1] Тесты инвариантов I1, I2, I4, I7, I9 в `client_backend/internal/store/store_test.go`
- [ ] T027a [P] [US1] Тест отказа старта в `client_backend/internal/server/server_test.go`: миграция с нуля даёт рабочий сервер, база с `user_version = 1` и без `users` — отказ с внятным сообщением (центральная защита от ловушки T2)
- [ ] T028 [P] [US1] Тест на все три пути `client_message_id` (list, replay, live) в `client_backend/internal/server/integration_test.go`
- [ ] T028a [P] [US1] Тест «своё — это личность, а не устройство» в `client_backend/internal/server/integration_test.go`: один человек, два соединения; второе получает `client_message_id` отправки первого (правило контракта §5, вводится T007; заодно закрывает FR-011 — одновременные подключения одной личности)
- [ ] T029 [P] [US1] Тест назначенных имён в `client_backend/internal/server/integration_test.go`: **форма** `User` + четыре знака (исправляемый дрейф, FR-019) и различность после перезапуска сервера
- [ ] T030 [P] [US1] Тест `test/general/identity/identifier_digest_test.dart` — пин **ожидаемой** строки контрольного вектора, а не сравнение функции с самой собой
- [ ] T030a [P] [US1] Тест в `test/data/remote/socket/nox_socket_client_test.dart`: полезная нагрузка приветствия содержит производную и **не** содержит сырой идентификатор входа ни в каком виде (FR-007)

**Контрольная точка:** US1 работает целиком и проверяема отдельно.

---

## Phase 4: US2 — переустановка не стирает человека (P1)

**Цель:** вход тем же идентификатором возвращает ту же личность на любой установке.

**Независимая проверка:** отправить сообщение, стереть локальные данные, войти тем же идентификатором — прошлые сообщения снова собственные.

- [ ] T031 [US2] Реализовать в `ResolveIdentity` приоритет следа человека над устройством и перепривязку устройства (`client_backend/internal/store/store.go`), сохраняя `created_at`
- [ ] T032 [US2] Довести ленивый путь до сквозного: материализация при первой отправке в **той же** транзакции, что и сообщение (`client_backend/internal/server/handlers.go`, `client_backend/internal/store/store.go`)
- [ ] T033 [P] [US2] Тесты инвариантов I3, I5, I8 (последний — через `testing/synctest`) в `client_backend/internal/store/store_test.go`
- [ ] T034 [P] [US2] Тест живого пробника `client_backend/internal/server/integration_test.go`: приветствие без обоих полей → `ok`, `COUNT(*) FROM users` не вырос

**Контрольная точка:** US2 работает; главный сценарий владельца закрыт.

---

## Phase 5: US3 — переименование не переписывает прошлое (P1)

**Цель:** имя меняется вперёд, история остаётся собственной и подписанной прежним именем.

**Независимая проверка:** отправить сообщение, переименоваться, отправить второе — первое подписано старым именем и осталось своим, без ручного переподключения.

- [ ] T035 [US3] Флаг `session.label_dirty` в `lib/data/repository/app/session_repository_impl.dart`: ставится в `updateLabel` и `setOnboardingComplete`, снимается в `adoptServerIdentity` после подтверждения
- [ ] T036 [US3] Провайдер учётных данных включает `label` **только** при поднятом флаге (`lib/data/sync/live_session_starter.dart`)
- [ ] T037 [US3] Вызвать `LiveSessionStarter.restart()` после успешного `updateLabel` в `lib/presentation/pages/settings_root_page/bloc/settings_root_bloc.dart` по образцу `auth_repository_impl.dart:53`
- [ ] T038 [US3] Условное обновление имени в `ResolveIdentity` (`client_backend/internal/store/store.go`): пустое заявление имя не меняет
- [ ] T039 [P] [US3] Тест инварианта I6 в `client_backend/internal/store/store_test.go`
- [ ] T039a [P] [US3] Тест вмороженности подписи (FR-014) в `client_backend/internal/server/integration_test.go`: после переименования `author_label` прошлых сообщений не изменился, а `author_id` остался прежним
- [ ] T040 [P] [US3] Тест в `test/data/sync/live_session_starter_test.dart`: без поднятого флага `label` не отправляется; после переименования отправляется ровно один раз

**Контрольная точка:** пинг-понг переименований невозможен.

---

## Phase 6: Ловушка T3 — смена хранилища сервера

Не привязана к одной истории: закрывает FR-024, FR-024a, FR-024b, FR-024c для всех сразу.

- [ ] T041 Хранить `journal_id` рядом с эпохой и сравнивать при приветствии (`lib/data/sync/live_session_starter.dart`)
- [ ] T042 Страж смены журнала в `lib/data/remote/socket/nox_socket_client.dart`: обнаружив расхождение **до** применения первого кадра replay, разорвать соединение и сообщить наверх; сокет **не** владеет стиранием и переподключается в любом случае
- [ ] T043 Сброс мира принадлежит `LiveSessionStarter` (`lib/data/sync/live_session_starter.dart`): готовый цикл `stop()` → стирание → `start()`, со сбросом `AttachmentPrefetchService`
- [ ] T044 Добавить `session.author_id` в список стираемого при смене мира (`lib/data/sync/live_session_starter.dart`) — оставленный, он разметит чужие сообщения своими
- [ ] T045 Обернуть очистку кэша файлов в best-effort try/catch по образцу пути logout (`lib/data/sync/live_session_starter.dart`)
- [ ] T046 Обернуть вызов `LiveSessionStarter.start()` в try/catch в `lib/main.dart`: сбой живого канала не должен мешать приложению дойти до экрана
- [ ] T047 [P] Тесты в `test/data/sync/live_session_starter_test.dart`: смена журнала стирает ровно один раз и записывает новый; падающая очистка кэша не срывает ни стирание, ни старт

**Контрольная точка:** устройство переживает пересборку серверного хранилища без ручного вмешательства.

---

## Phase 7: US4 — опора для этапа 2 (P2)

- [ ] T048 [US4] Проверить по `docs/client-backend/architecture/authentication.md`, что кейсы 3 и 4 ложатся на введённые таблицы без изменения их формы; расхождения записать в документ

---

## Phase 8: T5 и смежные стражи клиента

- [ ] T049 Не усваивать личность в `_adoptGreeting` при отсутствии сессии (`lib/data/sync/live_session_starter.dart`); зафиксировать личность соединения на момент приветствия, а не перечитывать позже
- [ ] T050 [P] Тест в `test/data/sync/live_session_starter_test.dart`: приветствие без сессии не пишет `session.author_id` и `session.label`

---

## Phase 9: Правдивость корпуса

- [ ] T051 [P] Закрыть Q11 в `docs/client-backend/open-questions.md`: строка реестра, раздел Q11 с решением и датой, снятие пометок «блокирует» везде
- [ ] T052 [P] Обновить `docs/client-backend/protocol/wire-surface.md` §2.1 — находка про утечку идентификатора описана в настоящем времени и больше не верна
- [ ] T053 [P] Исправить перевёрнутое описание DI-привязок в корневом `CLAUDE.md` (реально `Real*` на `[Environment.dev]`, моки на `[prod, test]`) и обновить абзацы про `author_id`, Q11 и открытую работу
- [ ] T054 [P] Обновить `docs/blueprints/client-backend/README.md` в части схемы и приветствия
- [ ] T055 [P] Исправить устаревший докстринг `lib/data/entity/chat/wire/message_wire_mapper.dart:16-17` про судьбу `clientMessageId`
- [ ] T056 [P] Отметить фазу 030 в `docs/client-backend/roadmap-client-track.md`

---

## Phase 10: Тестовые данные и живая проверка

- [ ] T057 Пересоздать identity-несущие фикстуры: `hello.json`, `message_new_text_event.json`, `message_new_attachment_event.json`, `message_send_echo.json`, `message_send_attachment_echo.json`, `messages_list_page.json`
- [ ] T058 Обновить `test/utils/fake_session_repository.dart` под новые поля сессии
- [ ] T059 Адаптировать живой пробник в `test/live/` — он не предъявляет ни следа, ни устройства и обязан продолжать работать
- [ ] T060 Проверка SC-007: механизм подсчёта вхождений идентификаторов в журнале сервера по [quickstart.md](./quickstart.md) §2.6
- [ ] T061 Прогнать `cd client_backend && gofmt -l . && go vet ./... && go test -race ./...`
- [ ] T062 Прогнать `make gate`
- [ ] T063 Прогнать `make golden-verify` — 216 снимков обязаны совпасть без перегенерации
- [ ] T064 Живой сценарий на двух клиентах по [quickstart.md](./quickstart.md) §2, включая §2.4 (главный) и §2.5

---

## Зависимости

```
Phase 1 (контракт)  ──▶  Phase 2 (основание)  ──┬──▶ Phase 3 (US1) ──▶ Phase 4 (US2) ──▶ Phase 5 (US3)
                                                └──▶ Phase 6 (T3, независима от US)
Phase 3+4+5+6  ──▶  Phase 7, 8  ──▶  Phase 9 (документы)  ──▶  Phase 10 (проверка)
```

- **Phase 1 блокирует всё**: код приводится к контракту, значит контракт существует раньше.
- **Phase 2 блокирует все истории**: без схемы и `ResolveIdentity` ни одна не собирается.
- **US2 зависит от US1** не логически, а по файлу: обе правят `ResolveIdentity`. Ленивый путь вынесен в основание (T011a), потому что на него опирается T020 из фазы 3.
- **US3 частично независима**: T035–T037 и T040 — клиентские файлы, можно вести параллельно с US2.
- **Phase 6 полностью независима** от US1–US3 и может идти параллельно с ними после Phase 2.

## Параллельные возможности

| Группа | Задачи |
|---|---|
| Клиентское основание | T023, T024 — разные файлы, ни от чего не зависят после Phase 2 |
| Серверные тесты US1 | T027, T028, T029 — разные файлы |
| Тесты US2 | T033, T034 |
| Документы | T051–T056 — шесть разных файлов, все после кода |

## Стратегия

**MVP — Phase 1 + Phase 2 + Phase 3 (US1).** Даёт наблюдаемое: вернувшееся устройство узнаётся, личность переживает перезапуск сервера, `author_id` перестаёт быть именем. Уже проверяемо вживую.

**Затем Phase 4 (US2)** — главный сценарий владельца, ради которого фича и затевалась.

**Phase 6 нельзя откладывать за пределы фичи:** именно это изменение делает стирание серверной базы обязательным, поэтому защита от последствий стирания принадлежит ему же.

## Соответствие требованиям

| Требование | Задачи |
|---|---|
| FR-001…FR-009 (личность и устройство) | T009, T011, T011a, T016–T021, T031–T032 |
| FR-010 (последнее появление устройства) | T009, T027 (инвариант I9) |
| FR-011 (одновременные подключения) | T028a |
| FR-012, FR-015…FR-017 (авторство) | T019, T020, T028 |
| FR-013 (публичность `user_id`) | обеспечено конструкцией минта (T011); отдельного теста не требует |
| FR-014 (вмороженная подпись) | T010, T020, T039a |
| FR-018…FR-020 (имя) | T021, T035–T038 |
| FR-021, FR-022 (приватность) | T022, T030a, T060 |
| FR-023…FR-025 (переход) | T013, T041–T047, T001–T008 |
| FR-026…FR-029 (правдивость корпуса) | T015, T051–T056 |
| SC-001…SC-009 | T027–T030, T033–T034, T039–T040, T047, T050, T060–T064 |
| T1…T5 (ловушки) | T019, T013, T041–T047, T035–T037, T049 |
