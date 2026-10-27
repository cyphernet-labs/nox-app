---

description: "Task list for feature 037 — local-only phase"
---

# Tasks: Локальный продукт — один человек на своём сервере

**Input**: Design documents from `/specs/037-local-only-phase/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/wire-delta.md](./contracts/wire-delta.md), [quickstart.md](./quickstart.md)

## Format: `[ID] [P?] [Story] Description`

- **[P]** — можно делать параллельно: другой файл, нет зависимости от незакрытой задачи
- **[US1]…[US4]** — к какой пользовательской истории относится

## Path Conventions

Сервер — `client_backend/`, приложение — `lib/` и `test/`, документы — `docs/`.

⚠️ **CI на паузе.** `make gate` и `make golden-verify` обязательны локально перед каждым коммитом. Задачи-гейты в списке — не формальность, а единственное место, где ловится регрессия.

---

## Phase 1: Setup

- [x] T001 Удалить локальные базы разработки (`/tmp/nox-demo*`, `client_backend/*.db`) — схема правится на месте, старый файл несовместим
- [x] T002 Зафиксировать базовые счётчики для SC-003: число Go-тестов, число Dart-тестов и число голденов **до** уборки, записать в `specs/037-local-only-phase/quickstart.md`

---

## Phase 2: Foundational — контракт правится первым

**Блокирует всё остальное.** Принцип VII: контракт — закон, обе стороны следуют записанному.

- [x] T003 Удалить раздел 8B «Приглашение человека в круг» целиком из `docs/client-backend/protocol/contract-draft.md`
- [x] T004 Удалить `person.invite`, `person.list`, `person.confirm` из перечня команд §8.1 в `docs/client-backend/protocol/contract-draft.md`
- [x] T005 Удалить события `person.pairRequested` и `person.pairResolved` из §6 — **оказалась пустой**: в §6 их не было, оба определялись только внутри §8B и ушли с ним (T003) в `docs/client-backend/protocol/contract-draft.md`
- [x] T006 Убрать ветку `status: "pending"` и поля `request_id` / `expires_at` из описания `pair` в §8A в `docs/client-backend/protocol/contract-draft.md`
- [x] T007 Убрать поле `owner` из объекта личности в §2.1 и во всех местах, где объект описан, в `docs/client-backend/protocol/contract-draft.md`
- [x] T008 Убрать коды ошибок `not_owner`, `pair_declined`, `pair_timeout` из §2.1 в `docs/client-backend/protocol/contract-draft.md`
- [x] T009 Переформулировать §1 (обзор), обоснование `chat.rename` и правило уникальности имени чата в `docs/client-backend/protocol/contract-draft.md`
- [x] T010 Записать в `docs/client-backend/protocol/contract-draft.md`, что изменение ломающее, и почему это допустимо (развёрнутых установок нет, стороны выпускаются одним коммитом)

**Гейт фазы**: документ читается связно, ни одна внутренняя ссылка не ведёт в удалённый раздел.

---

## Phase 3: User Story 1 — Сервер принадлежит одному человеку (Priority: P1) 🎯 MVP

**Цель**: на сервере не может появиться второй человек, и продукт нигде о нём не упоминает.

**Независимая проверка**: свежий сервер, два устройства одного человека; команды `person.*` не отвечают ничем осмысленным; в настройках нет `People`; в карточке личности нет отметки владения.

### 3A. Сервер: провод

- [x] T011 [P] [US1] Удалить `client_backend/internal/store/approval.go` и `client_backend/internal/store/approval_test.go`
- [x] T012 [P] [US1] Удалить `client_backend/internal/store/people.go` и `client_backend/internal/store/people_test.go`
- [x] T013 [P] [US1] Удалить `client_backend/internal/server/approval_test.go`
- [x] T014 [US1] Снять `handlePersonInvite`, `handlePersonList`, `handlePersonConfirm` из `client_backend/internal/server/pairing.go`
- [x] T015 [US1] Снять диспетчеризацию `person.*` из `client_backend/internal/server/ws.go`; **убедиться, что удалённое имя падает в ветку «неизвестная команда», а не в общий обработчик по префиксу** (FR-006)
- [x] T016 [US1] Снять ветку pending, `deliverSettledOutcome`, `announcePairOutcome` и поля `pairReply` из `client_backend/internal/server/pairing.go`
- [x] T017 [US1] Снять `notifyPairRequested`, `notifyPairResolved`, `pairRequestedFrame`, `markPendingRequest`, `sendToOwnerDevices` из `client_backend/internal/server/server.go`
- [x] T018 [US1] Снять `runPairSweeper` и его поля из `client_backend/internal/server/server.go`
- [x] T019 [US1] Снять `resendPendingRequests` и её вызов при приветствии из `client_backend/internal/server/handlers.go`
- [x] T020 [US1] Снять поле `pendingRequestID` из `client_backend/internal/server/client.go`
- [x] T021 [US1] Снять три команды, два события и три кода из `client_backend/internal/protocol/frames.go` и `client_backend/internal/protocol/errors.go`
- [x] T022 [US1] **Гейт**: `cd client_backend && go test -race ./...` зелёный

### 3B. Сервер: схема и владение

- [x] T023 [US1] Убрать `invite_user` из CHECK и удалить `request_id`, `awaiting_platform`, `awaiting_until`, `outcome` и `idx_pair_tokens_pending` из `client_backend/migrations/001_init.sql`
- [x] T024 [US1] Добавить синглтон-индекс `users` в `client_backend/migrations/001_init.sql`; **проверить**, что SQLite принимает индекс по выражению на STRICT-таблице, иначе заменить на инвариант в комментарии плюс тест, доказывающий, что вторая личность не заводится ни одним путём. **Выбранный вариант записать в `research.md` §2** — задача считается закрытой только с записанным решением
- [x] T025 [US1] Снять `TokenInviteUser`, `PersonInviteTTLSeconds`, `ApprovalWindowSeconds`, `IssuePersonInvite`, `PairResult.Pending`, `pendingOutcome` из `client_backend/internal/store/pairing.go`
- [x] T026 [US1] Убрать признак владения из резолва личности и коррелированный подзапрос из `client_backend/internal/store/identity.go`
- [x] T027 [US1] Схлопнуть владение до отметки «машина забрана» в `client_backend/internal/store/serverkey.go`; **ключ машины не трогать**
- [x] T028 [US1] Убрать `owner` из объекта личности в приветствии в `client_backend/internal/server/handlers.go`
- [x] T029 [US1] Убрать состояние `stateOwnerless` и предупреждение о бесхозном хранилище из `client_backend/internal/server/status.go` и `client_backend/internal/server/status_page.go`
- [x] T030 [US1] Убрать счётчик людей из `client_backend/internal/store/stats.go` и со страницы статуса
- [x] T031 [US1] Снять шаг приглашения человека из `client_backend/cmd/smoke/main.go`
- [x] T032 [US1] Обновить инварианты в `client_backend/CLAUDE.md`: снять пункты про приглашение человека, ожидание в строке, свипер, метку на соединении, seq-0 у двух событий, владение как ссылку
- [x] T033 [US1] **Гейт**: `go test -race ./...` на пересозданной базе; `cmd/smoke` проходит укороченный сценарий

### 3C. Клиент: удаление, от листьев к корню

- [x] T034 [P] [US1] Удалить `lib/presentation/pages/people_page/` целиком, `test/presentation/pages/people_page/` и 12 голденов
- [x] T035 [P] [US1] Удалить `lib/presentation/pages/pair_request_page/` целиком, `test/presentation/pages/pair_request_page/` и 4 голдена
- [x] T036 [P] [US1] Удалить `lib/data/sync/pair_request_service.dart` и `test/data/sync/pair_request_service_test.dart`
- [x] T037 [P] [US1] Удалить `lib/data/repository/person/` и `lib/domain/repository/person/`
- [x] T038 [P] [US1] Удалить `lib/domain/model/person/`
- [x] T039 [P] [US1] Удалить `lib/presentation/widgets/settings/app_owner_badge_widget.dart` и его голден
- [x] T040 [US1] Снять подписку на заявки и `_askNext` из `lib/presentation/app/app_root.dart`
- [x] T041 [US1] Снять `_forgetPairRequests` из `lib/data/repository/app/auth_repository_impl.dart`
- [x] T042 [US1] Снять ветку ожидания из `lib/data/sync/live_identity_handshake.dart`: развилку на `pending`, цикл переподачи, `approvalWait`/`approvalSlack`/`approvalCeiling`/`approvalPoll`, `waitingForOwner`, `_awaitPairOutcome`, `_outcomeOf`, `_refusalFor`. **Логику своего устройства — перезапуск канала, поколение приветствия — не трогать**
- [x] T043 [US1] Сократить `lib/domain/model/session/pair_refusal.dart` до двух значений
- [x] T044 [US1] Снять `notOwner`, `pairDeclined`, `pairTimeout` и их wire-коды из `lib/domain/exception/repository_exception.dart`
- [x] T045 [US1] Снять `personPairRequested` и `personPairResolved` из `lib/data/remote/socket/server_frame.dart` и `confirmPair` из `lib/data/remote/socket/nox_socket_client.dart`
- [x] T046 [US1] Снять `waitingForOwner`, `errorDeclined`, `errorNoAnswer` из `lib/presentation/pages/login_page/bloc/login_state.dart`, `_watchOwnerWait` из блока и соответствующие ветки из `login_page.dart`
- [x] T047 [US1] Вырезать `isOwner` сквозь слой сессии: `session_repository.dart`, `session_repository_impl.dart` (поток, ключ prefs, запись), `server_identity.dart`, `live_session_starter.dart`, `auth_repository_impl.dart`, `nox_socket_client.dart`, `live_identity_handshake.dart`
- [x] T048 [US1] Снять строку `People` и признак владельца из `lib/presentation/pages/settings_root_page/settings_root_page.dart`, его блока и состояния; убрать бейдж из `lib/presentation/widgets/settings/app_identity_card_widget.dart`
- [x] T049 [US1] Снять 19 ключей локализации многолюдности из `lib/l10n/app_en.arb` и `lib/l10n/app_uk.arb` — **наборы ключей должны остаться идентичными**
- [x] T050 [US1] Поправить тесты, задетые сквозняком: `test/data/repository/app/auth_repository_impl_test.dart`, `test/data/sync/live_identity_handshake_test.dart`, `test/presentation/pages/settings_root_page/bloc/settings_root_bloc_test.dart`, `test/utils/fake_session_repository.dart`, `test/data/remote/socket/nox_socket_client_test.dart`
- [x] T051 [US1] Перерисовать голдены настроек и карточки личности (уходит строка People и бейдж)
- [x] T052 [US1] **Гейт**: `make gate` зелёный

---

## Phase 4: User Story 3 — Шов для relay виден и честен (Priority: P1)

**Цель**: единственное добавление фазы — выключенная кнопка приглашения в двух местах.

**Независимая проверка**: открыть чат на узкой и широкой ширине; кнопка есть в шапке треда и в карточке чата, неактивна, подписана, нажатие не делает ничего.

- [x] T053 [US3] Добавить ключи `Invite a person`, `Available in a future version`, `People` в `lib/l10n/app_en.arb` и `lib/l10n/app_uk.arb`
- [x] T054 [US3] Добавить неактивное действие приглашения в шапку треда в `lib/presentation/widgets/chat/app_thread_header_widget.dart`, с текстовым именем для чтения с экрана; обе ширины
- [x] T055 [US3] Добавить секцию `People` с единственной строкой человека и выключенной кнопкой под ней в `lib/presentation/pages/chat_card_page/chat_card_body.dart`; человек читается через `resolveIdentity`, никакой новой сущности
- [x] T056 [P] [US3] Виджет-тесты: кнопка неактивна, нажатие не порождает ни навигации, ни снэкбара, действие в шапке имеет имя и объявлено недоступным
- [x] T057 [P] [US3] Голдены мобильный и десктопный для карточки чата с новой секцией
- [x] T058 [P] [US3] Голдены мобильный и десктопный для экрана переписки с новым действием в шапке
- [x] T059 [US3] **Гейт**: `make gate` и `make golden-verify` зелёные

---

## Phase 5: User Story 2 — Всё, что работало, продолжает работать (Priority: P1)

**Цель**: убедиться, что уборка ничего не сломала.

**Независимая проверка**: сквозной прогон на свежей базе и двух устройствах.

- [x] T060 [US2] Пройти `specs/037-local-only-phase/quickstart.md` целиком на свежей базе и двух устройствах, отметить каждый пункт
- [x] T061 [US2] Сверить счётчики тестов и голденов с базовыми из T002: уменьшение только за счёт удалённых, ни одного упавшего (SC-003)
- [x] T062 [US2] Проверить, что мёртвая команда получает отказ «неизвестная команда», а не пустой успех — тест уровня протокола в `client_backend/internal/server/`
- [x] T063 [US2] **Подметание (SC-002, SC-004)**: grep по `person`, `isOwner`, `owner`, `pairRequest`, `pair_declined`, `People` в `lib/`, `test/`, `client_backend/` и `docs/`; каждое оставшееся совпадение либо снять, либо объяснить письменно в отчёте фазы. Это единственная задача, доказывающая, что убрано **всё**, а не только то, что было в списке

---

## Phase 6: User Story 4 — Документы описывают тот мир, который есть (Priority: P2)

**Цель**: ни один документ не описывает многолюдность как действующую возможность.

- [x] T064 [P] [US4] Переписать продуктовую модель в `docs/design/spec/overview.md`: §Чаты, таблица решений, уникальность имени чата, правило про push «только свои чаты»
- [x] T065 [P] [US4] Переписать `termsContentBody` в `lib/l10n/app_en.arb` и `lib/l10n/app_uk.arb` — обещание общего пространства имеет юридический вес
- [x] T066 [P] [US4] Удалить `docs/design/spec/screens/people.md` и `docs/design/spec/screens/pair-request.md`; поправить `screens/README.md`, `top-level-screens.md`, `settings-root.md`
- [x] T067 [P] [US4] Описать выключенный шов в `docs/design/spec/screens/chat.md` и `docs/design/spec/screens/chat-card.md`, обе ширины
- [x] T068 [P] [US4] Снять кейс 2 и его следы из `docs/client-backend/architecture/authentication.md`
- [x] T069 [US4] Обновить `docs/client-backend/open-questions.md`: переоткрыть Q4 с новым решением и датой (конвенция раздела — не удалять, а пометить изменённым с причиной), снять Q15 и Q17, поднять Q13 до блокирующего, добавить вопросы, которые впервые ставит новая модель
- [x] T070 [P] [US4] Обновить `docs/client-backend/roadmap-stage2.md` (034 отменена), `docs/client-backend/demo-runbook.md` (сценарий круга из двух), `docs/client-backend/README.md`, `docs/README.md`
- [x] T071 [P] [US4] Поправить `docs/client-backend/protocol/wire-surface.md`: строку про экономию открытой модели («нет ростера, управления членством») и обоснование `chat.rename`
- [x] T072 [US4] Поправить `docs/design/system/nox-desktop-screens/screens/01-chats.md`: шапка треда десктопа описана как несущая **одно** info-действие, а фаза добавляет второе. Корпус — авторитет по десктопной раскладке (Принцип IV), и он обязан следовать решению владельца, а не наоборот
- [x] T073 [US4] Обновить корневой `CLAUDE.md`: продуктовая модель, заметки по 034, список экранов, описание фаз

---

## Phase 7: Polish

- [x] T074 Финальный прогон `make gate`, `make golden-verify` и `go test -race ./...` на чистом дереве
- [ ] T075 Слить `037-local-only-phase` в `develop` через `--no-ff`

---

## Dependencies

```
Phase 1 (Setup)
      ↓
Phase 2 (Контракт — блокирует обе стороны провода)
      ↓
Phase 3 (US1: 3A → 3B → 3C, строго по порядку)
      ↓
Phase 4 (US3: шов — только после того, как убрано лишнее)
      ↓
Phase 5 (US2: регрессия — проверяет всё предыдущее)
      ↓
Phase 6 (US4: документы — можно начинать параллельно с Phase 4)
      ↓
Phase 7 (Polish)
```

**Почему US2 (P1) идёт после US3 (P1)**: US2 — это проверка, а не работа. Её задачи проверяют результат всех предыдущих фаз, поэтому физически выполняются последними, хотя приоритет у неё тот же.

**Внутри Phase 3 порядок строгий**: провод → схема → клиент. Обратный порядок оставляет код, обращающийся к удалённым колонкам (см. [research.md](./research.md) §1).

**Внутри 3C порядок от листьев к корню**: экраны → блоки → репозитории → рукопожатие → сессионный слой. `isOwner` вырезается последним, потому что задевает девять файлов.

## Parallel Opportunities

- **T011–T013** — три независимых удаления файлов
- **T034–T039** — шесть независимых удалений на клиенте
- **T056–T058** — тесты и голдены шва
- **T064, T065, T066, T067, T068, T070, T071** — документы, разные файлы
- **Phase 6** может идти параллельно с Phase 4 **за одним исключением**: T065 и T053 правят одни и те же два ARB-файла, поэтому выполняются последовательно

## Implementation Strategy

**MVP — Phase 1 + Phase 2 + Phase 3.** После них продукт уже верен: сервер односоставный, лишнего нет, всё работает. Шов и документы можно доделывать отдельно.

**Инкремент — каждый гейт.** T022, T033, T052, T059 — четыре точки, в которых дерево заведомо зелёное. Если что-то сломалось, виновата ровно одна группа задач между двумя гейтами.

**Что не делаем в этой фазе**: relay, notification-сервер, настоящий состав участников чата, E2EE. TLS-пиннинг (фаза 036) — отдельная фича на своей ветке, после этой.
