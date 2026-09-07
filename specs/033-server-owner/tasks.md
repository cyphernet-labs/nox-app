---

description: "Task list for feature 033 — the server knows its owner"
---

# Tasks: Сервер знает своего владельца

**Input**: Design documents from `/specs/033-server-owner/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/)

**Tests**: включены. Их требует сама спека (FR-010, SC-004, SC-005) и обязательный локальный гейт конституции — CI на паузе, и тесты единственное место, где регрессия ловится.

**Organization**: задачи сгруппированы по пользовательским историям. US2 идёт **раньше** US1, хотя обе P1: отметку в настройках нечем нарисовать, пока признак не доезжает от сервера.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: можно делать параллельно (разные файлы, нет незакрытых зависимостей)
- **[Story]**: US1 / US2 / US3 из [spec.md](./spec.md)

---

## Phase 1: Контракт (блокирует всё)

**Purpose**: Принцип VII — провод правится контрактом первым, до единой строки кода.

- [ ] T001 Внести поле `owner` в объект `identity` ответа на приветствие (§3) в `docs/client-backend/protocol/contract-draft.md`, обновив пример кадра
- [ ] T002 Внести то же поле в объект `identity` ответа на `pair` (§8A) в `docs/client-backend/protocol/contract-draft.md`, обновив пример кадра
- [ ] T003 Записать в §8A правила поля из `specs/033-server-owner/contracts/wire-changes.md`: отвечает про спрашивающего, описывает личность, присутствует всегда без `omitempty`, клиент не выводит владение сам
- [ ] T004 Уточнить в `docs/client-backend/protocol/contract-draft.md` §8A определение «сервер забран» — это наличие владельца; отдельной решающей отметки не существует, момент времени сервер помнит, но правила на него не смотрят
- [ ] T005 Отметить в `docs/client-backend/protocol/contract-draft.md` (§8A и таблица статусов §8), что `device.list` признаком владения **не** расширяется и вопрос возвращается в фазу 034

**Checkpoint**: контракт описывает провод, которого ещё нет в коде — дальше код догоняет контракт.

---

## Phase 2: Foundational — владелец в хранилище (блокирует все истории)

**Purpose**: понятие владельца в схеме и переключение трёх мест решения с `claimed_at` на владельца. Ни одна история без этого не начинается.

- [ ] T006 Добавить колонку `owner_user_id TEXT NULL REFERENCES users(user_id)` в таблицу `server_identity` в `client_backend/migrations/001_init.sql`, правкой **на месте** (пре-релизное правило); в комментарии таблицы записать, что наличие ссылки и есть «сервер забран», а `claimed_at` остаётся информацией для статусной страницы
- [ ] T007 Добавить `OwnerUserID string` в `store.ServerIdentity` и прочитать колонку в `readServerIdentity` в `client_backend/internal/store/serverkey.go`
- [ ] T008 Добавить в `client_backend/internal/store/serverkey.go` предикат «забран» поверх владельца и функцию простановки владельца внутри переданной транзакции; в комментарии — почему решение идёт от владельца, а не от `claimed_at`
- [ ] T009 Добавить `Owner bool` в `store.Identity` в `client_backend/internal/store/identity.go`; в комментарии объяснить отличие от `Created`: `Owner` описывает личность и потому устойчив, `Created` описывает ответ
- [ ] T010 Заполнить `Owner` в `ResolveIdentity` в `client_backend/internal/store/identity.go` — сравнением найденной личности с владельцем машины, без второго запроса за строкой машины, если её уже читали
- [ ] T011 В `client_backend/internal/store/pairing.go` в ветке `TokenClaim` заменить чтение `claimed_at` на чтение владельца: сервер занят, если владелец есть **и** устройств больше нуля
- [ ] T012 В `client_backend/internal/store/pairing.go` проставлять владельца в той же транзакции, что создаёт личность claim-путём, и **не** трогать владение на пути переприсоединения к существующей личности
- [ ] T013 В `client_backend/internal/store/pairing.go` заполнить `Owner` в возвращаемой `Identity` на всех трёх выходах ветки claim: новая личность, переприсоединение, повтор потерянного ответа (`pairedBy`)
- [ ] T014 В `client_backend/internal/store/pairing.go` заполнить `Owner` в ветке приглашения устройства — приглашённое устройство принадлежит той же личности, поэтому значение то же, что у неё
- [ ] T015 В `client_backend/internal/server/server.go` перевести `announceClaim` на владельца: ссылка печатается, пока владельца нет **или** устройств нет
- [ ] T016 В `client_backend/internal/server/server.go` добавить в проверку схемы на старте предупреждение о хранилище с личностями, но без владельца — без идентификатора личности в сообщении (Принцип I), сервер продолжает запуск

**Checkpoint**: `go build ./...` и `gofmt -l .` чисты; владение записано и читается, решения приняты по нему.

---

## Phase 3: US2 — признак владения доезжает до устройства (Priority: P1)

**Goal**: устройство узнаёт о владении от сервера в обоих кадрах и хранит услышанное.

**Independent Test**: два клиента против одного `noxd` — забравший сервер получает признак, приглашённое устройство той же личности получает такой же. Проверяется без единого экрана.

### Сервер — провод

- [ ] T017 [US2] Добавить `Owner bool` в `greetingIdentity` в `client_backend/internal/server/handlers.go` с тегом без `omitempty` и комментарием, почему пропавшее `false` недопустимо
- [ ] T018 [US2] Добавить `Owner bool` в `identity` (ответ на `pair`) в `client_backend/internal/server/handlers.go`, там же
- [ ] T019 [US2] Заполнить признак при сборке ответа на приветствие в `client_backend/internal/server/handlers.go` из `store.Identity.Owner`
- [ ] T020 [US2] Заполнить признак при сборке ответа на `pair` в `client_backend/internal/server/pairing.go` из `store.Identity.Owner`

### Сервер — тесты

- [ ] T021 [P] [US2] Тест в `client_backend/internal/store/pairing_test.go`: claim на пустом хранилище заводит личность, помечает её владельцем и возвращает `Owner: true`
- [ ] T022 [P] [US2] Тест в `client_backend/internal/store/pairing_test.go`: приглашённое устройство даёт `Owner: true` для той же личности — владение принадлежит человеку, а не аппарату
- [ ] T023 [P] [US2] Тест в `client_backend/internal/store/identity_test.go`: `ResolveIdentity` владельца возвращает `Owner: true`, а личности без владения — `false`
- [ ] T024 [P] [US2] Тест в `client_backend/internal/store/serverkey_test.go`: «забран» считается от владельца — хранилище с `claimed_at`, но без владельца считается незабранным
- [ ] T025 [US2] Тест в `client_backend/internal/server/pairing_test.go`: ответ на `pair` несёт владение в том же кадре, и приветствие следом несёт его же
- [ ] T026 [US2] Тест в `client_backend/internal/server/pairing_test.go`: поле присутствует в кадре даже со значением `false` — проверять по сырому JSON, а не по разобранной структуре, иначе `omitempty` пройдёт незамеченным

### Клиент — данные

- [ ] T027 [P] [US2] Добавить `bool? owner` в `lib/domain/model/session/server_identity.dart` с комментарием, почему тип нулевой: `null` = «сервер не заявил», и это не то же самое, что «не владелец»
- [ ] T028 [P] [US2] Добавить `bool? isOwner` в `lib/domain/model/app/session_model.dart` рядом с `authorId`
- [ ] T029 [US2] Разобрать `owner` из ответа на приветствие в `lib/data/remote/socket/nox_socket_client.dart`
- [ ] T030 [US2] Разобрать `owner` из ответа на `pair` в `lib/data/repository/app/auth_repository_impl.dart`
- [ ] T031 [US2] Расширить `adoptServerIdentity` признаком владения в `lib/domain/repository/app/session_repository.dart` и `lib/data/repository/app/session_repository_impl.dart`; хранить в `SharedPreferences` под ключом `session.is_owner`
- [ ] T032 [US2] Стирать `session.is_owner` в `clear()` и в `discardSignIn()` в `lib/data/repository/app/session_repository_impl.dart` — несостоявшийся вход не оставляет следа о владении
- [ ] T033 [US2] Передавать признак из приветствия в сессию в `_adoptGreeting` в `lib/data/sync/live_session_starter.dart`
- [ ] T034 [US2] Передавать признак из ответа на `pair` в сессию в `signIn` в `lib/data/repository/app/auth_repository_impl.dart` — владелец узнаёт о себе сразу, не дожидаясь приветствия

### Клиент — тесты

- [ ] T035 [P] [US2] Тест в `test/data/repository/app/session_repository_impl_test.dart`: признак сохраняется, переживает перезапуск и стирается выходом
- [ ] T036 [P] [US2] Тест в `test/data/remote/socket/nox_socket_client_test.dart`: приветствие без поля даёт `null`, а не `false` — «не заявлено» отличимо от «не владелец»
- [ ] T037 [US2] Тест в `test/data/sync/live_session_starter_test.dart`: признак из приветствия доезжает до сессии, и приветствие без сессии его не пишет

**Checkpoint**: `go test -race ./...` и `make gate` зелёные; признак доезжает и хранится, экранов ещё нет.

---

## Phase 4: US1 — хозяин видит, что машина его (Priority: P1)

**Goal**: отметка владения в корне настроек на обеих ширинах.

**Independent Test**: чистая установка, claim, выбор имени — отметка стоит рядом с именем; узкая и широкая ширина.

**Depends on**: Phase 3 (нечего рисовать без признака).

- [ ] T038 [P] [US1] Добавить ключ микрокопии отметки в `lib/l10n/app_en.arb` и `lib/l10n/app_uk.arb` — оба ARB обязаны иметь одинаковый набор ключей
- [ ] T039 [US1] Добавить необязательный признак владения в `AppIdentityCardWidget` в `lib/presentation/widgets/settings/app_identity_card_widget.dart`; отметка рядом с именем, на токенах и `ColorScheme`, без новых цветовых литералов
- [ ] T040 [US1] Провести признак через состояние настроек в `lib/presentation/pages/settings_root_page/bloc/settings_root_state.dart` и `settings_root_bloc.dart`, читая его из сессии
- [ ] T041 [US1] Передать признак в карточку из `lib/presentation/pages/settings_root_page/settings_root_page.dart` — на **обеих** ветках раскладки, узкой и широкой
- [ ] T042 [P] [US1] Тест в `test/presentation/pages/settings_root_page/bloc/settings_root_bloc_test.dart`: состояние несёт владение из сессии, а «не заявлено» не превращается в «не владелец»
- [ ] T043 [P] [US1] Виджет-тест в `test/presentation/widgets/settings/app_identity_card_widget_test.dart`: отметка есть у владельца, отсутствует у не-владельца и отсутствует при «не заявлено»
- [ ] T044 [US1] Обновить голдены виджета карточки идентичности в `test/presentation/widgets/settings/` — светлая и тёмная темы
- [ ] T045 [US1] Обновить мобильные и **десктопные** голдены корня настроек в `test/presentation/pages/settings_root_page/goldens/` (Принцип VI, FR-021)
- [ ] T046 [US1] Обновить голдены оболочки в `test/presentation/widgets/shell/goldens/` — десктопная вкладка настроек рисует ту же карточку

**Checkpoint**: `make golden-verify` зелёный; отметка видна на обеих ширинах.

---

## Phase 5: US3 — владение переживает потерю всех устройств (Priority: P2)

**Goal**: повторный claim возвращает того же человека с тем же владением; второй владелец не заводится.

**Independent Test**: claim → выход → повторный claim по новой ссылке; личность и владение те же, счётчик личностей не вырос.

**Depends on**: Phase 2 (поведение уже заложено там; здесь оно закрепляется тестами и проверяется целиком).

- [ ] T047 [P] [US3] Тест в `client_backend/internal/store/pairing_test.go`: повторный claim на сервере без устройств переприсоединяет к существующей личности и **сохраняет** за ней владение; вторая личность не заводится
- [ ] T048 [P] [US3] Тест в `client_backend/internal/store/pairing_test.go`: claim на сервере с живым устройством отвергается, владелец не меняется
- [ ] T049 [P] [US3] Тест в `client_backend/internal/store/serverkey_test.go`: хранилище с личностями, но без владельца считается незабранным, и владелец по «самой ранней» строке **не** выбирается
- [ ] T050 [US3] Тест в `client_backend/internal/server/pairing_test.go`: сквозной путь claim → отзыв последнего устройства → повторный claim; тот же `identity.id`, `owner: true`, `created: false`

**Checkpoint**: `go test -race ./...` зелёный; редкий необратимый путь закреплён.

---

## Phase 6: Polish — документация и живая проверка

**Purpose**: привести доки в соответствие коду (Принцип II) и убедиться, что путь работает не только в тестах.

- [ ] T051 [P] Обновить `client_backend/CLAUDE.md`: понятие владельца, «забран» считается от владельца, `claimed_at` больше не решает — в разделе намеренных умолчаний
- [ ] T052 [P] Обновить карту файлов в `client_backend/CLAUDE.md` — `serverkey.go` теперь хранит и владельца
- [ ] T053 [P] Обновить `docs/design/spec/screens/settings-root.md`: блок имени несёт отметку владения
- [ ] T054 [P] Обновить `docs/design/spec/top-level-screens.md` — экран 7.1
- [ ] T055 Отметить фазу 033 как смёрженную в `docs/client-backend/roadmap-stage2.md`
- [ ] T056 Расширить живой прогон в `test/live/pairing_live_probe.dart` проверкой признака владения после claim
- [ ] T057 Прогнать `quickstart.md` вживую против настоящего `noxd` на двух устройствах: US1, US2, US3 и отрицательные проверки
- [ ] T058 Финальный гейт: `make gate`, `make golden-verify`, `cd client_backend && go vet ./... && go test -race ./...`

---

## Зависимости

```
Phase 1 (контракт) ──→ Phase 2 (хранилище) ──→ Phase 3 US2 (провод + данные) ──→ Phase 4 US1 (экран)
                                            └──→ Phase 5 US3 (тесты пути)
                                                                              Phase 6 (доки, живой прогон)
