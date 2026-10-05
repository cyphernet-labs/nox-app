---

description: "Задачи фичи 043 — файлы с докачкой в обе стороны"
---

# Tasks: Файлы с докачкой — большой файл доходит и через Tor

**Input**: `specs/043-resumable-files/` — spec.md, plan.md, research.md, data-model.md, contracts/wire-files.md, contracts/client-seams.md, quickstart.md

**Prerequisites**: plan.md, spec.md (US1–US4), research.md, data-model.md, contracts/

**Tests**: обязательны (правила проекта).
- Go — `go test -race ./...`, предел застоя, шаг точки сохранения и ожидание писателя задаются полями `Server` через `openStack(..., tweak)`.
- Dart — unit и bloc. Настоящий источник данных проверяется против локального TLS-сервера на фикстурах пиннинга, по образцу `test/data/remote/socket/transports_are_pinned_test.dart`: `HttpOverrides.global = null`, `valid.pem` + `server_key.pem`, `fingerprint.txt`.
- Голдены не меняются, но `make golden-verify` обязателен.
- Каждая задача с кодом проверяется тестом, который падает без неё.

**Organization**: контракт → сервер → приложение → живой зонд → документы. Внутри истории тесты пишутся первыми.

## Format: `[ID] [P?] [Story] Description`

- **[P]** — можно делать параллельно: разные файлы, нет зависимостей
- **[Story]** — история из spec.md (US1…US4)

---

## Phase 1: Setup

- [X] T001 Внести дельту §7 в `docs/client-backend/protocol/contract-draft.md` по `contracts/wire-files.md` (Принцип VII, FR-015):
  - таблица REST в §1 — `PUT` несёт остаток от `received`, `GET` — с `Range`/`If-Range`;
  - §7 — запрос `{name, size, mime, file_id?}` и ответ с `received` (наличие поля — признак поддержки); отказы продолжения `not_found`, `invalid_request`, `internal`; `PUT` с остатком и кодами `204`/`404`/`408`/`409`/`413`/`400`; пустой `PUT` завершает; правило докачки `GET` (`Range` + `If-Range` с `Last-Modified`, `206`/`200`/`416`); время — только застой 60 с; незаконченное хранится по правилу суток;
  - дополнение к §9 п. 6 о ручке продолжения в записи очереди.
  Номер схемы не поднимать.

---

## Phase 2: Foundational

Общее для нескольких историй: лестница пауз (очередь и скачивание) и поколение передач (отмена при выходе, сбросе и смене пути).

- [X] T002 [P] Вынести лестницу пауз из `lib/data/sync/outbox_service.dart` в новый `lib/data/sync/retry_ladder.dart`:
  - `RetryLadder.pause(int attempts)` = `min(30 с, 1 с × 2^(attempts−1))` ±20 %, `Random` подставляется;
  - `RetryLadder.refusalLimit = 10`;
  - `OutboxService` берёт их оттуда, поведение не меняется.
  Тест `test/data/sync/retry_ladder_test.dart`: границы, рост вдвое, потолок 30 с, джиттер в пределах ±20 %.
- [X] T003 [P] Поколение передач в `lib/data/remote/api_client.dart`:
  - `CancelToken get transferToken` (текущее поколение) и `void cancelTransfers()` — отменяет текущее поколение и заводит новое;
  - `FileRemoteDataSource.cancelTransfers()` в интерфейсе `lib/data/remote/datasource/file_remote_data_source.dart`, у настоящего источника — через `ApiClient`, у мока — ничего.
  Тест в `test/data/remote/api_client_test.dart` против локального TLS-сервера на фикстурах: запрос с токеном поколения, идущий во время `cancelTransfers()`, кончается отменой, а следующий проходит.

**Checkpoint**: общая основа готова, истории можно начинать.

---

## Phase 3: User Story 1 — Отправить большой файл вне дома (Priority: P1) 🎯 MVP

**Goal**: загрузка продолжается с байта, которого у сервера нет, — после обрыва, после перезапуска и на медленном пути; кольцо показывает долю всего файла.

**Independent Test**: начать загрузку, оборвать посреди и вернуть связь; затем перезапустить посреди передачи — сервер получает только недостающее, сообщение уходит (quickstart: живой зонд, шаги 1–2; стенд, сценарии 1–3).

### Tests for User Story 1 — сервер

