# Блюпринт client-сервера (Go)

**Дата:** 2026-08-20 · Архитектурный референс реализации в `client_backend/`. Контракт — [protocol/contract-draft.md](../../client-backend/protocol/contract-draft.md); инварианты кода — `client_backend/CLAUDE.md`; стиль — скилл `go-style`. Все утверждения проверены по первоисточникам (go.dev, репозитории библиотек, разбор PocketBase / ntfy / miniflux / gotify) в августе 2026.

---

## 1. Целевая версия и зависимости

| | Выбор | Почему |
|---|---|---|
| **Go** | **1.27** (вышел 2026-08-19; поддерживаются 1.27 и 1.26) | `encoding/json/v2` достиг GA; Green Tea GC по умолчанию с 1.26 |
| **WebSocket** | `github.com/coder/websocket` (бывш. nhooyr) | Единственная библиотека с живым релизным циклом (v1.8.15, июнь 2026); context-first API; внутренняя сериализация записей. gorilla после ревайва 2023 фактически заморожен (релиз июнь 2024); `x/net/websocket` сам отправляет к coder |
| **SQLite** | `modernc.org/sqlite` (v1.57.0, SQLite 3.53.3) | Чистый Go — сохраняет `CGO_ENABLED=0` и кросс-сборку; в проде у PocketBase. ⚠️ `modernc.org/libc` не следует semver — версия пинится |
| **Оркестрация** | `golang.org/x/sync/errgroup` | Идиома graceful-каркаса. ⚠️ Паника из горутины НЕ доносится до `Wait` — не закладываться |
| Роутер, логгер, конфиг, ORM | **stdlib** | `ServeMux` с 1.22 умеет методы и wildcards; `log/slog`; флаги+env; сырой SQL — весь жанр (miniflux: 13 прямых зависимостей на целый RSS-сервер) живёт без фреймворков |

Три прямые зависимости. Любая четвёртая — с письменным обоснованием.

## 2. Раскладка

