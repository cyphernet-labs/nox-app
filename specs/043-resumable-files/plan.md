# Implementation Plan: Файлы с докачкой — большой файл доходит и через Tor

**Branch**: `043-resumable-files` | **Date**: 2026-10-05 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/043-resumable-files/spec.md`

## Summary

Передача файла становится продолжаемой в обе стороны, а время на неё перестаёт быть пределом.

**Загрузка.** `file.uploadBegin` получает необязательное поле `file_id` — «продолжить эту незаконченную загрузку» — и отвечает новым полем `received`: сколько первых байтов файла сервер хранит надёжно. Токен выдаётся под это смещение, и `PUT` несёт остаток — от `received` до конца. Оборванный `PUT` оставляет на сервере всё, что успело прийти: сервер дописывает `<id>.part`, каждые 4 MiB и в конце каждого запроса сбрасывает его на диск и отмечает надёжную длину в файле рядом (`<id>.synced`). Схема базы не меняется. Сервер, не знающий продолжения, поле `file_id` пропускает и `received` не присылает — тогда приложение грузит файл целиком, как сегодня. Пишет в файл один запрос: новый прерывает прежний и ждёт, пока тот отпустит файл.

**Скачивание.** Приложение хранит недокачанное в `<fileId>.<ext>.part`, а рядом — `Last-Modified` сервера (`.part.tag`). Следующая попытка просит `Range` от того, что есть, с `If-Range`. Ответ `206` дописывается, `200` (файл не тот) начинает часть заново, в конце размер сверяется с заявленным. Сервер это уже умеет — и сегодняшний тоже.

**Время.** Абсолютные пределы уходят: сервер обрывает передачу только при застое (60 с без байтов, срок продлевается на каждом чтении и записи), приложение — при 45 с без движения. Для загрузки это свой сторож на прогрессе отправки: `sendTimeout` в Dio ограничивает всё тело целиком. Для скачивания — `receiveTimeout` Dio, который считает паузу между кусками.

**Повторы.** Загрузку повторяет очередь исходящих по своей лестнице; здесь добавляется только предел отказов для загрузки — сегодня его нет. Скачивание получает свой сервис данных `AttachmentDownloadService`: одна передача на файл, та же лестница, пробуждение при возвращении связи. Он продолжает скачивание после закрытия 5.3 и сам записывает путь в сообщение. Обрыв связи не исчерпывает повторы ни в одну сторону.

**Смена пути.** Идущие передачи прерываются, когда адрес REST меняется, и продолжаются на новом пути сразу, а не через предел застоя.

**Интерфейс** не меняется: прогресс и ошибки — существующие. Ошибка с `Try again` на 5.3 теперь появляется только когда автоматика исчерпана.

## Technical Context

**Language/Version**: Dart (Flutter `3.44.1`, FVM) — приложение; Go `1.27` — сервер (`client_backend/`).

**Primary Dependencies**: новых нет. Приложение — Dio `5.9.2` (`CancelToken`, `ResponseType.stream`, опции на запрос), flutter_bloc + freezed, injectable/get_it, rxdart. Сервер — stdlib: `http.ResponseController` для сроков на каждом чтении и записи, `http.ServeContent` для `Range`/`If-Range`, `os.Root` для частей.

**Storage**:
- Приложение — у записи `outbox` три новых необязательных поля незаконченной загрузки (старые записи читаются как есть). В каталоге кэша `nox_attachments/` рядом с недокачанным `<fileId>.<ext>.part` лежит `.part.tag`.
- Сервер — схема SQLite **не меняется**. В каталоге файлов рядом с `<id>.part` появляется `<id>.synced` — длина надёжно сохранённого начала. Токен в памяти несёт смещение.

**Testing**: `flutter_test`, `bloc_test`, `mockito`. Настоящий источник данных проверяется против локального TLS-сервера на фикстурах пиннинга (`test/general/pairing/fixtures`). Go — `httptest`, короткие пределы застоя через поля `Server`, `go test -race ./...`. Голдены не меняются, но `make golden-verify` обязателен.

**Target Platform**: приложение — iOS, Android, macOS, Windows, Linux (Tor — везде, кроме Linux); сервер — Linux, macOS, Windows.

**Project Type**: мобильное + десктопное приложение и Go-сервер; контракт v0 меняется (§7).

**Performance Goals**:
- 100 MiB доходят через onion в обе стороны (SC-001);
- после обрыва повторно идёт не больше того, что было в пути (SC-002);
- передачу, в которой байты идут, ничто не обрывает: 100 MiB на 0,3 Мбит/с — около 45 мин (SC-004);
- после смены пути передача продолжается по новому адресу не позже чем через 2 с, не дожидаясь предела застоя.

**Constraints**:
- §7 контракта правится первым (FR-015);
- одноразовые токены на 10 минут остаются;
- на сервере один писатель на файл, в приложении одна передача на файл (FR-014);
- в логах только id, размеры и смещения (FR-016);
- новых строк интерфейса нет.

**Scale/Scope**: файл до 100 MiB; одна машина одного человека. Сервер: файлы, токены, части. Приложение: источник данных, репозиторий файлов, очередь исходящих, новый сервис скачивания, подкачка картинок и блок 5.3.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Принцип | Проверка | Итог |
|---|---|---|
| I. Приватность | Новых данных за пределами устройства нет: сервер получает те же байты. Логи — только id, размеры и смещения. Ошибки файловой системы на исходном файле превращаются в `notFound` до лога: их текст несёт путь, а значит имя файла. Недокачанное лежит в кэше вложений и стирается при выходе (FR-017). | ✅ |
| II. Спека — источник истины | В том же change-set'е обновляются: §7 контракта; экран 5.3 — `docs/design/spec/screens/file-view.md` и оба корпуса (`5-3-file.md`, `08-file.md`): обрыв не ошибка, скачивание идёт после закрытия, `Try again` — только когда автоматика исчерпана. | ✅ |
| III. Блюпринт | Слои соблюдены: `FileViewBloc` → `AttachmentDownloadService` (домен) ← реализация в `data/sync`; доменная модель `UnfinishedUpload`; `RepositoryResult` и `LogRepository`. Обновляются `16-file-upload.md`, `14-networking-and-auth.md`, `04-data-layer.md`. | ✅ |
| IV. Дизайн-система | Визуально ничего не меняется: существующие прогресс, кольцо и ошибки. | ✅ |
| V. Языки | Документы — русский; код, комментарии и коммиты — английский; микрокопия — существующая EN + UK. | ✅ |
| VI. Паритет | Изменение в слое данных и одинаково для обеих ширин: 5.3 на телефоне — экран, на десктопе — лайтбокс, блок один. Существующие голдены обеих ширин остаются зелёными. | ✅ |
| VII. Контракт — закон | §7 правится первым, сервер и клиент — в этом же change-set'е. Расширение по правилу эволюции §2.1: необязательное поле команды плюс поле ответа как признак поддержки — нового признака не нужно. Инварианты `client_backend/CLAUDE.md` сохранены: метаданные файлов по-прежнему без событий, новых записей в базу нет. Новая блокировка — инфраструктурная, вносится в инвариант 7 (см. Complexity Tracking). | ✅ |

Повторная проверка после дизайна (Phase 1): нарушений принципов нет. Одно отступление от правила `client_backend/CLAUDE.md` обосновано ниже.

## Project Structure

### Documentation (this feature)

```text
specs/043-resumable-files/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── wire-files.md          # дельта §7 контракта v0
│   └── client-seams.md        # швы приложения: репозиторий, источник данных, сервис скачивания, очередь
├── checklists/requirements.md
└── tasks.md                   # /speckit-tasks
```

### Source Code (repository root)

```text
client_backend/
├── internal/server/files.go            # продолжение uploadBegin; PUT с остатком, сроки застоя, точки сохранения; GET со сроком застоя
├── internal/server/tokens.go           # токен несёт смещение
├── internal/server/writers.go          # НОВЫЙ: один писатель на файл (прерывание прежнего)
├── internal/server/server.go           # поля Server: предел застоя, шаг точки сохранения, ожидание прежнего писателя (PUT 5 с, продолжение 1 с), writers
├── internal/blob/blob.go               # Resume / Received / Checkpoint / Suspend; Remove и Abort убирают <id>.synced
├── internal/server/{files,tokens,writers}_test.go
├── internal/blob/blob_test.go
└── CLAUDE.md                           # инвариант 7: новая инфраструктурная блокировка