- [ ] T004 [P] [US1] `client_backend/internal/blob/blob_test.go`:
  - `Resume(id, 0)` на новом id создаёт часть;
  - запись плюс `Checkpoint()` записывает длину в `<id>.synced`;
  - `Received`: часть длиннее `synced` → `synced`; нет `<id>.synced` → 0; часть короче `synced` → длина части;
  - `Resume(id, offset)` отказывает, когда `Received < offset`;
  - `Resume` на более длинной части сначала опускает `<id>.synced` до `offset`, потом обрезает часть; у новой загрузки `<id>.synced` не появляется до первой точки сохранения;
  - `Suspend()` ставит точку и оставляет часть;
  - `Finalize`, `Abort` и `Remove` убирают `<id>.synced`;
  - id, похожие на обход каталога, по-прежнему отвергаются.
- [ ] T005 [P] [US1] `client_backend/internal/server/tokens_test.go`: токен загрузки несёт смещение, `consume` возвращает id файла и смещение; у токена скачивания смещение 0; одноразовость и срок — как прежде.
- [ ] T006 [P] [US1] Новый `client_backend/internal/server/writers_test.go`:
  - `take` на свободном файле регистрирует писателя;
  - второй `take` вызывает прерывание первого и возвращается, когда тот отпустил;
  - если не отпустил за `preemptWait` — `ok == false`;
  - `interrupt(fileID, wait)` вызывает прерывание держателя и возвращается, когда тот отпустил, или по истечении `wait` — ничего не регистрируя;
  - `release` вытесненного писателя не снимает регистрацию нового.
  Всё под `-race`.
- [ ] T007 [US1] `client_backend/internal/server/files_test.go`. Помощники: `uploadBegin` с `file_id`, чтение `received`, `PUT` с обрывом после N байт, «висящий» `PUT` (соединение открыто, байты не идут). Короткие `stallTimeout`, `checkpointBytes`, `preemptWait` и `continuationWait` задаются через `tweak` в `openStack`. Случаи:
  - (a) у новой загрузки в ответе `received: 0`;
  - (b) `PUT`, оборванный клиентом на N байтах, оставляет их: продолжение отвечает тем же `file_id` и `received == N`; `PUT` остатка даёт `204`, байты на диске равны отправленным (SC-002);
  - (c) продолжение загруженного, но не привязанного файла — `received == size`; пустой `PUT` с его токеном — `204`;
  - (d) продолжение неизвестного id, привязанного к сообщению и вычищенного — `not_found`; с другим `size`, `name` или `mime` — `invalid_request`;
  - (e) `PUT`, переставший слать байты дольше `stallTimeout`, кончается `408`, полученное сохранено, обработчик вернулся;
  - (f) висящий `PUT` прерывается продолжением: оно отвечает за `continuationWait` точным `received`, следующий `PUT` проходит; писатель, который не отпускает файл (подменённое прерывание), не заставляет продолжение ждать дольше `continuationWait` и не даёт ошибки — ответ несёт надёжно сохранённую длину;
  - (g) при малом `checkpointBytes` во время идущего `PUT` `<id>.synced` растёт ступенями;
  - (h) `PUT` больше остатка → `413` и откат `received` к смещению токена; чистый короткий `PUT` → `400`, байты сохранены;
  - (i) часть усечена ниже смещения выданного токена → `PUT` получает `404`;
  - (j) расширить `TestOrphanSweepRemovesAbandonedUploads`: старая незаконченная загрузка уходит вместе с `<id>.part` и `<id>.synced`;
  - (k) обновить отрицательные случаи `TestStoryOneAttachmentChain` под новые правила (`413` — ничего от этого запроса, `400` — байты в части, готовых байтов нет);
  - (l) `PUT`, медленно, но непрерывно шлющий байты дольше `stallTimeout`, доходит до `204` (FR-009, SC-004);
  - (m) незаконченная загрузка переживает перезапуск сервера: новый `openStack` над той же базой и каталогом, продолжение отвечает тем же `received`, остаток доходит (FR-004);
  - (n) через `newTestServerLogging`: объявленное имя файла не встречается в логе ни при загрузке, ни при продолжении, ни при обрыве (FR-016).

### Implementation for User Story 1 — сервер

- [ ] T008 [US1] `client_backend/internal/blob/blob.go`:
  - `Resume(id, offset)`, `Received(id)`, `(*Upload).Checkpoint()`, `(*Upload).Suspend()`;
  - `<id>.synced` пишется атомарно (временный файл + `Rename` внутри `os.Root`) и только после `fsync` части; `Resume` опускает его до `offset`, если тот больше, а новой загрузке не пишет ничего;
  - `Finalize`, `Abort` и `Remove` убирают `<id>.synced`;
  - `Create` либо становится `Resume(id, 0)`, либо уходит; места вызова и тесты обновить (research §3, data-model).
