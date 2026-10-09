# Tasks: Данные на диске сервера

**Input**: Design documents from `specs/047-server-data-at-rest/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md; 044–046 влиты в `security-rework` (после 045 ключа onion-сервиса в базе нет — бэкап его не несёт, FR-016)

**Tests**: обязательны (Go `-race`), сквозной прогон на macOS.

**Organization**: контракт — первым; фундамент — драйвер и ключ данных; затем истории. Go — по скиллам `go-style`, `ws-rest-patterns`, `migrations`; коммит — после гейта.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [ ] T001 Дельта контракта по `contracts/wire-locked.md` в `docs/client-backend/protocol/contract-draft.md` (§1 запертый сервер и `/health`, §3 имя журнала после восстановления)
- [ ] T002 Зависимости `client_backend/go.mod`: `github.com/ncruces/go-sqlite3`, `golang.org/x/crypto`, `golang.org/x/term`; убрать `modernc.org/sqlite`; `go mod tidy`; сборка `CGO_ENABLED=0`

## Phase 2: Foundational

- [ ] T003 [P] Ключ данных в `client_backend/internal/vault/` : создание (32 случайных байта), `<db>.key` (Argon2id 64 МиБ/3/4, XChaCha20-Poly1305), открытие паролем, смена пароля через временный файл, `fsync` и переименование; правило пароля (≥ 12 знаков, не пробелы); тесты (неверный пароль, сбой между записью и переименованием, время ≤ 2 с, SC-006)
- [ ] T004 Драйвер в `client_backend/internal/db/db.go`: `ncruces/go-sqlite3` + VFS `adiantum` с ключом данных, прагмы те же + `temp_store=memory`, `_txlock=immediate`; все тесты сервера — на зашифрованной базе с тестовым ключом; тест: после записи маркеров ни в `<db>`, ни в `-wal` маркеров нет

## Phase 3: User Story 1 — украденный диск ничего не даёт (P1) 🎯 MVP

- [ ] T005 [US1] Формат вложений версии 1 в `client_backend/internal/blob/`: куски по 64 КиБ, ключ файла HKDF, nonce и AAD по `data-model.md`, последний кусок по объявленному размеру; запись запечатанных кусков, `.synced` по кускам; чтение диапазона; тесты (подмена байта — отказ, перестановка кусков — отказ, усечение — отказ)
- [ ] T006 [US1] `client_backend/internal/server/files.go`: загрузка кусками с хвостом в памяти запроса, продолжение с начала незаконченного куска, `Range`/`If-Range` по кускам; тесты `files_resume_test.go` (обрыв посреди куска, 100 MiB — SC-004), `files_test.go` (диапазоны)
- [ ] T007 [US1] Тест SC-001 `client_backend/internal/server/at_rest_test.go`: наполнить сервер (сообщения, вложения, незаконченная загрузка), остановить, искать маркеры, ключ сервера и токены по всем файлам каталога — ноль совпадений

## Phase 4: User Story 2 — запуск с паролем (P1)

- [ ] T008 [US2] Запертый старт в `client_backend/internal/server/server.go`: служебный слушатель сразу, состояния `setup`/`locked`/`open`, отказ старта при базе без ключа или ключе без базы, основной порт — только после разблокировки, остальной `Run` — как сегодня; `/health` `locked`/`ok`; тесты (порт закрыт до пароля, `/health`)
- [ ] T009 [US2] Страница (`status.go`, `status_page.go`): формы `setup`, `unlock`, `change` по `contracts/control-and-page.md` (`Host`, `Origin`, токен), сообщения `wrong`/`short`/`mismatch`, предупреждение о забытом пароле; запертая страница — только поле пароля; тесты (неверный пароль — каталог не изменился, SC-003)
- [ ] T010 [US2] Команды: `client_backend/internal/server/control.go` (`/control/unlock`, `/control/password`), подкоманды `noxd unlock` и `noxd password` (`main.go`, `internal/config`), пароль без эха (`x/term`) или из stdin; тесты (браузерный запрос — отказ; stdin)

## Phase 5: User Story 3 — бэкап и восстановление (P2)

- [ ] T011 [US3] `client_backend/internal/backup/`: бэкап (`VACUUM INTO` во временную базу той же VFS, tar `nox.key`, `nox.db`, `files/<id>`, `manifest` с HMAC, `.partial` → переименование), восстановление (отказ на непустом месте, пароль, MAC, `quick_check`, новое `journal_id`, атомарное размещение); `/control/backup`, `noxd backup`, `noxd restore`; тесты (бэкап без открытого текста; восстановление в другой каталог — устройства подключаются без спаривания, новое `journal_id`, SC-005; подменённый бэкап — отказ; неверный пароль — ничего не меняется)

## Phase 6: User Story 4 — смена пароля и вложения кусками (P3)

- [ ] T012 [US4] Тест: смена пароля на базе с большим объёмом данных — меньше 5 с, прежний пароль не открывает (SC-006); сбой посреди смены — открывается прежний или новый

## Phase 7: Polish & Cross-Cutting

- [ ] T013 [P] Документы: `docs/blueprints/client-backend/README.md` (драйвер, ключ данных, запертый старт), `client_backend/CLAUDE.md` (зависимости с обоснованием, файлы, инварианты, команды), `docs/client-backend/{README,demo-runbook}.md`, `scripts/demo-stand.sh` (`noxd unlock` со стенда), `CLAUDE.md`
- [ ] T014 Аудит логов и вывода команд: ни пароля, ни ключей, ни содержимого
- [ ] T015 Гейты Go: `gofmt -l .`, `go vet ./...`, `go test -race ./...`, `CGO_ENABLED=0 go build` (Dart-код фича не меняет)
- [ ] T016 Сквозной прогон по `quickstart.md` §2; итог — в `research.md`
- [ ] T017 Трекер `docs/client-backend/roadmap-security.md`: 047 реализована

## Dependencies & Execution Order

T001 → T002 → T003 → T004 → (T005 → T006 → T007) и (T008 → T009 → T010) → T011 → T012 → Polish.

## Implementation Strategy

MVP — US1 + US2 вместе (шифрование без пароля открыть нельзя). Затем бэкап (US3) и смена пароля (US4).
