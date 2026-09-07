# Implementation Plan: Сервер знает своего владельца

**Branch**: `033-server-owner` | **Date**: 2026-09-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/033-server-owner/spec.md`

## Summary

Владение записывается **ссылкой на личность в единственной строке машины** (`server_identity.owner_user_id`) — там же, где её собственные ключи. Строка одна, значит и владелец один: «владельцев больше одного» становится непредставимым без индексов и проверок.

Из этого следует главное упрощение фазы: **отметка `claimed_at` перестаёт быть решающей**. «Сервер забран» = `owner_user_id IS NOT NULL`, и все три места, которые сегодня читают `claimed_at` для принятия решения, переключаются на владельца. Сама отметка времени остаётся как информация для статусной страницы фазы 035.

На проводе — одно булево поле в уже существующем объекте `identity`, отвечающее «владеет ли **тот, кто спрашивает**». Идентификатор владельца не уезжает: правила проверяет сервер, а страница 035 читает хранилище напрямую.

На клиенте признак кладётся в сессию рядом с `authorId`, переживает перезапуск и стирается при выходе; отметка рисуется в карточке идентичности корня настроек на обеих ширинах.

## Technical Context

**Language/Version**: Go 1.27 (сервер, `client_backend/`) + Dart / Flutter 3.44.1 FVM (приложение)

**Primary Dependencies**: сервер — только stdlib плюс три прямых зависимости (`coder/websocket`, `modernc.org/sqlite`, `x/sync`); приложение — существующий стек (freezed, injectable + get_it, sembast, rxdart). **Новых зависимостей ни на одной стороне не добавляется.**

**Storage**: встроенный SQLite сервера — единственная миграция `001_init.sql`, правится **на месте** (пре-релизное правило владельца 2026-08-27). На клиенте — `SharedPreferences` (признак владения не секрет).

**Testing**: `go test -race ./...` (табличные тесты, свой файл БД в `t.TempDir()`); `make gate` + `make golden-verify` на клиенте, три категории голденов.

**Target Platform**: сервер — один процесс на машине владельца; приложение — iOS, Android, macOS, Windows, Linux.

**Project Type**: клиент-серверная пара в одном репозитории; изменение затрагивает обе стороны и контракт между ними.

**Performance Goals**: не применимо — фаза не добавляет ни одного запроса. Чтение владельца попутное, внутри уже существующих транзакций и выборок.

**Constraints**: провод правится **контрактом первым** (Принцип VII); одна миграция; признак владения не попадает в журналы рядом с идентификатором личности (Принцип I); обе ширины UI с десктопным голденом (Принцип VI).

**Scale/Scope**: круг ~10 человек, владелец ровно один. Затрагивается 1 таблица, 3 места принятия решения на сервере, 2 ответа провода, 1 экран.

## Constitution Check

*GATE: пройден до Phase 0, перепроверен после Phase 1.*

| Принцип | Как соблюдается | Вердикт |
|---|---|---|
| **I. Приватность и E2EE** | Признак владения не попадает в журналы рядом с идентификатором личности (FR-024). Ничего нового о переписке не хранится и не передаётся. Признак — роль, а не доступ. | ✅ |
| **II. Спецификации — источник истины** | Спека и решения `/speckit-clarify` записаны до кода. Затрагиваемые доки (`contract-draft.md`, `client_backend/CLAUDE.md`, `docs/design/spec/screens/settings-root.md`, `roadmap-stage2.md`) правятся в этом же change-set'е. | ✅ |
| **III. Блюпринт обязателен** | Клиентская часть — существующие швы: модель `ServerIdentity`, `SessionRepository`, `SettingsRootBloc`, `AppIdentityCardWidget`. Ни одного нового слоя. | ✅ |
| **IV. Верность дизайн-системе** | Отметка строится на токенах и `ColorScheme`; ни одного нового цветового литерала. Раскладка карточки идентичности не меняется. | ✅ |
| **V. Языковая дисциплина** | Спека и доки — русские; код, коммиты, ветка — английские; микрокопия отметки — английская. | ✅ |
| **VI. Паритет mobile ↔ desktop** | Отметка живёт в `AppIdentityCardWidget`, который рисуется обеими ширинами корня настроек; десктопный голден обязателен (FR-021, SC-005). | ✅ |
| **VII. Контракт провода — закон** | Поле в `identity` вносится в §3 и §8A контракта **до** кода; обе стороны — одним change-set'ом (FR-017). | ✅ |

**Нарушений нет** — раздел Complexity Tracking пуст и удалён.

Отдельно про **инвариант 3 сервера** (транзакционный outbox): владение — часть разрешения личности, а разрешение личности намеренно **бессобытийно** (`internal/store/identity.go` — второе бессобытийное место после файловых метаданных). Владение не порождает событий и не должно: оно возникает внутри `pair`, который событий не пишет, и меняется только там же.

## Project Structure

### Documentation (this feature)

```text
specs/033-server-owner/
├── spec.md              # готово
├── plan.md              # этот файл
├── research.md          # Phase 0
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1
├── contracts/           # Phase 1 — выдержка правок контракта
├── checklists/
│   └── requirements.md  # готово, 16/16
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
client_backend/
├── migrations/001_init.sql                  # server_identity.owner_user_id (правка на месте)
├── internal/store/
│   ├── serverkey.go                         # ServerIdentity{OwnerUserID}, SetOwner, IsClaimed
│   ├── pairing.go                           # Pair: владелец при создании; «забран» от владельца
│   └── identity.go                          # Identity{Owner}; ResolveIdentity его заполняет
├── internal/server/
│   ├── handlers.go                          # greetingIdentity.Owner, identity.Owner
│   ├── pairing.go                           # ответ pair несёт владение
│   └── server.go                            # announceClaim: «забран» от владельца; предупреждение о сироте
└── (тесты рядом: pairing_test.go, identity_test.go, serverkey_test.go)