- [ ] T009 [US1] `client_backend/internal/server/tokens.go`: поле `offset` в `tokenEntry`; `issue(fileID, op, offset)`, `consume` возвращает `(fileID, offset, ok)`; места вызова обновить.
- [ ] T010 [US1] Новый `client_backend/internal/server/writers.go`:
  - реестр `uploadWriters` — мьютекс и `map[fileID]*writer{interrupt func(), done chan struct{}}`;
  - `take(fileID, interrupt)` (для `PUT`) прерывает прежнего писателя и ждёт его до `preemptWait`, возвращает `(release func(), ok bool)`;
  - `interrupt(fileID, wait)` (для продолжения) прерывает прежнего писателя и ждёт его не дольше `wait`, ничего не регистрируя;
  - комментарий: инфраструктурная блокировка того же класса, что хранилище токенов.
- [ ] T011 [US1] `client_backend/internal/server/server.go`: поля `stallTimeout` (60 с), `checkpointBytes` (4 MiB), `preemptWait` (5 с, для `PUT`), `continuationWait` (1 с, для продолжения: обработчик команды сокета не должен держать цикл чтения, который читает и понги) и `writers`; значения по умолчанию в `New`.
- [ ] T012 [US1] `handleFileUploadBegin` в `client_backend/internal/server/files.go`:
  - необязательный `file_id`;
  - продолжение: нет строки или `message_id != NULL` → `not_found`; `name`/`size`/`mime` не те → `invalid_request`; `uploaded` → `received = size`; иначе `writers.interrupt(fileID, continuationWait)` и `received = blob.Received` — отказа из-за ожидания нет;
  - токен со смещением;
  - `received` в ответе всегда;
  - лог `upload resumed file=… from=…` — без имени.
- [ ] T013 [US1] Переписать `handlePutFile` в `client_backend/internal/server/files.go`:
  - токен → (id, offset); строки нет → `404`;
  - файл уже загружен: `offset == size` → `204`, иначе `404`;
  - `writers.take` (не дождались → `409`); `blob.Resume(id, offset)` (надёжно меньше `offset` → `404`);
  - чтение тела со сроком застоя: перед каждым `Read` — `SetReadDeadline(now + stallTimeout)`; прерывание ставит срок `now` под тем же мьютексом;
  - `MaxBytesReader(size − offset)`; точка сохранения каждые `checkpointBytes`;
  - исходы: всё пришло → `Finalize` + `MarkUploaded` → `204`; `MaxBytesError` → откат к `offset` → `413`; чистый короткий конец → `Suspend` → `400`; застой → `Suspend` → `408`; обрыв или прерывание → `Suspend`, лог `upload interrupted file=… at=…`; ошибка записи → `Abort` → `500`;
  - убрать `transferTimeout`.

### Tests for User Story 1 — приложение

- [ ] T014 [P] [US1] Новый `test/data/mapper/chat/outbox_mapper_test.dart`: три поля `uploadFileId`/`uploadSourceSize`/`uploadSourceModifiedAt` (мс) ↔ `UnfinishedUpload`; без любого из трёх — `null`; JSON записи, сделанной до 043, читается.
- [ ] T015 [P] [US1] `test/data/repository/chat/outbox_repository_impl_test.dart`:
  - `noteUpload` хранит и забывает ручку;
  - `attachFile(fileId)` забывает её;
  - `markPending` и `recordFailure` её сохраняют;
  - `pending()` и `watchQueue` её несут.
- [ ] T016 [P] [US1] Новый `test/data/remote/datasource/real/real_file_remote_data_source_test.dart`, часть загрузки.
  - **Поддельный сокет** (`implements NoxSocketClient`, остальное — `noSuchMethod`): `uploadBegin` шлёт `file_id` только при продолжении; `received` разбирается, а без поля — `null`.
  - **Против локального TLS-сервера**:
    - `putBytes(offset)` шлёт ровно байты `[offset, size)` с `Content-Length = size − offset`, прогресс — `(offset + отправлено, size)`;
    - `offset == size` — пустое тело;
    - коды: `204` — успех; `404` → `passRejected`; `413`/`400` → `sizeMismatch`; `408`/`409`/`500` → `connection`;
    - сервер перестал читать тело → сторож застоя (короткий предел через `forTest`) отменяет с `connection` раньше любых сроков Dio;
    - сервер читает медленно, но непрерывно дольше предела застоя — `PUT` доходит до `204` (FR-009);
    - `cancelTransfers()` посреди `PUT` → `connection`.
