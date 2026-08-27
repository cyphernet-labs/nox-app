# Research: Client-сервер — bootstrap этапа 1

**Phase 0.** NEEDS CLARIFICATION в Technical Context нет: все технологические решения приняты и проверены до фичи (ресёрчи августа 2026: 8-агентный по Go-тулкиту — 55 утверждений подтверждено, 0 опровергнуто; 6-агентный по стеку; аудит контракта против приложения). Здесь — консолидация в формате Decision/Rationale/Alternatives со ссылками на носители решений. Плюс два решения кларификации спеки.

## R1. Язык и рантайм

- **Decision**: Go 1.27, `CGO_ENABLED=0`, один статический бинарник.
- **Rationale**: решение зафиксировано в [client-backend-stack.md](../../docs/client-backend/architecture/client-backend-stack.md) (сравнение пяти кандидатов); 1.27 — текущий стабильный (json/v2 GA).
- **Alternatives considered**: Rust (сильный второй; условие возврата — Q1 в вариант серверной крипты), Elixir (отклонён по поставке), Dart, Python — разбор в том же документе.

## R2. WebSocket-библиотека

- **Decision**: `github.com/coder/websocket`.
- **Rationale**: единственная с живым релизным циклом (v1.8.15, июнь 2026), context-first API, сериализация конкурентных записей; проверено по репозиториям.
- **Alternatives considered**: gorilla/websocket (фактически заморожен после ревайва), gobwas/ws (неверный уровень абстракции для ~10 соединений), x/net/websocket (сам отправляет к преемникам).

## R3. SQLite-драйвер и дисциплина доступа

- **Decision**: `modernc.org/sqlite`; два пула (writer `MaxOpenConns(1)` + `_txlock=immediate`; reader отдельно); прагмы фиксированы; транзакционный outbox.
- **Rationale**: сохраняет CGO-free кросс-сборку (путь PocketBase); `_txlock=immediate` снимает класс `SQLITE_BUSY_SNAPSHOT`; рецепт — блюпринт §3.
- **Alternatives considered**: mattn/go-sqlite3 (CGO ломает кросс-сборку — контрпример ntfy без macOS-сервера); GORM/query builders (запрещены стилем проекта — сырой SQL как аудируемый артефакт).

## R4. Конверт, replay и семантика курсора

- **Decision**: дословно контракт v0 §2–§3 ([contract-draft.md](../../docs/client-backend/protocol/contract-draft.md)): четыре кадра, `id`-корреляция, глобальный `seq`, подписка → replay → live, правило «догнан» (`seq ≥ cursor`), первое подключение без `since` — без replay.
- **Rationale**: контракт — закон (Принцип VII); семантика выверена аудитом против Flutter-приложения.
- **Alternatives considered**: зафиксированы в контракте и transport.md (свой протокол поверх TCP, page-пагинация вместо курсора — отклонены с обоснованием).

## R5. Конкурентная модель

- **Decision**: hub-горутина владеет подписчиками (каналы register/unregister/broadcast); один читатель на соединение; write pump с ping ~25 с; буфер 16 кадров, переполнение → `StatusPolicyViolation`; ни одного мьютекса в бизнес-коде (реестр соединений для shutdown — инфраструктурное исключение).
- **Rationale**: рецепты и скетчи — скилл `ws-rest-patterns` (дистилляция gotify `api/stream` + chat-примера coder); drop-политика безопасна по построению — replay долечивает.
- **Alternatives considered**: mutex-map подписчиков (отклонено правилом владения), блокирующий broadcast (замораживает всех из-за одного клиента).

## R6. Shutdown

- **Decision**: `signal.NotifyContext` + errgroup; порядок: HTTP drain → закрытие WS-соединений `StatusGoingAway` через реестр (`RegisterOnShutdown`) → останов hub → закрытие БД.
- **Rationale**: `http.Server.Shutdown` документированно не ждёт hijacked-соединений — проверенная ловушка; порядок — инвариант 9 CLAUDE.md.
- **Alternatives considered**: полагаться на Shutdown (виснет/рвёт), обратный порядок (дедлок хендлеров).

## R7. Конфигурация и логи

- **Decision**: `flag` + переопределение `NOX_*`-переменными; `log/slog` JSONHandler; без PII в логах (Принцип I: ни тел сообщений, ни label).
- **Rationale**: консенсус жанра (viper не использует никто из четырёх эталонов); slog — stdlib-стандарт с 1.21.
- **Alternatives considered**: viper/yaml-конфиг (лишняя зависимость для пяти флагов), сторонние логгеры (не нужны на нашем масштабе).

## R8. Identity-заглушка этапа 1 (кларификация спеки, 2026-08-20)

- **Decision**: необязательное поле `label` в `data` `session.hello`; fallback `User<n>` на соединение; сервер личностей не хранит. Внесено в контракт §3 как «поле этапа 1».
- **Rationale**: label стабилен между реконнектами (ручной тест читается правильно) при нулевом хранении; на этапе 2 источником станет сервер, поле уйдёт.
- **Alternatives considered**: эфемерный `User<n>` (после реконнекта «чужие» собственные сообщения), мини-таблица личностей по `device_key` (преждевременная сущность этапа 2).

## R9. Discovery свежего клиента (кларификация спеки, 2026-08-20)

- **Decision**: принято ограничение bootstrap — без `since` виден только поток новой активности; `chat_id` в ручном сценарии копируется между терминалами; `chats.list` — фаза 023.
- **Rationale**: держит фазу минимальной; для двух-трёх терминалов копирование — ноль неудобства.
- **Alternatives considered**: втащить `chats.list` в 022 (фаза толстеет), смоук через `since: 0` (полный replay — работает, но подменяет сценарий первого подключения).
