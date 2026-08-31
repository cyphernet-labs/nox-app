---

description: "Task list for client-outbox"
---

# Tasks: client-outbox

**Input**: `/specs/027-client-outbox/` — [spec.md](./spec.md), [plan.md](./plan.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/outbox-repository.md](./contracts/outbox-repository.md), [quickstart.md](./quickstart.md)

**Tests**: включены — CI на паузе, локальный гейт единственный, и три из пяти критериев успеха (порядок, отсутствие дублей, переживание рестарта) иначе нечем подтвердить.

**Organization**: по историям спеки. US1 самодостаточна и составляет MVP.

## Format: `[ID] [P?] [Story] Описание`

- **[P]** — можно вести параллельно (разные файлы, нет незакрытых зависимостей)
- **[Story]** — к какой истории относится

---

## Phase 1: Setup

**Цель**: ветка и точка отсчёта.

- [ ] T001 Убедиться, что ветка `027-client-outbox` отведена от актуального `develop` и гейт на ней зелёный: `make gate && make golden-verify`

---

## Phase 2: Foundational (блокирует все истории)

**Цель**: очередь как хранилище — сущность, DAO, домен, маппер, репозиторий, DI. Без неё ни одна история не начинается.

- [ ] T002 [P] Создать `lib/domain/model/chat/outbox_status.dart` — `enum OutboxStatus { pending, error }` с доккоментарием о том, почему `sending` не персистится
- [ ] T003 [P] Создать `lib/domain/model/chat/outbox_entry.dart` — `@freezed` модель по data-model.md (`clientMessageId`, `chatId`, `ordinal`, `text?`, `attachment?`, `createdAt`, `status`, `attempts`, `lastErrorCode?`)
- [ ] T004 [P] Создать `lib/data/entity/chat/outbox_entity.dart` — `@freezed` + `json_serializable` DTO, только базовые типы, вложение плоскими полями; новые поля объявлены необязательными
- [ ] T005 Создать `lib/data/local/chat/outbox_dao.dart` — store `outbox`, ключ записи = `clientMessageId`; `enqueue` считает `ordinal = max + 1` **в транзакции**; сортировка и фильтрация в Dart по декодированным сущностям (гоча `field_rename: snake`); битая запись пропускается
- [ ] T006 [P] Создать `lib/data/mapper/chat/outbox_mapper.dart` — `OutboxEntity` ↔ `OutboxEntry`, включая сборку/разбор `MessageAttachment`
- [ ] T007 Создать `lib/domain/repository/chat/outbox_repository.dart` по contracts/outbox-repository.md
- [ ] T008 Создать `lib/data/repository/chat/outbox_repository_impl.dart` — `@LazySingleton(as: OutboxRepository, env: [dev, prod, test])`; `enqueue` минтит `client_message_id` (`uuid v4`) и возвращает записанную запись через `execute`
- [ ] T009 Прогнать `make generate` и убедиться, что `analyze` чист

**Контрольная точка**: очередь читается и пишется; ни один экран о ней ещё не знает.

---

## Phase 3: US1 — неотправленное переживает перезапуск (P1) 🎯 MVP

**Цель**: написанное без связи сохраняется на устройстве, восстанавливается после перезапуска и уходит само, когда связь появляется — в порядке написания.

**Независимая проверка**: отправить при выключенном сервере, убить приложение, запустить снова — сообщения на месте и в прежнем порядке; поднять сервер — уходят без действий пользователя.