- [ ] T017 [P] [US1] Новый `test/data/remote/datasource/mock/mock_file_remote_data_source_test.dart`:
  - продолжение известной незаконченной загрузки отвечает тем же id и `received`;
  - неизвестный id → `not_found`;
  - `putBytes(offset)` дописывает;
  - израсходованный пропуск бросает `passRejected` — сегодня мок молча возвращается.
- [ ] T018 [US1] `test/data/repository/file/file_repository_impl_test.dart`, загрузка. `_FakeSource` получает продолжение и записывает порядок вызовов.
  - (a) Новая загрузка на сервере с продолжением: `onUnfinished` получает `{fileId, size, mtime}`, и его `Future` завершается раньше первого байта.
  - (b) С `from` в `uploadBegin` идёт `file_id`, `PUT` начинается с `received`, первым сообщается `received/size`.
  - (c) Сервер забыл загрузку (`not_found`): `onUnfinished(null)`, затем новая загрузка в том же вызове, итог — успех.
  - (d) Исходник изменился (размер или время) → `notFound`, сервер не спрашивается.
  - (e) Исходника нет → `notFound`; `FileSystemException` при `stat` превращается в `notFound` раньше, чем `execute` залогирует: перехватывающий `LogRepository` не видит пути исходника ни в одной строке (FR-016).
  - (e2) Исходник изменился во время `PUT` (поддельный источник меняет файл посреди передачи) → после `PUT` слепок не сходится → `notFound`, id не возвращается, даже если `PUT` удался.
  - (f) Старый сервер (`received == null`): `onUnfinished(null)`, файл целиком с нуля.
  - (g) Первый `404` — одна новая просьба продолжения в том же вызове; второй подряд → `internal`.
  - (h) `received == size` → пустой `PUT`, затем id.
  - (i) Обновить существующие тесты: «отказ пропуска — новое объявление» становится «продолжение того же файла», а для старого сервера — по-прежнему новое объявление. Проверка предела 100 MiB до первого байта остаётся как есть (FR-013).
- [ ] T019 [US1] `test/data/sync/outbox_service_test.dart`, группа `attachments`:
  - ручка из записи передаётся как `from`;
  - ручку, о которой сообщил репозиторий, очередь записывает до байтов;
  - новый `OutboxService` над тем же хранилищем (перезапуск) продолжает с записанной ручкой, а не объявляет заново;
  - окончательный отказ загрузки (`notFound`) забывает ручку;
  - подтверждённая загрузка забывает ручку;
  - сразу после ответа на продолжение передача пузыря показывает `received/size`, а не 0.

### Implementation for User Story 1 — приложение

- [ ] T020 [P] [US1] Новый `lib/domain/model/file/unfinished_upload.dart` (freezed): `fileId`, `sourceSize`, `sourceModifiedAt`.
- [ ] T021 [US1] Очередь:
  - `lib/domain/model/chat/outbox_entry.dart` — `UnfinishedUpload? upload`;
  - `lib/data/entity/chat/outbox_entity.dart` — три необязательных поля;
  - `lib/data/mapper/chat/outbox_mapper.dart`;
  - `lib/domain/repository/chat/outbox_repository.dart` и `lib/data/repository/chat/outbox_repository_impl.dart` — `noteUpload`, а `attachFile` ещё и забывает ручку.
- [ ] T022 [US1] Провод и источник данных:
  - `lib/data/entity/file/upload_ticket_wire_entity.dart` — `received: int?`;
  - в `lib/data/remote/datasource/file_remote_data_source.dart` — `uploadBegin(fileId:)` и `putBytes(offset:)`;
  - `real/real_file_remote_data_source.dart`:
    - `Content-Length` остатка, `file.openRead(offset)`, прогресс `offset + sent`;
    - сторож застоя: таймер перезапускается на каждом `onSendProgress`, отменяет свой `CancelToken`; предел 45 с, конструктор `forTest` задаёт короче;
    - `receiveTimeout` запроса = предел застоя;
    - свой токен связан с `ApiClient.transferToken`;
  - `mock/mock_file_remote_data_source.dart` — продолжение и `passRejected` на израсходованный пропуск.
- [ ] T023 [US1] `lib/domain/repository/file/file_repository.dart` — `upload(from:, onUnfinished:)`; `lib/data/repository/file/file_repository_impl.dart` — алгоритм research §7:
  - слепок исходника — перед попыткой и после каждого `PUT`; ошибки `dart:io` на исходнике → `notFound`;
  - `not_found` → новая загрузка; старый сервер → целиком;
  - один повтор после `404`, второй → `internal`;
  - прогресс с `received`;
  - в логах только id и смещения.
