---

description: "Task list for feature implementation"
---

# Tasks: ядро спаривания и аутентификации

**Input**: `/specs/032-pairing-core/` — [spec.md](./spec.md), [plan.md](./plan.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Тесты обязательны.** В этом проекте они не опция: гейт — `make gate` + `make golden-verify`, и конституция требует трёх категорий эталонов. Тестовые задачи стоят рядом со своим кодом, а не отдельной фазой в конце.

## Format: `[ID] [P?] [Story] Описание`

- **[P]** — можно вести параллельно (разные файлы, нет зависимости от незакрытых задач)
- **[US1/US2/US3]** — к какой пользовательской истории относится

---

## Phase 1: Контракт (сначала, до всякого кода)

Все задачи этой фазы правят один файл — `docs/client-backend/protocol/contract-draft.md`.

Принцип VII: нужное на проводе сначала попадает в контракт. Ничего из фаз 2+ не начинается, пока эта не закрыта.

- [ ] T001 Внести в `docs/client-backend/protocol/contract-draft.md` команды `pair`, `device.list`, `device.revoke`, `identity.setLabel` и событие `device.revoked` — формы кадров по [contracts/wire-changes.md](./contracts/wire-changes.md)
- [ ] T002 Записать в §2 контракта, что подписывается: `"nox/challenge/v1:" ‖ challenge` **сырыми байтами**, и почему префикс есть (разделение доменов), а base64-запись не подписывается (padding разошёлся бы между реализациями)
- [ ] T003 Закрепить в §3 контрольный вектор Ed25519 из [research.md §1](./research.md) — как в своё время закрепили `login_ref`: совпадение двух реализаций должно быть свойством провода, а не удачей
- [ ] T004 Изменить в §3 значение `device_key` (публичный ключ вместо непрозрачного идентификатора установки) и снять пометку «`signature` не проверяется»
- [ ] T005 **Удалить** `login_ref` из §3 целиком, вместе с формулой, вектором и всеми упоминаниями входа по идентификатору
- [ ] T006 Перенести `identity.created` с приветствия на ответ `pair` (§8.1 это предусматривал) и убрать поле из описания приветствия
- [ ] T007 **Вычеркнуть** из §8.1 `identity.labelAvailable` и `identity.completeOnboarding` с записью причины: имена людей не уникальны, а второй источник исхода онбординга разойдётся с первым
- [ ] T008 Добавить в §2.1 коды `invalid_token` и `token_expired` и записать, почему они разделены: у человека разные действия
- [ ] T009 Внести формат ссылки спаривания по [contracts/pairing-link.md](./contracts/pairing-link.md) отдельным разделом
- [ ] T010 Обновить строку 8.1 в таблице этапов: спаривание переезжает из «этап 2» в реализованное, с оговоркой, что кейсы 2 и 4 остаются за Q15/Q16

---

## Phase 2: Основание (блокирует все истории)

### Сервер

- [ ] T011 Добавить в `client_backend/migrations/001_init.sql` таблицу `server_identity` по [data-model.md](./data-model.md) — правится **на месте**, миграция до релиза одна
- [ ] T012 Добавить в `client_backend/migrations/001_init.sql` таблицу `pair_tokens`; `expires_at` **nullable**, потому что у claim срока нет
- [ ] T013 Изменить в `client_backend/migrations/001_init.sql` таблицу `devices`: добавить `platform`, переопределить смысл `device_key`; удалить `users.id_digest`
- [ ] T014 Создать `client_backend/internal/store/serverkey.go`: рождение пары ключей при первом запуске, чтение, автомат `claimed_at`
- [ ] T015 [P] Создать `client_backend/internal/store/pairing.go`: выпуск токена и **атомарное** сжигание. Имя файла не `tokens.go` — так уже называется файл про пропуска на передачу файлов в пакете `server`
- [ ] T016 [P] Тесты `client_backend/internal/store/pairing_test.go`: одноразовость, срок invite, отсутствие срока у claim, и **гонка двух одновременных предъявлений одного токена** — выиграть должен ровно один
- [ ] T017 [P] Тесты `client_backend/internal/store/serverkey_test.go`: ключ переживает перезапуск; claim принимается пока `claimed_at IS NULL` и не принимается после

### Клиент

- [ ] T018 Добавить `cryptography: ^2.9.0` в `pubspec.yaml` с комментарием, почему именно он (одна зависимость, чистый Dart, те же примитивы понадобятся для Q1)
- [ ] T019 Создать `lib/general/pairing/device_keys.dart`: генерация пары из семени, подпись challenge, хранение семени через `flutter_secure_storage` под `session.device_secret`
- [ ] T020 [P] Создать `lib/general/pairing/pairing_link.dart`: разбор и сборка ссылки по [contracts/pairing-link.md](./contracts/pairing-link.md); отказ разбора **отличим** от отказа токена
- [ ] T021 [P] Тесты `test/general/pairing/pairing_link_test.dart`: контрольный вектор, неизвестная версия, обрезанная строка, все три типа адреса, приём ссылки без схемы (человек вставил один фрагмент)
- [ ] T022 [P] Тесты `test/general/pairing/device_keys_test.dart`: подпись под фиксированным семенем совпадает с вектором из [research.md §1](./research.md) — это тот самый тест, который поймает подмену библиотеки или формата подписываемого
- [ ] T023 Расширить `lib/domain/repository/app/session_repository.dart` и `lib/data/repository/app/session_repository_impl.dart`: `deviceSecret()` вместо `deviceId()`; **удалить** `session.identifier` и `session.device_id`; `clear()` обязан стирать семя
- [ ] T024 [P] Тесты `test/data/repository/app/session_repository_impl_test.dart` на новое: семя рождается один раз и переживает чтение; `clear()` его стирает

**Контрольная точка:** сервер умеет ключ и токены, клиент умеет ключ и ссылку — ни одна история ещё не работает, но всё для них есть.

---

## Phase 3: User Story 1 — Хозяин забирает свой сервер (P1) 🎯 MVP

**Цель:** на свежем сервере человек предъявляет ссылку из вывода и получает работающий мессенджер.

**Независимая проверка:** [quickstart.md §2.2](./quickstart.md) — поднять чистый `noxd`, взять ссылку, предъявить, отправить сообщение.

### Сервер

- [ ] T025 [US1] Реализовать в `client_backend/internal/server/handlers.go` команду `pair`: сжечь токен, завести личность для `claim`, записать публичный ключ и `platform`
- [ ] T026 [US1] Провести в `client_backend/internal/server/ws.go` `pair` как **исключение** из правила «первая команда — hello»: неспаренному устройству нечем подписать challenge
- [ ] T027 [US1] Включить в `ws.go` проверку `signature` над `"nox/challenge/v1:" ‖ challenge`; неизвестный ключ и несошедшаяся подпись — `unauthenticated`
- [ ] T028 [US1] Переписать `client_backend/internal/store/identity.go`: личность ищется по ключу устройства, ветка `login_ref` удаляется целиком
- [ ] T029 [US1] Вернуть в `client_backend/internal/server/handlers.go` в ответе `pair` объект `identity` с `created`, считая его **от того, завели ли личность** — не от типа токена и не от факта успеха
- [ ] T030 [US1] Печатать в `client_backend/main.go` ссылку спаривания при первом запуске; локальной HTTP-страницы **не делать** (уточнение 2026-09-04)
- [ ] T031 [P] [US1] Тесты `client_backend/internal/server/pairing_test.go`: claim заводит личность и возвращает `created: true`; повторный claim отвергается; подпись проверяется; подделанная подпись отвергается
- [ ] T032 [P] [US1] Тест в `client_backend/internal/server/pairing_test.go`: устройство с ключом, которого сервер не знает, получает `unauthenticated` — это же поведение у пересобранного сервера

### Клиент

- [ ] T033 [US1] Реализовать команду спаривания в `lib/data/remote/socket/nox_socket_client.dart`: отправка `pair` до приветствия, разбор ответа
- [ ] T034 [US1] Подписывать challenge в приветствии в `lib/data/remote/socket/nox_socket_client.dart`; убрать отправку `login_ref`
- [ ] T035 [US1] Переписать `signIn` в `lib/data/repository/app/auth_repository_impl.dart` на предъявление ссылки: разобрать → спариться → взять исход → и только потом двигать навигацию. Порядок тот же, что выстроен фазой 031, и по той же причине
- [ ] T036 [US1] Заменить `lib/general/nox_qr_envelope.dart` на разбор ссылки спаривания либо удалить, если весь его смысл переехал в `pairing_link.dart`
- [ ] T037 [US1] Переделать `lib/presentation/pages/login_page/`: вставка и скан **ссылки** вместо идентификатора; тексты ошибок различают «ссылка не читается», «токен недействителен», «срок истёк»
- [ ] T038 [US1] Свести wide-ветку `lib/presentation/pages/login_page/login_page.dart` с `docs/design/system/nox-desktop-screens/`, narrow — с `nox-mobile-screens/`
- [ ] T039 [P] [US1] Тесты `test/presentation/pages/login_page/bloc/login_bloc_test.dart`: ожидание, три различимых отказа, успех никуда не навигирует сам
- [ ] T040 [P] [US1] Эталоны в `test/presentation/pages/login_page/login_page_golden_test.dart`: `goldenTest` и `goldenTestDesktop`, включая состояние ошибки разбора
- [ ] T041 [P] [US1] Тесты `test/data/repository/app/auth_repository_impl_test.dart`: `created: true` ведёт к выбору имени, `created: false` — нет; неудача спаривания не оставляет полусессии

**Контрольная точка:** MVP. Человек получает работающий мессенджер на своём сервере, и сервер его проверяет.

---

## Phase 4: User Story 2 — Второе устройство того же человека (P2)

**Цель:** одна личность, несколько устройств, одна история на всех.

**Независимая проверка:** [quickstart.md §2.4](./quickstart.md) — два клиента против одного `noxd`; сообщение с первого показано на втором своим.

### Сервер

- [ ] T042 [US2] Реализовать выпуск `invite-device` в `client_backend/internal/server/handlers.go`: токен привязан к личности выпустившего, живёт 10 минут
- [ ] T043 [US2] Обработать в `client_backend/internal/server/handlers.go` в `pair` токен типа `invite_device`: ключ добавляется **к той же личности**, ответ несёт `created: false`
- [ ] T044 [US2] Реализовать `identity.setLabel` в `client_backend/internal/server/handlers.go`: переименование обычной командой, эхо новым именем всем устройствам личности
- [ ] T045 [P] [US2] Тесты в `client_backend/internal/server/pairing_test.go`: приглашение одноразово; просроченное даёт `token_expired`, а израсходованное — `invalid_token`; два устройства оказываются у одной личности

### Клиент

- [ ] T046 [US2] Реализовать выпуск приглашения и его показ в `lib/presentation/pages/settings_root_page/`: QR через `qr_flutter` **и** копирование текстом — без второго Windows и Linux останутся без пути
- [ ] T047 [US2] Перевести переименование в `lib/presentation/pages/settings_root_page/bloc/settings_root_bloc.dart` на `identity.setLabel`; **удалить** `session.label_dirty` и вызов `LiveSessionStarter.restart()` при смене имени
- [ ] T048 [US2] Переделать поверхность «Your ID» в `lib/presentation/pages/settings_root_page/`: показ публичного `identity.id` вместо секрета, «показать QR» → приглашение устройства
- [ ] T049 [US2] Свести обе ветки `lib/presentation/pages/settings_root_page/settings_root_page.dart` со своими корпусами ширин
- [ ] T050 [P] [US2] Тесты `test/presentation/pages/settings_root_page/bloc/settings_root_bloc_test.dart`: переименование уходит командой и **не** перезапускает сессию
- [ ] T051 [P] [US2] Обновить эталоны в `test/presentation/pages/settings_root_page/settings_root_page_golden_test.dart`, обе ширины
- [ ] T052 [P] [US2] Тест в `test/data/repository/chat/message_repository_impl_test.dart`: сообщение, отправленное первым устройством, на втором опознано своим — оба знают один `author_id`

**Контрольная точка:** личность действительно переживает устройства, а не только на бумаге.

---

## Phase 5: User Story 3 — Потерянное устройство перестаёт быть дверью (P2)

**Цель:** отзыв как операция с обратным ходом; выход — её частный случай.

**Независимая проверка:** [quickstart.md §2.7](./quickstart.md) — отозвать одно устройство со второго, убедиться, что сессия порвана и подключение отклонено.

### Сервер

- [ ] T053 [US3] Реализовать `device.list` в `client_backend/internal/server/handlers.go`: ключ, платформа, момент привязки, момент последней связи
- [ ] T054 [US3] Реализовать `device.revoke` в `client_backend/internal/server/handlers.go`: удаление строки; отзыв несуществующего ключа — **успех**, конечное состояние достигнуто
- [ ] T055 [US3] Рвать в `client_backend/internal/server/ws.go` живое соединение отозванного ключа **сразу**, а не ждать его следующей попытки, и слать событие `device.revoked`
- [ ] T056 [US3] Тестом в `client_backend/internal/store/pairing_test.go` убедиться, что личность переживает отзыв последнего устройства — иначе кейсу восстановления не к чему будет прицепиться
- [ ] T057 [P] [US3] Тесты в `client_backend/internal/server/pairing_test.go`: отзыв рвёт сессию; отозванный ключ больше не подключается; повторный отзыв успешен; личность остаётся

### Клиент

- [ ] T058 [US3] Создать `lib/data/repository/device/` — список и отзыв поверх сокета, `RepositoryResult` как везде
- [ ] T059 [US3] Создать `lib/presentation/pages/devices_page/` с Freezed-BLoC: список, отметка текущего устройства, действие отзыва с подтверждением
- [ ] T060 [US3] Построить в `lib/presentation/pages/devices_page/devices_page.dart` narrow-ветку по `nox-mobile-screens/`, wide — по `nox-desktop-screens/`; на десктопе экран живёт панелью деталей настроек, как остальные листья
- [ ] T061 [US3] Обработать событие `device.revoked` в `lib/data/sync/live_session_starter.dart`: локальная очистка и возврат к предъявлению ссылки — тем же кодом, что и «сервер не знает мой ключ»
- [ ] T062 [US3] Перевести выход в `lib/data/repository/app/auth_repository_impl.dart` на отзыв своего ключа при живой связи; без связи очистка **безусловна**
- [ ] T063 [P] [US3] Тесты `test/presentation/pages/devices_page/bloc/devices_bloc_test.dart`: список, отзыв другого, отзыв себя
- [ ] T064 [P] [US3] Эталоны в `test/presentation/pages/devices_page/devices_page_golden_test.dart`: `goldenTest` **и** `goldenTestDesktop` — продуктовая страница обязана иметь пару
- [ ] T065 [P] [US3] Тест `test/data/repository/app/auth_repository_impl_test.dart`: выход без связи вычищает локально, не дожидаясь сервера

**Контрольная точка:** дыра, которую открыла история 2, закрыта.

---

## Phase 6: Документация и живая проверка

- [ ] T066 [P] Обновить `docs/design/spec/screens/2-1-login.md` (или как называется файл экрана входа): предъявление ссылки вместо идентификатора
- [ ] T067 [P] Обновить `docs/design/spec/screens/settings-root.md`: «Your ID» перестал быть секретом, «показать QR» стало приглашением
- [ ] T068 [P] Завести спеку нового экрана списка устройств в `docs/design/spec/screens/`
- [ ] T069 [P] Обновить `docs/design/system/nox-mobile-screens/screens/` — вход, настройки, новый экран
- [ ] T070 [P] Обновить `docs/design/system/nox-desktop-screens/screens/` — то же для широкой ширины
- [ ] T071 [P] Обновить `docs/design/spec/overview.md`: раздел про идентичность — идентификатора входа больше нет как понятия
- [ ] T072 [P] Записать в `CLAUDE.md` инварианты фазы: где живёт ключ сервера, почему отзыв удаляет строку, почему у claim нет срока, что подписывается
- [ ] T073 [P] Закрыть в `docs/client-backend/open-questions.md` то, что фаза закрыла, и обновить `docs/client-backend/roadmap-client-track.md`
- [ ] T074 Записать в `docs/blueprints/mobile/` desktop-fallback для хранения секретов — принцип III требует явной фиксации, раз подсистема платформенно-специфична
- [ ] T075 `make gate`
- [ ] T076 `make golden-verify` — объяснить каждый сдвиг эталона в сообщении коммита
- [ ] T077 `cd client_backend && go test ./...`
- [ ] T078 Живой сценарий [quickstart.md §2](./quickstart.md) целиком, двумя клиентами: §2.2 (главный), §2.3, §2.4, §2.5, §2.6 (гонка), §2.7, §2.8, §2.9, §2.10, §2.11 (подпись правда проверяется), §2.12 (идентификатора нет нигде)

---

## Зависимости и порядок

### Между фазами

- **Phase 1 (контракт)** — ни от чего не зависит и **блокирует всё остальное**. Это не формальность: обе реализации берут формы кадров оттуда дословно.
- **Phase 2 (основание)** — после контракта, блокирует все истории.
- **Phase 3 (US1)** — после основания. Единственная история, работающая на пустом сервере.
- **Phase 4 (US2)** — после US1 **по существу, а не по коду**: нечем выпустить приглашение, пока нет ни одного спаренного устройства.
- **Phase 5 (US3)** — после US2 по той же причине: нечего отзывать, пока устройство одно. Отзыв себя (выход) можно вести и после US1.
- **Phase 6** — после нужных историй.

### Внутри истории

Сервер → клиент невидимый → клиент экраны → эталоны. Клиенту нужен сервер, который уже отвечает; эталонам — экран, который уже верный.

### Что можно вести параллельно

- T015–T017 (токены и ключ сервера) параллельно T018–T022 (ключи и ссылка на клиенте) — разные языки, разные файлы, общий только контракт
- Внутри каждой истории все `[P]`-тесты идут вместе после своего кода
- Вся Phase 6 кроме T075–T078 — параллельно

---

## Стратегия

### MVP — только US1

Phase 1 → 2 → 3 даёт полностью рабочий продукт: человек забирает свой сервер, устройство проверяется по подписи, переписка работает. Это уже больше, чем есть сегодня, и уже закрывает главную дыру — секрет перестаёт ходить по рукам.

### Дальше приращениями

US2 добавляет второе устройство и делает реальностью то, ради чего личность отделяли от устройства фазой 030. US3 закрывает дыру, которую US2 открывает: без отзыва спаривание — операция без обратного хода.

**Останавливаться после US2 нельзя.** US1 самодостаточна, US1+US2 — нет: каждое утерянное устройство остаётся открытой дверью навсегда. Если фазу придётся резать, режется US2+US3 вместе, а не US3 отдельно.