- [ ] T010 [US1] Создать `lib/data/sync/outbox_service.dart` — `start()` подписывается на `SessionPhaseService.watchPhase()` и сливает по переходу в `live`; `flush()` сериализован цепочкой `Future _queue`; `stop()` снимает подписку и таймер
- [ ] T011 [US1] Реализовать проход слива: `pending()` по возрастанию `ordinal`, по одной записи, `remove` **после** успешного возврата `sendMessage`
- [ ] T012 [US1] Завести старт сервиса в `lib/main.dart` — после `configureDependencies` и `allReady()`, во всех окружениях (в отличие от `LiveSessionStarter`, который только `dev`)
- [ ] T013 [US1] Перевести `ChatThreadBloc` на очередь: `MessageSent` ставит в очередь, **сразу** эмитит оптимистичную строку (не дожидаясь тика — иначе появление пузыря зависит от планировщика и снимки поплывут) и просит слить; добавить событие `OutboxChanged` и подписку `watchQueue(chatId: ...)`; убрать `_deliver`, `_updateOutgoing`, `_adoptOutgoing`, `_redeliverQueued`. `ConnectivityChanged` сохраняет за собой только баннер и вызов `flush()` на переходе в эфир — переотправку он больше не ведёт
- [ ] T014 [US1] Обработчик `OutboxChanged` пересчитывает `outgoing` из записей **и** перечитывает сообщения из кэша, эмитя состояние **один раз** — окно мигания при успехе закрывается порядком записи в сервисе
- [ ] T015 [US1] Сохранить достижимость отладочных состояний: сценарий `offline` ставит в очередь и не сливает, `sendError` ставит и сразу помечает ошибкой; сброс сценария чистит очередь чата через `removeForChat`
- [ ] T016 [P] [US1] Тест `test/data/local/chat/outbox_dao_test.dart` — порядок по `ordinal`, монотонность `ordinal` через новый экземпляр DAO над той же базой, пропуск битой записи, тик наблюдения, `cleanData`
- [ ] T017 [P] [US1] Тест `test/data/repository/chat/outbox_repository_impl_test.dart` — `enqueue` минтит и персистит ключ, `markError`/`markPending`/`remove`/`removeForChat`/`clean`
- [ ] T018 [US1] Тест `test/data/sync/outbox_service_test.dart` — десять записей уходят строго в порядке `ordinal` (SC-003); параллельный `flush()` не даёт второй отправки; слив срабатывает по переходу фазы в `live`
- [ ] T019 [US1] Дополнить `test/presentation/pages/chat_thread_page/bloc/chat_thread_bloc_test.dart` — неотправленное восстанавливается **новым экземпляром** BLoC (прокси перезапуска), порядок сохранён

**Контрольная точка**: US1 проверяема целиком; сценарии 1 и 3 quickstart проходят.

---

## Phase 4: US2 — повтор не создаёт второй копии (P2)

**Цель**: повтор после потерянного ответа и после перезапуска идёт с прежним ключом; на сервере одна копия. Классификация отказов и пауза повтора.

**Независимая проверка**: оборвать связь между отправкой и ответом, перезапустить, дождаться повтора — у второго клиента ровно одно сообщение.

- [ ] T020 [US2] Классификация отказа в `outbox_service.dart`: `connection`/`rateLimited`/`internal`/`unknown` — повторяемые (`recordFailure(terminal: false)`), прочие — окончательные (`recordFailure(terminal: true)`, проход продолжается со следующей записи)
- [ ] T021 [US2] Нарастающая пауза `min(30s, 1s × 2^(attempts − 1))` с ±20% джиттера, где `attempts` берётся у головной записи — счётчик прохода не годится, он умирает вместе с процессом; пауза сбрасывается при новом переходе в `live`
- [ ] T022 [US2] `SendRetried` в `ChatThreadBloc` — `markPending` по прежнему ключу плюс `flush()`; `attempts` не сбрасывается
- [ ] T023 [US2] Дополнить `test/data/sync/outbox_service_test.dart` — повторяемый отказ оставляет запись в очереди и повторяет её тем же ключом; окончательный помечает ошибкой и **не блокирует** следующую
- [ ] T024 [US2] Дополнить тест BLoC — ручной повтор уходит с прежним `clientMessageId`
- [ ] T025 [US2] Второй жест по отказавшему пузырю убирает запись из очереди: долгое нажатие и вторичное нажатие мышью в `lib/presentation/widgets/chat/app_thread_view_widget.dart` (обе ширины — Принцип VI), событие `SendDiscarded` в `ChatThreadBloc` → `remove`
- [ ] T026 [P] [US2] Обновить `tooltipRetry` в `lib/l10n/app_en.arb` **и** `lib/l10n/app_uk.arb` — подсказка называет оба жеста; наборы ключей остаются одинаковыми
- [ ] T027 [US2] Тест: убранное вторым жестом не возвращается ни при следующем сливе, ни у нового экземпляра BLoC (SC-007)