- [ ] T024 [US1] `lib/data/sync/outbox_service.dart`, `_uploadFor`:
  - `from: entry.upload`, `onUnfinished` → `_outbox.noteUpload`;
  - окончательный отказ → `noteUpload(null)`.
  Документ `lib/domain/model/file/attachment_transfer.dart`: перезапуск продолжает с того, что есть у сервера.

**Checkpoint**: загрузка продолжается после обрыва и перезапуска, на любой скорости.

---

## Phase 4: User Story 2 — Получить большой файл вне дома (Priority: P1)

**Goal**: скачивание продолжается с того, что уже на устройстве, — после обрыва и перезапуска. Готовым считается только файл, совпавший с сервером. Скачивание, начатое на 5.3, идёт и после закрытия экрана.

**Independent Test**: начать скачивание, оборвать посреди, вернуть связь; перезапустить посреди скачивания — устройство просит только недостающее, файл целый (quickstart: зонд, шаг 4; стенд, сценарии 5–8).

### Tests for User Story 2

- [ ] T025 [P] [US2] `client_backend/internal/server/files_test.go`:
  - `GET` медленно, но непрерывно читающему клиенту дольше `stallTimeout` — доходит целиком;
  - клиент, переставший читать дольше `stallTimeout`, обрывается, обработчик вернулся;
  - `If-Range` с `Last-Modified` первого ответа → `206` с остатком, с другой датой → `200` целиком.
- [ ] T026 [P] [US2] `test/data/remote/datasource/real/real_file_remote_data_source_test.dart`, часть скачивания (локальный TLS-сервер):
  - `offset == 0` — без `Range`, `200` → весь файл, `total` из `Content-Length`, валидатор из `Last-Modified`;
  - `offset > 0` с валидатором — уходят `Range` и `If-Range`; `206` → остаток, `total` из `Content-Range`; `200` вопреки `Range` → весь файл;
  - `416` → `staleRange`; `404` → `passRejected`;
  - остановка посреди тела → `connection` после короткого предела; `cancelTransfers()` посреди тела → `connection`;
  - медленное, но непрерывное тело дольше предела застоя доходит целиком (FR-009).
- [ ] T027 [P] [US2] `test/data/remote/datasource/mock/mock_file_remote_data_source_test.dart`: `openBytes` с `offset` и валидатором отдаёт остаток; без валидатора — весь файл.
- [ ] T028 [US2] `test/data/repository/file/file_repository_impl_test.dart`, скачивание:
  - (a) обрыв посреди тела оставляет `.part` и `.part.tag`;
  - (b) следующая попытка просит от длины части с записанным валидатором и дописывает — в том числе новым экземпляром `FileRepositoryImpl` над тем же каталогом кэша (перезапуск, FR-007);
  - (c) `200` → часть обрезана, новый `.part.tag` записан до первого байта (поддельный источник проверяет порядок), тело с нуля;
  - (d) `416` → часть и тег выброшены, одна немедленная новая попытка с нуля, отказом не считается;
  - (e) часть без тега выбрасывается;
  - (f) в конце длина ≠ `expectedSize` → оба выброшены, `internal`;
  - (g) `attachmentGone`/`notFound` окончательны; первый `404` — новая просьба, второй → `internal`;
  - (h) прогресс `(offset + принято)/total`;
  - (i) одна попытка на файл: второй вызов присоединяется и сразу слышит последнюю долю;
  - (j) `cancelTransfers()` прерывает попытку с `connection`;
  - (k) `clean()` убирает части и теги (FR-017);
  - обновить «a torn transfer leaves NOTHING that looks like a cache hit»: готового файла нет, а часть теперь остаётся.
- [ ] T029 [P] [US2] Новый `test/data/sync/attachment_download_service_impl_test.dart` (поддельные `FileRepository` и `MessageRepository`, `FixedSessionPhaseService`, короткая лестница через `forTest`):
  - одна передача на файл: второй `fetch` присоединяется и сразу получает последнюю долю;
  - 15 обрывов подряд, затем успех — успех, путь записан (обрывы не исчерпывают);
  - паузы идут по лестнице; фаза, ставшая текущей, будит ждущий повтор сразу;
  - успех записывает `attachLocalFile(messageId)`, даже если слушатель ушёл;
  - `attachmentGone`/`notFound` кончают сразу;
  - отказы (`internal`, `rateLimited`) кончают скачивание с `internal` после `RetryLadder.refusalLimit`, а обрывы в этот счёт не идут;
  - `reset()` останавливает ждущие циклы, вызывает `cancelTransfers()` и ждёт их.