Консенсус жанра (main в корне + `internal/`) поверх официального гайда `go.dev/doc/modules/layout`; `pkg/` не существует — golang-standards/project-layout дезавуирован лично Russ Cox (issue #117).

```
client_backend/
  main.go              # ~3 строки: flags → internal/server.Run
  go.mod               # go 1.27; tool-директивы вместо tools.go (Go 1.24+)
  migrations/          # append-only нумерованные .sql, embed.FS
  internal/
    config/            # флаги + NOX_*-env; валидация при старте
    db/                # открытие пулов, прагмы, миграции user_version
    store/             # типы + ВСЕ чтения/записи; единственный писательский код
    hub/               # горутина-владелец множества подписчиков
    server/            # wiring: ServeMux, WS-endpoint, REST, graceful shutdown
    protocol/          # конверт v0: типы кадров, коды ошибок, (un)marshal
```

Один уровень вложенности под `internal/`, однословные имена пакетов, никаких `util`/`common`/`helpers` (запрещены Google style guide). Тесты — colocated `_test.go` в том же пакете.

## 3. Рецепт SQLite (выжимка из PocketBase + официальные оговорки)

**Два пула на одну базу:**

```go
// DSN: busy_timeout первым (порядок PocketBase), затем WAL и остальные.
dsn := "file:" + path + "?_pragma=busy_timeout(5000)" +
    "&_pragma=journal_mode(WAL)" +
    "&_pragma=synchronous(NORMAL)" +
    "&_pragma=foreign_keys(1)"

read, _  := sql.Open("sqlite", dsn)              // читающий пул
write, _ := sql.Open("sqlite", dsn+"&_txlock=immediate")
write.SetMaxOpenConns(1)                          // ЕДИНСТВЕННЫЙ писатель
```

- `_txlock=immediate` на writer снимает класс ошибок `SQLITE_BUSY_SNAPSHOT`.
- **Никогда `:memory:` с `database/sql`** — каждое соединение пула получает свою приватную базу (официальная ловушка). В тестах — файл в `t.TempDir()`.
- Миграции: `PRAGMA user_version` + `embed.FS` с `*.sql`, применяются при старте до открытия endpoint'ов. Файлы append-only.
- Бэкап: `VACUUM INTO` во временный файл + rename. Живой файл БД не копировать. WAL ломается на сетевых ФС — только локальный диск.
- Транзакция записи и её `events`-строка — **атомарно**; broadcast — только после commit (транзакционный outbox; сериализацию даёт `MaxOpenConns(1)`).

## 4. Рецепт WebSocket (coder/websocket + hub gotify-стиля)

- **Один читающий goroutine на соединение** — жёсткий инвариант библиотеки; конкурентные записи coder сериализует сам.
- **Hub** — горутина, владеющая множеством подписчиков; взаимодействие только через каналы register/unregister/broadcast. Мьютексов в проекте нет: если правка «требует» мьютекс — перестроить на владение одной горутиной.
- **Медленный клиент:** буферизованный канал ~16 кадров на подписчика; переполнился → `Close(StatusPolicyViolation)`. Это безопасно по построению: клиент переподключится с `since` и догонится по seq-логу — replay и есть наша защита от потери.
- **Keepalive не автоматический:** свой ticker с `Ping(ctx)` (~25 с) при работающем читателе.
- **`SetReadLimit`** = `max_frame_bytes` из контракта (131072; дефолт библиотеки 32 КиБ — мал).
- **`http.Server.Shutdown` документированно НЕ ждёт hijacked-соединений.** Обязательно: `RegisterOnShutdown` + собственный реестр соединений + `Close(StatusGoingAway)` каждому. Порядок остановки: HTTP-drain → закрыть WS → остановить hub → закрыть БД.
- Кадры JSON: `encoding/json` v1-API (в 1.27 уже работает поверх v2); двухфазный разбор через `json.RawMessage` для поля `data`. Неизвестные поля **игнорировать** (эволюция v0); `DisallowUnknownFields` — только в контрактных тестах.

## 5. Каркас процесса

```go
ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
g, ctx := errgroup.WithContext(ctx)
// g.Go: http.ListenAndServe; g.Go: hub.Run(ctx); по ctx.Done() → srv.Shutdown(таймаут)
```

- REST: `mux.HandleFunc("GET /health", …)`, `PUT /files/{token}`; middleware — `func(http.Handler) http.Handler`.
- Загрузка: `http.MaxBytesReader` лимитом из контракта. Скачивание: `http.ServeContent` — Range и условные заголовки обрабатывает сам.
- Логи: `slog` + `JSONHandler`, request-middleware с методом/путём/статусом/длительностью.
- Сборка: `CGO_ENABLED=0 go build -trimpath -ldflags="-s -X main.version=$(git describe)"` (`-s` теперь подразумевает `-w`).

## 6. Тестирование

- Табличные тесты + `t.Run`; БД — файл в `t.TempDir()`, миграции с нуля в каждом тесте.
- HTTP — `httptest`; WS — `httptest.NewServer` + `websocket.Dial(ctx, s.URL)` (http-схему принимает напрямую).
- **`go test -race ./...` — всегда**, не опционально (race detector требует CGo только в тестовом контуре — на маке это штатно).
- Конкурентность и replay — `testing/synctest` (GA с 1.25; в 1.27 добавлен `httptest.NewTestServer` с in-memory сетью специально под него).
- Идеи из жанра: leaktest на WS-хендлерах (gotify), сценарные хелперы на группу endpoint'ов (PocketBase `ApiScenario`).

## 7. Линт и проверки

`gofmt` (диф пустой) → `go vet ./...` → `staticcheck` (или `golangci-lint` **v2** — конфиг `version: "2"`, примеры v1 из старых статей не годятся) → `govulncheck` → `go test -race`. Не отключать `errcheck` (антипример miniflux/gotify — осознанно отвергнут).

## 8. Что отвергнуто сознательно

| Практика | Откуда | Почему нет |
|---|---|---|
| Роутер-фреймворк (chi, gin, echo) | привычка | `ServeMux` 1.22+ покрывает всё; «advanced routing needs» у нас нет |
| `pkg/`-каталог, golang-standards/project-layout | карго-культ | Дезавуирован Go-командой |
| `util`/`common`-пакеты | ntfy/gotify | Запрещены Google style guide — имя пакета должно описывать содержимое |
| Мьютексы в бизнес-коде | привычка | Владение состоянием — одна горутина + каналы (hub) или один writer-пул (БД) |
| ORM / query builder | привычка | Сырой параметризованный SQL — аудируемый артефакт |
| `viper`, `testify`-везде | привычка | Ни один из четырёх эталонов жанра не использует viper; miniflux живёт на голом `testing` |