**Контрольная точка**: сценарии 2 и 4 quickstart проходят.

---

## Phase 5: US3 — уход с экрана ничего не теряет (P3)

**Цель**: очередь сливается независимо от того, открыт ли тред; выход из аккаунта не оставляет текстов.

**Независимая проверка**: написать без связи, уйти в список чатов, восстановить связь — уходит; вернуться — на месте, отправленное.

- [ ] T031 [US3] Добавить `OutboxRepository` в вайп логаута (`lib/data/repository/app/auth_repository_impl.dart`) — рядом с `chats.clean()`/`messages.clean()`, порядок: остановить слив, затем чистить
- [ ] T029 [US3] Остановить слив до вайпа: `OutboxService.stop()` в той же ветке логаута, что и `LiveSessionStarter.stop()`
- [ ] T030 [US3] Обновить `test/data/repository/app/auth_repository_impl_test.dart` — очередь входит в вайп и чистится после успешного `session.clear()`, но не при отказе
- [ ] T031 [US3] Тест: слив работает при закрытом треде (сервис сливает записи чата, чей BLoC не создан)

**Контрольная точка**: сценарии 3 и 5 quickstart проходят.

---

## Phase 6: Polish и сквозные обязательства

- [ ] T032 [P] Привести `docs/blueprints/mobile/` в соответствие: очередь исходящих описана как data-слой, а не как состояние экрана (Принцип III — расхождение чинится в том же change-set)
- [ ] T033 [P] Отметить в `docs/client-backend/protocol/contract-draft.md` §9 пункты 3 и 8 как выполненные клиентом и обновить статус 027 в `docs/client-backend/roadmap-client-track.md`
- [ ] T034 [P] Обновить `CLAUDE.md` — очередь исходящих в разделе data-слоя, `OutboxService` рядом с `SyncService`
- [ ] T035 Проверить Принцип I: `OutboxService` и репозиторий логируют только `client_message_id` и код ошибки — ни текста, ни метки, ни имени чата
- [ ] T036 Гейт: `make gate` зелёный и `make golden-verify` зелёный **без перегенерации** эталонов — включая 62 десктопных эталона, то есть обе ширины подтверждены (SC-006, Принцип VI)

---

## Dependencies

```text
Phase 1 (T001)
    └─▶ Phase 2 (T002–T009)  ← блокирует всё
            ├─▶ Phase 3 US1 (T010–T019)   MVP
            │       ├─▶ Phase 4 US2 (T020–T027)   опирается на слив из T010–T011
            │       └─▶ Phase 5 US3 (T028–T031)   опирается на сервис из T010
            └─▶ Phase 6 (T032–T036)   после кода
```

US2 и US3 независимы друг от друга и могут идти параллельно после US1.

## Parallel opportunities

- **Phase 2**: T002, T003, T004 — три разных новых файла, зависимостей между ними нет; T006 параллелен T005 после появления T003/T004.
- **Phase 3**: T016 и T017 — разные тестовые файлы.
- **Phase 4**: T026 (строки) параллелен T025 (жест).
- **Phase 6**: T032, T033, T034 — три разных документа.

## Implementation strategy

MVP — **Phase 2 + Phase 3**: этого достаточно, чтобы неотправленное перестало пропадать, что и есть суть фазы. US2 добавляет устойчивость повтора, US3 — независимость от экрана и чистоту после выхода. Коммит на историю, гейт перед каждым коммитом.