- [ ] T030 [P] [US2] `test/data/sync/attachment_prefetch_service_test.dart`: подкачка идёт через сервис скачивания и путь сама не пишет; пока сервис повторяет, передача картинки не кончается; картинка с исчерпанной автоматикой не запрашивается на следующем обновлении, а запрашивается снова по `retryNow` (возвращение канала).
- [ ] T031 [P] [US2] `test/presentation/pages/file_view_page/bloc/file_view_bloc_test.dart`:
  - скачивание идёт через сервис;
  - пока сервис повторяет после обрывов, состояние `downloading` с прогрессом, без `failed`;
  - блок закрыт посреди скачивания — сервис всё равно завершает и записывает путь;
  - новый блок того же файла присоединяется и начинает с последней доли;
  - `gone` — как прежде.
- [ ] T032 [P] [US2] Порядок сброса: `test/data/repository/app/auth_repository_impl_test.dart` (выход) и `test/data/sync/live_session_starter_test.dart` (смена мира) — `AttachmentDownloadService.reset()` вызывается раньше `FileRepository.clean()`.

### Implementation for User Story 2

- [ ] T033 [US2] `client_backend/internal/server/files.go`, `handleGetFile`: обёртка над `ResponseWriter` продлевает `SetWriteDeadline(now + stallTimeout)` перед каждой записью и прячет `ReadFrom`, чтобы каждая запись шла через неё; `Last-Modified` остаётся от `ServeContent`.
- [ ] T034 [US2] Провод скачивания:
  - `FileTransferFailure.staleRange` в `lib/data/exception/file_transfer_exception.dart`;
  - `FetchedBytes` и `openBytes(downloadPath:, offset:, validator:)` вместо `getBytes` в `lib/data/remote/datasource/file_remote_data_source.dart`;
  - настоящий источник — `dio.get` с `ResponseType.stream`:
    - `Range` и `If-Range` только при `offset > 0` и валидаторе;
    - `receiveTimeout` = предел застоя, токен связан с поколением;
    - коды: `200`/`206` → `FetchedBytes`, `416` → `staleRange`, `404` → `passRejected`, остальное → `connection`;
  - мок — остаток сохранённого файла.
- [ ] T035 [US2] `lib/domain/repository/file/file_repository.dart` — `download(expectedSize:)` и `cancelTransfers()`. В `lib/data/repository/file/file_repository_impl.dart` переписать `_downloadOnce` по research §6:
  - часть и тег, порядок записи;
  - `416` — одна немедленная попытка;
  - сверка размера;
  - часть остаётся при неудаче;
  - `lastFraction` в `_SharedDownload`.
- [ ] T036 [US2] Сервис скачивания: новый `lib/domain/service/attachment_download_service.dart` и `lib/data/sync/attachment_download_service_impl.dart` (`@LazySingleton(as: AttachmentDownloadService, env: [dev, prod, test])`) — research §8 и contracts/client-seams.md:
  - `RetryLadder`;
  - пробуждение по фазе `SessionPhaseService`;
  - предел отказов;
  - `attachLocalFile`;
  - `reset()`.
- [ ] T037 [US2] `lib/data/sync/attachment_prefetch_service.dart` — через сервис скачивания: свою запись пути убрать; окончательные отказы — в `_hopeless`, как прежде; исчерпанная картинка ждёт `retryNow`, а не паузы в 15 с (research §8).
- [ ] T038 [US2] `lib/presentation/pages/file_view_page/bloc/file_view_bloc.dart` — через `AttachmentDownloadService` (передаёт `messageId`, путь сам не пишет).
- [ ] T039 [US2] `AttachmentDownloadService.reset()` перед `FileRepository.clean()` в `lib/data/repository/app/auth_repository_impl.dart` (выход) и `lib/data/sync/live_session_starter.dart` (смена мира).

**Checkpoint**: обе стороны продолжаются; US1 и US2 проверяются каждая сама по себе.

---

## Phase 5: User Story 3 — Смена пути посреди передачи (Priority: P2)

**Goal**: при смене пути (прямой ↔ Tor) передача продолжается на новом пути сразу, а не через предел застоя.

**Independent Test**: начать передачу по одному адресу, перевести REST на другой — передача прервана сразу и продолжилась по новому адресу (quickstart: зонд, шаг 3; стенд, сценарий 4).