lib/
├── domain/model/session/server_identity.dart    # + owner
├── domain/model/app/session_model.dart          # + isOwner
├── domain/repository/app/session_repository.dart# + adoptServerIdentity(owner:)
├── data/repository/app/session_repository_impl.dart # ключ session.is_owner в prefs
├── data/remote/socket/nox_socket_client.dart    # разбор owner из hello
├── data/repository/app/auth_repository_impl.dart# owner из ответа pair
├── data/sync/live_session_starter.dart          # _adoptGreeting передаёт owner
├── presentation/pages/settings_root_page/       # bloc/state + страница
├── presentation/widgets/settings/app_identity_card_widget.dart # сама отметка
└── l10n/app_en.arb + app_uk.arb                 # микрокопия

docs/
├── client-backend/protocol/contract-draft.md    # §3 и §8A
├── client-backend/roadmap-stage2.md             # 033 → ☑
├── design/spec/screens/settings-root.md         # блок имени
└── design/spec/top-level-screens.md             # 7.1
```

**Structure Decision**: изменение идёт по существующей паре «Go-сервер + один Dart-пакет». Новых директорий, пакетов и слоёв не заводится: каждая правка садится в файл, который уже владеет этой ответственностью.

## Порядок работ

Порядок продиктован Принципом VII и тем, что клиент не может быть написан раньше провода:

1. **Контракт** — поле в `identity` (§3 и §8A), правило «забран = есть владелец».
2. **Схема** — `owner_user_id` в `server_identity`, правка `001_init.sql` на месте.
3. **Сервер: хранилище** — владелец при создании личности в `pair`; три места решения переключаются с `claimed_at` на владельца; `ResolveIdentity` возвращает владение.
4. **Сервер: провод** — поле в обоих ответах; тесты на приветствие, на `pair`, на повторный claim.
5. **Клиент: данные** — модель, сессия, разбор обоих кадров, стирание при выходе.
6. **Клиент: экран** — отметка в карточке идентичности, обе ширины, голдены.
7. **Доки** — блюпринты, экранные спеки, роадмап.