lib/
├── domain/model/file/unfinished_upload.dart                 # НОВЫЙ: {fileId, sourceSize, sourceModifiedAt}
├── domain/model/file/attachment_transfer.dart               # doc: перезапуск больше не начинает с первого байта
├── domain/model/chat/outbox_entry.dart                      # + UnfinishedUpload? upload
├── domain/repository/chat/outbox_repository.dart            # + noteUpload
├── domain/repository/file/file_repository.dart              # upload(from:, onUnfinished:), download(expectedSize:), cancelTransfers()
├── domain/service/attachment_download_service.dart          # НОВЫЙ
├── data/entity/chat/outbox_entity.dart                      # + uploadFileId, uploadSourceSize, uploadSourceModifiedAt
├── data/mapper/chat/outbox_mapper.dart
├── data/repository/chat/outbox_repository_impl.dart
├── data/entity/file/upload_ticket_wire_entity.dart          # + received
├── data/exception/file_transfer_exception.dart              # + staleRange (416)
├── data/remote/api_client.dart                              # отмена передач при смене адреса и по просьбе
├── data/remote/datasource/file_remote_data_source.dart      # uploadBegin(fileId:), putBytes(offset:), openBytes(offset:, validator:)
├── data/remote/datasource/real/real_file_remote_data_source.dart
├── data/remote/datasource/mock/mock_file_remote_data_source.dart
├── data/repository/file/file_repository_impl.dart           # продолжение в обе стороны
├── data/sync/retry_ladder.dart                              # НОВЫЙ: общая лестница пауз (вынесена из OutboxService)
├── data/sync/outbox_service.dart                            # незаконченная загрузка; предел отказов для загрузки
├── data/sync/attachment_download_service_impl.dart          # НОВЫЙ
├── data/sync/attachment_prefetch_service.dart               # через сервис скачивания
├── data/sync/live_session_starter.dart                      # сброс скачиваний до стирания кэша (смена мира)
├── data/repository/app/auth_repository_impl.dart            # то же при выходе
└── presentation/pages/file_view_page/bloc/file_view_bloc.dart