### Tests for User Story 3

- [ ] T040 [P] [US3] `test/data/remote/api_client_test.dart`:
  - `initBase` с другим адресом отменяет текущее поколение: идущий к серверу A запрос кончается отменой;
  - тот же адрес — не отменяет;
  - первый `initBase` не отменяет ничего.
- [ ] T041 [P] [US3] `test/data/remote/datasource/real/real_file_remote_data_source_test.dart`, два TLS-сервера на loopback с одним сертификатом:
  - `PUT` к A, медленно читающему тело, кончается `connection` не позже чем через 2 с после `initBase(B)` (не дожидаясь предела застоя), следующий `putBytes` идёт к B;
  - то же для `openBytes`.

### Implementation for User Story 3

- [ ] T042 [US3] `lib/data/remote/api_client.dart`, `initBase`: сравнить нормализованный адрес с прежним; изменился (и прежний был) → `cancelTransfers()`.

**Checkpoint**: смена пути не начинает передачу заново и не ждёт застоя.

---

## Phase 6: User Story 4 — Когда автоматика исчерпана (Priority: P2)

**Goal**: обрывы связи не исчерпывают повторов. Исчерпывает их только сервер, отказывающий раз за разом. Ручной повтор продолжает с последнего полученного байта.

**Independent Test**: сервер раз за разом отказывает — после исчерпания ошибка с ручным повтором; повтор продолжает, а не начинает заново (стенд, сценарий 9).

### Tests for User Story 4

- [ ] T043 [P] [US4] `test/data/sync/outbox_service_test.dart`:
  - загрузку, которой сервер раз за разом отказывает (`internal` на `uploadBegin`, второй `404` на каждом проходе), очередь откладывает после `RetryLadder.refusalLimit` отказов. **Сегодня этот тест падает**: в `_uploadFor` нет предела;
  - загрузка при мигающей связи (`connection` много раз подряд) не откладывается никогда;
  - ручной повтор (`markPending`) передаёт записанную ручку как `from` и начинает лестницу заново.
- [ ] T044 [P] [US4] `test/data/sync/attachment_download_service_impl_test.dart`: после исчерпания новый `fetch` того же файла (ручной повтор) начинает лестницу заново, а репозиторий получает попытку, которая продолжает с части, — часть исчерпание не трогает (FR-011).
- [ ] T045 [P] [US4] `test/presentation/pages/file_view_page/bloc/file_view_bloc_test.dart`: сервис сообщил об исчерпании → `failed`; `Retried` зовёт `fetch` снова.

### Implementation for User Story 4

- [ ] T046 [US4] `lib/data/sync/outbox_service.dart`, `_uploadFor`: `exhausted = serverAnswered && entry.refusals + 1 >= RetryLadder.refusalLimit`, окончательность включает `exhausted`; ручку забывает только `_isTerminal`, исчерпание её сохраняет (FR-011).

**Checkpoint**: все истории работают.

---

## Phase 7: Сквозная проверка — 100 MiB через onion (SC-001 — SC-004)

- [ ] T047 Вынести обвязку `test/live/tor_live_probe.dart` (`_Noxd`, `_AwayProber`, `_Network`, `_until`) в общий `test/live/live_harness.dart`, поведение зонда не меняется. Прогнать `tor_live_probe.dart` на macOS.
- [ ] T048 Новый `test/live/resumable_files_probe.dart` (`@Tags(['live'])`, без суффикса `_test`) по quickstart, шаги 1–5:
  - 100 MiB через onion в очередь исходящих;
  - обрыв через `ApiClient.cancelTransfers()` и «перезапуск» очереди посреди загрузки;
  - возврат «домой» посреди второй половины;
  - скачивание через `AttachmentDownloadService` с обрывом, побайтовое сравнение;
  - `MEASURE:` — время в обе стороны и сколько байт пришло на сервер сверх размера (по логу `noxd`).
  Прогнать на macOS с tor стенда, числа записать в новый раздел `research.md` «§14. Замер».

---

## Phase 8: Polish & Cross-Cutting Concerns

- [ ] T049 [P] Экран 5.3:
  - `docs/design/spec/screens/file-view.md`: таблица состояний — Loading переживает обрывы и продолжает сама; Inline-error со `Try again` — только когда автоматика исчерпана; скачивание идёт после закрытия; строка в таблицу решений;
  - `docs/design/system/nox-mobile-screens/screens/5-3-file.md` и `docs/design/system/nox-desktop-screens/screens/08-file.md` — то же поведением;
  - записи 5.3 и File view в `docs/design/system/nox-mobile-screens/specs.js` и `docs/design/system/nox-desktop-screens/specs.js` — так же.