```

- **Phase 1 блокирует всё**: Принцип VII не допускает кода раньше контракта.
- **Phase 2 блокирует все истории**: без владельца в хранилище нечего возвращать и нечего показывать.
- **US1 зависит от US2**, хотя обе P1: отметку нечем нарисовать без признака.
- **US3 почти целиком тесты**: поведение заложено в Phase 2, здесь оно закрепляется — но закрепляется обязательно, потому что путь необратимый.
- **Phase 6** идёт последней и целиком.

## Параллельные возможности

| Группа | Задачи | Почему параллельны |
|---|---|---|
| Тесты хранилища | T021–T024 | разные файлы, ни один не правит код |
| Модели клиента | T027, T028 | разные файлы, freezed-типы независимы |
| Тесты клиента | T035, T036 | разные файлы |
| Тесты US3 | T047–T049 | разные файлы, читают уже готовый код |
| Документация | T051–T054 | четыре разных файла |

Внутри `pairing.go` (T011–T014) параллельности нет: один файл, и правки пересекаются.

## Стратегия

**MVP — Phase 1 + Phase 2 + Phase 3 (US2).** Это уже осмысленно: владелец назван, записан и доезжает до устройства, а фазы 034 и 035 получают то, ради чего 033 существует. Отметка в настройках (US1) — то, что делает фазу видимой человеку, и идёт сразу следом.

**US3 не откладывается**, несмотря на P2: путь редкий, но необратимый, а его поведение уже заложено в Phase 2 — оставить его без тестов значит унести незакреплённым ровно то, что дороже всего сломать.