test/  — зеркально: retry_ladder_test (НОВЫЙ), file_repository_impl_test, real_file_remote_data_source_test (НОВЫЙ, локальный TLS-сервер),
         mock_file_remote_data_source_test (НОВЫЙ), attachment_download_service_impl_test (НОВЫЙ),
         outbox_service_test, outbox_repository_impl_test, outbox_mapper_test (НОВЫЙ), attachment_prefetch_service_test,
         file_view_bloc_test, api_client_test, auth_repository_impl_test, live_session_starter_test
test/live/live_harness.dart                    # НОВЫЙ: обвязка, вынесенная из tor_live_probe.dart
test/live/resumable_files_probe.dart           # НОВЫЙ: 100 MiB через onion в обе стороны (вручную, вне гейтов)

docs/
├── client-backend/protocol/contract-draft.md                # §1 (таблица REST), §7, §9 п. 6
├── client-backend/roadmap-tor.md                            # этап 3 → 043
├── blueprints/mobile/{16-file-upload,14-networking-and-auth,04-data-layer}.md
├── blueprints/client-backend/README.md                      # загрузка с продолжением, сроки застоя
├── design/spec/screens/file-view.md
├── design/system/nox-mobile-screens/screens/5-3-file.md
└── design/system/nox-desktop-screens/screens/08-file.md
.claude/skills/ws-rest-patterns/SKILL.md                     # долгая передача: сроки застоя, не абсолютный срок
CLAUDE.md                                                    # файловая цепочка (043), история фич
```

**Structure Decision**: сервер, контракт и приложение меняются в одном change-set'е (Принцип VII). Порядок — контракт → сервер → приложение → документы. Схема базы сервера и интерфейс приложения не меняются.

## Complexity Tracking

| Отступление | Зачем | Почему не проще |
|---|---|---|
| Новая блокировка на сервере — реестр писателей (`internal/server/writers.go`). Инвариант 7 `client_backend/CLAUDE.md` перечисляет блокировки поимённо. | Один писатель на файл. Прежний `PUT` на тихо умершем соединении висит в чтении до своего предела застоя. Если новый `PUT` начнёт писать рядом, его байты и поздние байты прежнего лягут в одну часть вперемешку. | «Отказывать новому `PUT`, пока прежний не кончился сам» — до 60 с простоя на каждую смену пути, ровно там, где фича обещает продолжение. Блокировка того же класса, что хранилище токенов: инфраструктура передачи, не бизнес-состояние. В инвариант 7 вносится поимённо. |
| Надёжная длина части — в файле `<id>.synced` рядом с частью, а не в базе. | После сбоя питания хвост части может быть мусором: размер файла говорит, сколько записано, а не сколько надёжно. | Колонка в `files`: правило «до релиза одна миграция» требует править `001`, и каждую базу разработки, включая стенд владельца, пришлось бы создать заново и спарить устройства снова. Надёжность байтов — свойство байтов, и пакет `blob` уже отвечает за неё (`Finalize` с `fsync`). |