- [ ] T050 [P] Блюпринты:
  - `docs/blueprints/mobile/16-file-upload.md` — §0, §1, §3, §5 и чеклист §9: продолжение, `received`, остаток в `PUT`, коды, докачка, пределы застоя, сервис скачивания;
  - `docs/blueprints/mobile/14-networking-and-auth.md` — REST с продолжением в обе стороны, только застой, поколение передач при смене пути;
  - `docs/blueprints/mobile/04-data-layer.md` — §6а: ручка незаконченной загрузки; `data/sync`: `retry_ladder.dart`, `attachment_download_service_impl.dart`;
  - `docs/blueprints/client-backend/README.md` — загрузка с продолжением, сроки застоя.
- [ ] T051 [P] `.claude/skills/ws-rest-patterns/SKILL.md`, §6 и таблица ошибок:
  - долгая передача — срок на каждом чтении и записи (застой), не абсолютный;
  - продолжаемый `PUT` дописывает от смещения, привязанного к токену, с точками сохранения.
- [ ] T052 [P] `client_backend/CLAUDE.md`: инвариант 7 называет реестр писателей загрузки; `<id>.synced` — в описании хранения байтов; метаданные файлов по-прежнему без событий.
- [ ] T053 [P] `docs/client-backend/roadmap-tor.md` — этап 3 → `043` и статус. Корневой `CLAUDE.md`:
  - пункт «File chain (028)» дополнить продолжением 043;
  - история фич — строка 043;
  - открытая граница из research §12.
- [ ] T054 Гейты: `make gate`, `make golden-verify`, `(cd client_backend && gofmt -l . && go vet ./... && go test -race ./...)`; счётчики тестов и снимков в `CLAUDE.md`.
- [ ] T055 Проверки на стенде по `quickstart.md` (сценарии 1–11 и старый сервер) — владелец.

---

## Dependencies & Execution Order

- **Setup (T001)** — первым: контракт раньше кода (Принцип VII).
- **Foundational (T002–T003)** — до историй; друг от друга независимы.
- **US1 (Phase 3)**:
  - серверная часть (T004–T013) и клиентская (T014–T024) — разные языки и файлы, могут идти параллельно;
  - внутри сервера: T008 → T009 → T010 → T011 → T012 → T013;
  - внутри клиента: T020 → T021 → T022 → T023 → T024.
- **US2 (Phase 4)** — после US1:
  - те же файлы `file_remote_data_source.dart`, `real_file_remote_data_source.dart`, `file_repository_impl.dart`, `files.go`;
  - T034 → T035 → T036 → T037/T038/T039.
- **US3 (Phase 5)** — после T003 и T022/T034 (передачи слушают поколение).
- **US4 (Phase 6)** — после US1 (`_uploadFor`) и US2 (сервис скачивания).
- **Phase 7** — после всех историй.
- **Polish** — после Phase 7; T054 последним из кода, T055 — владелец.

### Within each story

Тесты пишутся первыми и падают без реализации; затем реализация.

### Коммиты и гейты (конституция, раздел «Рабочий процесс и гейты качества»)

Коммит — по фазам, английское сообщение, без упоминания ИИ. Перед каждым коммитом — гейты затронутых языков:
- Go-код — `gofmt -l .` (пусто), `go vet ./...`, `go test -race ./...` в `client_backend/`;
- Dart-код — `make gate` и `make golden-verify`.

Коммит с одной прозой гейтов не требует.

## Parallel Example: User Story 1

```text
Сервер: T004 (blob), T005 (tokens), T006 (writers) — параллельно; T007 — после них
Клиент: T014 (mapper), T015 (outbox repo), T016 (real source), T017 (mock source) — параллельно; T018, T019 — после
```

## Implementation Strategy

### MVP First (User Story 1)

US1 одна закрывает главную половину этапа: большой файл уходит через Tor, а обрыв и перезапуск не начинают загрузку заново. Срок 15 минут на сервере уходит здесь же.

### Incremental Delivery

1. Контракт → основа.
2. US1 (сервер + приложение) → тесты загрузки.
3. US2 → скачивание с продолжением, сервис скачивания, 5.3.
4. US3 → смена пути без ожидания застоя.
5. US4 → предел отказов для загрузки, ручной повтор с продолжением.
6. Живой зонд 100 MiB через onion → замер в research.
7. Документы и гейты.
