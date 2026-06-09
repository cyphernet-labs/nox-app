# 12 — Команды разработки

> **Назначение:** дать единый, скопированный-вставленный набор повседневных команд для **одно-пакетного** приложения `nox_app` (codegen, формат, анализ, тесты, mise-таски, Makefile) и набор скаффолдинг-скиллов `.claude/commands/*`, которые порождают артефакты строго по нашей архитектуре (Freezed-BLoC, пагинация через `applyPage`, единый DI). **Когда читать:** ежедневно во время разработки, а также перед заведением нового фичевого вертикального среза (список чатов — первый реальный). **Связанные документы:** [11-scaffolding-plan.md](11-scaffolding-plan.md) (порядок ручного скаффолдинга, который эти команды автоматизируют), [10-code-templates.md](10-code-templates.md) (canonical-шаблоны, которые команды эмитят), [08-conventions-and-constitution.md](08-conventions-and-constitution.md) (правила именования/импортов/коммитов, которые команды обязаны соблюдать), [01-stack-and-tooling.md](01-stack-and-tooling.md) (версии FVM/Dart/Flutter), [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md) (mise-таски секретов и flavored-сборки).

---

## 0. Ключевое правило: один пакет, а не три

Этот блюпринт намеренно использует **один Dart-пакет** `nox_app`, а не три (`domain/`, `data/`, root). В трёх-пакетной раскладке codegen пришлось бы запускать по очереди (`build_runner` в `data/` → `domain/` → root в порядке зависимостей), форматирование и импорты ходили бы по пяти корням (`lib/`, `domain/lib/`, `data/lib/`, `data/test/`, `test/`), а DI собиралось бы по-пакетно. Мы это не делаем.

У нас **ОДИН пакет** `nox_app`. Слои — это **папки** в одном `lib/` (`lib/domain`, `lib/data`, `lib/presentation`, `lib/di`, `lib/general`, `lib/design`, `lib/resource`), один `pubspec.yaml`, один `build_runner`-прогон, один `configureDependencies(env)`. Поэтому везде ниже:

- **codegen — ОДНА команда** `fvm dart run build_runner build --delete-conflicting-outputs`. Никакого `data → domain → root` порядка: нет нескольких пакетов, нечего упорядочивать.
- **импорты — только `package:nox_app/...`** (никаких `../` кроме `part`). Поиск-замена при рефакторинге идёт по одному корню `lib/` (+ `test/`, `integration_test/`), а не по пяти.
- **DI — один** генерируемый `lib/di/configure_dependencies.config.dart`; команды не упоминают «три пакета» и path-deps.

Эта поправка применяется к каждой команде в этом документе — отдельно повторяется в трейлерах.

---

## 1. Повседневные команды (все через `fvm`)

Все вызовы идут через **FVM** (версия Flutter закреплена в `.fvmrc` — Flutter 3.44.1, Dart `>=3.12.0 <4.0.0`). Никаких голых `flutter`/`dart` — только `fvm flutter` / `fvm dart`.

### 1.1. Зависимости

```bash
fvm flutter pub get
```

Запускать после `git clone`, после любой правки `pubspec.yaml`, после смены ветки с изменёнными зависимостями.

### 1.2. Кодогенерация (ОДИН прогон)

```bash
fvm dart run build_runner build --delete-conflicting-outputs
```

Генерирует за один проход по всему `lib/`:

- `*.freezed.dart` — Freezed-модели (домен), Freezed-BLoC `State`/`Event`-юнионы, `RepositoryResult`, конфиги репозиториев;
- `*.g.dart` — `json_serializable` (ТОЛЬКО на entity-слое — у доменных моделей и BLoC-типов `*.g.dart` нет, см. [03-domain-layer.md](03-domain-layer.md), [05-presentation-layer.md](05-presentation-layer.md));
- `lib/di/configure_dependencies.config.dart` — `injectable`-регистрации (`$initGetIt`).

> **Никакого пер-пакетного порядка.** Это один пакет — `build_runner` сам разрешает граф `part`-директив внутри `lib/`. Если codegen падает — почти всегда отсутствует `part '*.freezed.dart';` / `part '*.g.dart';` или сломана `@freezed`/`@JsonSerializable`-аннотация.

Watch-режим при активной работе над моделями (опционально):

```bash
fvm dart run build_runner watch --delete-conflicting-outputs
```

### 1.3. Форматирование (ТОЛЬКО изменённые файлы)

Длина строки — **140** (закреплена в `analysis_options.yaml`). Форматируем **только файлы, которые трогали в текущей задаче** — никогда весь репозиторий:

```bash
fvm dart format -l 140 lib/data/repository/item/item_repository_impl.dart lib/presentation/pages/item_list_page/bloc/item_list_bloc.dart
```

Передавать **явные пути**, а не `.` и не diff-режим: иначе переформатируется куча несвязанных файлов и раздувается diff. Генерируемые файлы (`*.g.dart`, `*.freezed.dart`, `*.config.dart`, `lib/design/gen/**`) форматировать не нужно — они исключены из анализа и не правятся руками.

### 1.4. Статический анализ

```bash
fvm flutter analyze
```

Должно быть **ноль ошибок** перед остановкой по задаче. Анализ исключает генерируемые файлы и `build/`. Это финальные ворота каждой задачи.

### 1.5. Тесты

```bash
# Юнит + виджет-тесты (включая bloc_test для Freezed-BLoC)
fvm flutter test

# Один файл / директория
fvm flutter test test/presentation/item_list_bloc_test.dart
fvm flutter test test/data/

# Интеграционные тесты (на устройстве/эмуляторе)
fvm flutter test integration_test
```

BLoC покрываем через `bloc_test` — он проверяет последовательность эмитнутых Freezed-`State` (`Initializing` → `Initialized` → …). Для пагинации тестируем чистую функцию `PagingStateExt.applyPage` отдельным юнит-тестом (детерминированно, без UI) — см. [07-pagination.md](07-pagination.md).

### 1.6. Запуск приложения с flavor

Flavor выбирается на этапе компиляции (`String.fromEnvironment('app.flavor')`); flavor-специфичные значения приходят через `--dart-define-from-file` (см. [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md)):

```bash
# Скелет: флейвор приходит из закоммиченного config-файла, единообразно на всех платформах.
fvm flutter run --dart-define-from-file=config/stage.json   # stage
fvm flutter run --dart-define-from-file=config/prod.json    # prod
```

> Нативные mobile-флейворы (`--flavor`) и секреты (`secrets:decrypt` → `.secrets-runtime/<flavor>.dart-define.json`) — на будущее (блюпринт `09` §6/§7); в скелете не используются.

---

## 2. mise-таски и Makefile-обёртки

Секреты (SOPS + age) и flavored-сборки оборачиваются в `mise`-таски (их **полное определение** — в [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md) §4 `.mise.toml`), а Makefile (§5 там же) даёт короткие алиасы. Именование тасков: `namespace:action[:channel]` для секретов и `build:<platform>:<channel>` для сборок; каждый `build:*` объявляет `depends = ["secrets:decrypt:<flavor>"]`, поэтому decrypt выполняется автоматически перед сборкой. Точные имена:

```bash
# Расшифровать секреты в .secrets-runtime/<flavor>.dart-define.json (+ нативные конфиги)
mise run secrets:decrypt:stage
mise run secrets:decrypt:prod

# Полная flavored-сборка (depends авто-дёргает secrets:decrypt:<flavor>):
mise run build:android:stage    # stage APK
mise run build:android:prod     # prod App Bundle (AAB)
mise run build:ios:stage        # stage IPA
mise run build:ios:prod         # prod IPA
```

Makefile-обёртки поверх них (чтобы не помнить точный синтаксис mise; полный Makefile — в [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md) §5):

```makefile
.PHONY: generate analyze test build-android-stage build-android-prod build-ios-stage build-ios-prod secrets-decrypt-stage secrets-decrypt-prod

generate:             ; fvm dart pub get && fvm dart run build_runner build --delete-conflicting-outputs
analyze:              ; fvm flutter analyze
test:                 ; fvm flutter test
secrets-decrypt-stage:; mise run secrets:decrypt:stage
secrets-decrypt-prod: ; mise run secrets:decrypt:prod
build-android-stage:  ; mise run build:android:stage
build-android-prod:   ; mise run build:android:prod
build-ios-stage:      ; mise run build:ios:stage
build-ios-prod:       ; mise run build:ios:prod
```

> **Никогда не вызывать `sops`/`age` напрямую** — только через `mise run secrets:*`. Версионирование сборок — CalVer + shifted-epoch (`YY.M.D+EPOCH`), детали в [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md). Под prod-дистрибуцию таск можно дополнительно разбить по назначению (`build:android:prod:firebase` / `build:android:prod:google` / `build:ios:prod:firebase` / `build:ios:prod:apple`) — мобильный CD пока отложен (см. 09 §11), поэтому здесь оставлен базовый `build:<platform>:prod`.

---

## 3. Скаффолдинг-скиллы `.claude/commands/*`

`.claude/commands/<name>.md` — это **prompt-шаблон**, а не скрипт. Когда вы вводите `/<name> <args>`, агент читает этот markdown и выполняет шаги. Ценность в том, что **рецепт лежит в репозитории** — скаффолдинг остаётся верным архитектуре спустя месяцы и между сессиями.

Три правила, которые соблюдает каждая команда набора:

1. **Одна команда = один canonical-класс артефакта.** `new-model` делает только модель+entity+mapper; `new-repository` — только стек репозитория; `new-page` — только page + **Freezed-BLoC-трио**. Они композируются, но не перекрываются.
2. **Шаблоны живут в доках, а не в команде.** Каждая команда ссылается на [10-code-templates.md](10-code-templates.md) и нужный layer-док за точными байтами; команда говорит, *какой* шаблон применить, *куда* и *с какими именами*. Единый источник правды.
3. **Каждая генеративная команда заканчивается одним трейлером:** codegen (один прогон) → format (только изменённые) → analyze. Ровно то, что делает `/check-build` (Раздел 3.1).

> **Что команды эмитят, а что — нет (важно).** Команды эмитят **Freezed-BLoC** (`State`/`Event` — `@freezed sealed`-юнионы с генерируемыми `when()`/`copyWith()`, см. [05-presentation-layer.md](05-presentation-layer.md)), а **не** рукописный `Equatable`-BLoC. Используются одно-пакетные пути (`lib/domain/...`, `lib/data/...`), env-лист `[Environment.dev, Environment.prod, Environment.test]` (`prod→Environment.prod`, `stage→Environment.dev`, плюс обязательная регистрация под `Environment.test`), пагинация через `PagingStateExt.applyPage`. BigInt/IPC/swift-to-dart, `@BigIntConverter()`, IPC-вариант репозитория и `CustomEnvironment.ipc` — **вне scope**, не эмитим.

Создать файлы под `.claude/commands/` в репозитории мобильного приложения:

```bash
mkdir -p .claude/commands
# каждый <name>.md авторим по рецептам ниже
```

| Команда | Что делает | Шаблоны в |
|---|---|---|
| `/check-build` | ничего не создаёт — запускает verify-пайплайн | [12-dev-commands.md](12-dev-commands.md) §1 |
| `/new-model` | `<Model>Model` + `<Model>Entity` + `<Model>Mapper` | [03-domain-layer.md](03-domain-layer.md), [04-data-layer.md](04-data-layer.md), [10-code-templates.md](10-code-templates.md) |
| `/new-repository` | `<Feature>Repository` (LIST-метод `get<Feature>s`) + `Get<Feature>sConfig` + `<Feature>RepositoryImpl` + DI | [03-domain-layer.md](03-domain-layer.md), [04-data-layer.md](04-data-layer.md), [10-code-templates.md](10-code-templates.md) |
| `/new-page` | `<Feature>ListPage` + **Freezed** `<Feature>ListBloc/Event/State` + пагинация через `applyPage` | [05-presentation-layer.md](05-presentation-layer.md), [07-pagination.md](07-pagination.md), [10-code-templates.md](10-code-templates.md) |
| `/move-files` | ничего — переносит файлы + чинит импорты | [08-conventions-and-constitution.md](08-conventions-and-constitution.md) |
| `/rename-class` | ничего — переименовывает класс + все ссылки | [08-conventions-and-constitution.md](08-conventions-and-constitution.md) |
| `/update-json` | ничего — сверяет JSON-фикстуру с моделью | [04-data-layer.md](04-data-layer.md) |

---

### 3.1. `/check-build`

**Назначение:** запустить полный verify-пайплайн одной командой.

**Когда:** после любого изменения кода и как финальный шаг каждой генеративной команды. Это стандартный end-of-task чеклист (codegen → format → analyze).

`.claude/commands/check-build.md`:

```markdown
Run the full build verification pipeline (single Dart package).

## Steps

1. Run code generation (ONE run — single package, no data->domain->root ordering):
   ```bash
   fvm dart run build_runner build --delete-conflicting-outputs
   ```
   Generates `*.freezed.dart`, `*.g.dart` (entity layer only), and
   `lib/di/configure_dependencies.config.dart` in one pass over `lib/`.

2. Format ONLY the files you changed (line length 140):
   ```bash
   fvm dart format -l 140 <changed paths>
   ```

3. Static analysis (zero errors before you stop):
   ```bash
   fvm flutter analyze
   ```

4. Report results: list any errors or warnings found.

## Notes
- If code generation fails, check for missing `part` directives
  (`part '*.freezed.dart';` / `part '*.g.dart';`) or malformed Freezed/Injectable annotations.
- Analysis excludes generated files (`*.freezed.dart`, `*.g.dart`, `*.config.dart`,
  `lib/design/gen/**`) and `build/`.
- All commands use `fvm flutter` / `fvm dart` — never bare `flutter`/`dart`.
```

---

### 3.2. `/new-model`

**Назначение:** создать Freezed-доменную модель + matching data-entity + mapper — lossless round-trip-тройку.

**Когда:** при добавлении доменного value-object, который пересекает data-границу. Запускать *до* `new-repository`, если новый репозиторий обслуживает эту модель.

`.claude/commands/new-model.md`:

```markdown
Create a Freezed domain model with corresponding data entity and mapper (single package).

## Input
- `$ARGUMENTS`: `<ModelName>`
- Example: `/new-model Item`
- Paths are fixed by the single-package layout:
  - model:  `lib/domain/model/<snake_name>_model.dart`
  - entity: `lib/data/entity/<snake_name>_entity.dart`
  - mapper: `lib/data/mapper/<snake_name>_mapper.dart`

## Steps

1. **Domain model** — `lib/domain/model/<snake_name>_model.dart`:
   - `@freezed class <Name>Model with _$<Name>Model`
   - `part '<snake_name>_model.freezed.dart';` ONLY — NO `*.g.dart`, NO `fromJson`
     (domain models carry no JSON; JSON lives on the entity layer)
   - All fields `required` (nullable fields typed `T?`); no `@Default`
   - Full package imports `package:nox_app/...`, never relative
   - Derived/computed logic goes in an EXTENSION getter, not in the @freezed body
   - Do NOT use BigInt money fields or `@BigIntConverter()`

2. **Data entity** — `lib/data/entity/<snake_name>_entity.dart`:
   - `@freezed class <Name>Entity with _$<Name>Entity`
   - Basic types only: String/int/double/bool (+ `String?`); enums as their `.name` String;
     DateTime as ISO-8601 String. No converters in the entity — all coercion lives in the mapper.
   - `part '<snake_name>_entity.freezed.dart';` AND `part '<snake_name>_entity.g.dart';`
   - `factory <Name>Entity.fromJson(Map<String, Object?> json) => _$<Name>EntityFromJson(json);`

3. **Mapper** — `lib/data/mapper/<snake_name>_mapper.dart`:
   - `@lazySingleton`
   - `class <Name>Mapper extends EntityConverter<<Name>Entity>` (registered in the converter registry)
     producing `<Name>Model`; do the enum<->String name and DateTime<->ISO-8601 coercion HERE
   - Implement `toModel()` / `toEntity()`

4. Export new files from barrels if they exist.
5. fvm dart run build_runner build --delete-conflicting-outputs   # ONE run
6. fvm dart format -l 140 <the 3 new files>
7. fvm flutter analyze

## References (canonical templates)
- Model / extension getters / RepositoryResult: `03-domain-layer.md`, `10-code-templates.md`
- Entity / mapper / ResponseEntity / EntityConverter registry: `04-data-layer.md`, `10-code-templates.md`
```

> Worked-тройка `Item`: `ItemModel { id, name, description?, status:ItemStatus, createdAt:DateTime }` → `ItemEntity { id, name, description?, status:String, createdAt:String }` → `ItemMapper`. Никакого `BigIntConverter`/money. Первый реальный артефакт — модель элемента списка чатов (`ItemModel`-форма) — делается этой же командой.

---

### 3.3. `/new-repository`

**Назначение:** создать весь стек репозитория: доменный контракт, Freezed-конфиг-юнион, data-реализацию, DI-регистрацию.

**Когда:** когда фиче нужен доступ к данным за контрактом. Запускать `new-model` первым, если модель ещё не существует.

`.claude/commands/new-repository.md`:

```markdown
Create a repository: contract, configs union, implementation, and DI registration (single package).

## Input
- `$ARGUMENTS`: `<RepositoryName>`
- Example: `/new-repository Item`
- Paths fixed by the single-package layout:
  - contract: `lib/domain/repository/<snake_name>/<snake_name>_repository.dart`
  - config:   `lib/domain/repository/<snake_name>/get_<snake_name>s_config.dart`
  - impl:     `lib/data/repository/<snake_name>/<snake_name>_repository_impl.dart`

## Steps

1. **Domain contract** — `lib/domain/repository/<snake_name>/<snake_name>_repository.dart`:
   - `abstract class <Name>Repository`
   - Methods return `RepositoryResult<T>` (one-shot) or `Stream<RepositoryResult<T>>` (watch).
   - For server-owned paginated lists the LIST method is `get<Name>s` returning
     `Future<RepositoryResult<(List<<Name>Model>, PageMetadata)>>`
     (offset is the default pagination flavor: `PageMetadata{required int total, int? nextPage}` at
     `lib/domain/repository/base/page_metadata.dart`, `nextPage == null` => last page; cursor is the
     documented alternative — the concrete chats-list pagination contract is finalized later with the
     NOX backend). Paginated lists are NETWORK-ONLY (no DAO/subject).
   - Canonical method set (per the method-prefix table — `get*` = parametrized/list,
     `fetch*` = one-shot single, `watch*` = stream): `watch<Name>`, `fetch<Name>`, `get<Name>s`,
     `create<Name>`, `update<Name>`, `delete<Name>`, `clean`.
     NO `save<Name>` (use `create<Name>`/`update<Name>`); NEVER `fetch<Name>s` for the list.

2. **Config** — `lib/domain/repository/<snake_name>/get_<snake_name>s_config.dart`:
   - ONE `@freezed abstract class Get<Name>sConfig with _$Get<Name>sConfig implements RepositoryConfig`
   - `const factory Get<Name>sConfig({required int page, String? search}) = _Get<Name>sConfig;`
   - Named constructors `Get<Name>sConfig.firstPage({String? search})` (=> `page: defaultPage`) and
     `Get<Name>sConfig.nextPage({required int page, String? search})`
   - `static const int pageSize = 20;` and `static const int defaultPage = 1;` (1-based)
   - `part 'get_<snake_name>s_config.freezed.dart';` ONLY — no `*.g.dart`
   - NO sealed-union `<Name>RepositoryConfigs.list` redirect; NEVER `Get<Name>sConfig(page: 0, pageSize: 50)`

3. **Implementation** — `lib/data/repository/<snake_name>/<snake_name>_repository_impl.dart`:
   - `@LazySingleton(as: <Name>Repository, env: [Environment.dev, Environment.prod, Environment.test])`
     (`test` is REQUIRED — the repo MUST resolve under `Environment.test` or `getIt` throws in tests;
     flavor map: prod->Environment.prod, stage->Environment.dev)
   - `class <Name>RepositoryImpl with BaseRepositoryHelper implements <Name>Repository`
   - Wrap every method body in `execute<T>()`; the callback returns an already-wrapped `RepositoryResult` (`return RepositoryResult.success(data: …)` / `.error(exception: RepositoryException.<code>)`). `execute` only catches unhandled errors (DioException -> internal, else -> unknown) and ALWAYS logs via LogRepository
   - Cache-first reactive watch*(): one BehaviorSubject fed by a single subscription to the DAO stream
   - Paginated `get<Name>s` / one-shot POSTs: NETWORK-ONLY, no DAO/subject (base carve-out);
     parse the raw envelope via `PaginatedResponse<T>` and map to `(List<<Name>Model>, PageMetadata)`
   - Inject the `<Name>Mapper` and `<Name>Dao` via constructor
   - NO IPC/multi-process variant.

4. Register in DI: confirm the env-list annotation (incl. `Environment.test`) is picked up by `$initGetIt`.
5. Export from barrels if they exist.
6. fvm dart run build_runner build --delete-conflicting-outputs   # ONE run
7. fvm dart format -l 140 <changed files>
8. fvm flutter analyze

## References (canonical templates)
- Contract / config / RepositoryResult / RepositoryException: `03-domain-layer.md`, `10-code-templates.md`
- Repo impl / BaseRepositoryHelper / Sembast DAO / mapper / network-only carve-out: `04-data-layer.md`, `10-code-templates.md`
- Pagination contract (PageMetadata / PaginatedResponse / RepositoryResult<(List, PageMetadata)>): `07-pagination.md`
- DI annotations + bootstrap chain ($initGetIt): `02-dependency-injection.md`
```

> **Env-лист — `[Environment.dev, Environment.prod, Environment.test]`** (два flavor: `prod→Environment.prod`, `stage→Environment.dev`; плюс **обязательный** `Environment.test`). Регистрация под `Environment.test` — **не опциональна**: без неё `getIt<<Name>Repository>()` бросит под `Environment.test`. Тестовый `AppDatabase` подменяется СВОИМ test-env-провайдером (`@LazySingleton(as: AppDatabase, env: [Environment.test])` → `AppDatabaseTest`), но сам репозиторий-импл регистрируется во всех трёх env, а не «подменяется отдельно». Конфиг — **единственный** `@freezed Get<Name>sConfig` (`firstPage`/`nextPage`, `defaultPage = 1`), без sealed-union-редиректа `…RepositoryConfigs.list` и без `page: 0`. IPC-вариант репозитория **не эмитим**.

---

### 3.4. `/new-page`

**Назначение:** создать Flutter-страницу с её **Freezed-BLoC-трио** (bloc + events + states) и, если страница списочная — пагинацией через `PagingStateExt.applyPage`.

**Когда:** при добавлении экрана. Связать с репозиторием, созданным `new-repository`. Первый реальный экран — список чатов (server-owned, network-only пагинируемый список).

`.claude/commands/new-page.md`:

```markdown
Create a Flutter page with a FREEZED BLoC trio (NOT hand-written Equatable) following project conventions.

## Input
- `$ARGUMENTS`: `<PageName>`
- Example: `/new-page ItemList`
- Directory: ONE FLAT page folder `lib/presentation/pages/<snake_name>_page/` with a `bloc/` subfolder.
  Page-based, NOT feature-based: no `<feature>/` or area sub-level, no extra nesting.
  Worked example (input `ItemList`): `lib/presentation/pages/item_list_page/` →
  `item_list_page.dart` + `bloc/{item_list_bloc,item_list_event,item_list_state}.dart` + `widgets/`.

## Steps

1. Create directory `lib/presentation/pages/<snake_name>_page/bloc/`.

2. **State** — `bloc/<snake_name>_state.dart` (FREEZED, NOT Equatable):
   - `part '<snake_name>_state.freezed.dart';` ONLY — never `*.g.dart`, NO fromJson on BLoC types
   - `@freezed sealed class <Name>State with _$<Name>State`
   - Canonical const-factory substates: `.initializing()`, `.initialized(...)`, `.error(...)`
   - For a LIST page, the `.initialized` factory carries the loaded `items` plus
     `PagingState<String, <Item>Model> pagingState` and `int? nextPage`
     (key K = String = item id, one-item-per-page; offset tracked via `nextPage`, NOT via K)
   - Derived/computed logic (e.g. itemCount, isLastPage) in an EXTENSION getter, not the @freezed body
   - Transitions via `copyWith`

3. **Event** — `bloc/<snake_name>_event.dart` (FREEZED):
   - `part '<snake_name>_event.freezed.dart';` ONLY
   - `@freezed sealed class <Name>Event with _$<Name>Event`
   - `const factory <Name>Event.initialize() = _Initialize;`
   - For a LIST page: `const factory <Name>Event.fetchNextPage() = _FetchNextPage;`

4. **BLoC** — `bloc/<snake_name>_bloc.dart`:
   - `class <Name>Bloc extends BaseBloc<<Name>Event, <Name>State>`
   - `super(const <Name>State.initializing())`; register handlers in ctor (`on<...>`); pattern-match the Freezed event union
   - Wrap async work in `executeLogic(..., onError: ...)` (BaseBloc try/catch); emit `<Name>State.error(...)` on failure
   - For a LIST page, fold each fetched page into pagingState via the reusable extension
     (canonical record-returning shape — `existingList` + `response: (items, meta)` + `keyExtractor`):
       ```dart
       final r = state.pagingState.applyPage(
         existingList: state.items,
         response: (items, meta),       // (List<<Item>Model>, PageMetadata)
         keyExtractor: (e) => e.id,     // K = String = item id
       );
       emit(state.copyWith(items: r.updatedList, pagingState: r.pagingState, nextPage: r.nextPage));
       ```
   - Repositories via `getIt<<Name>Repository>()`; store subscriptions in fields, cancel in `close()`

5. **Page** — `lib/presentation/pages/<snake_name>_page/<snake_name>_page.dart`:
   - `class <Name>Page extends StatefulWidget` with `static const routeName` + `static Route route()` factory
   - Create the BLoC in `initState()` with `..add(const <Name>Event.initialize())`; close in `dispose()`
   - `build()` = `BlocProvider` + `BlocBuilder` + Freezed `state.when(initializing:, initialized:, error:)`
   - initializing -> `AppProgressWidget()`; error -> `AppErrorWidget(onTryAgain: ...)`; empty -> `AppEmptyContentWidget()`
   - LIST page renders pagingState via `PagedListView<String, <Item>Model>` (infinite_scroll_pagination v5,
     key K = String = item id), calling `bloc.add(const <Name>Event.fetchNextPage())` from the `fetchNextPage` callback
   - Navigation single-window: `routeName` + `route()` + `Navigator.push`

6. fvm dart run build_runner build --delete-conflicting-outputs   # REQUIRED — Freezed BLoC needs codegen
7. fvm dart format -l 140 <changed files>
8. fvm flutter analyze

## References (canonical templates)
- Page / BaseBloc / Freezed State+Event union / extension getters: `05-presentation-layer.md`, `10-code-templates.md`
- Pagination (PagingState-in-bloc, applyPage, PagedListView): `07-pagination.md`
- Shared widgets (App-prefixed: AppProgressWidget / AppErrorWidget / AppEmptyContentWidget): `05-presentation-layer.md`
```

> **Правило блюпринта: только Freezed-BLoC, без рукописного `Equatable`.** У нас `State`/`Event` — `@freezed sealed`-юнионы (`*.freezed.dart`, никогда `*.g.dart`), `when()`/`copyWith()` генерируются Freezed, вычисляемая логика — в extension-геттерах. Поэтому `new-page` **обязан** запускать codegen: Freezed-BLoC без него не компилируется. Канонические имена сабстейтов — `Initializing` / `Initialized` / `Error` через `const factory`. Общие виджеты — с префиксом `App`.

---

### 3.5. `/move-files`

**Назначение:** перенести Dart-файлы (или директорию) в новое место и обновить все импорт-ссылки.

`.claude/commands/move-files.md`:

```markdown
Move Dart files to a new location and update all import references (single package).

## Input
- `$ARGUMENTS`: `<source_path> <destination_path>` (source may be a file or directory)
- Example: `/move-files lib/domain/repository/item lib/domain/repository/catalog/item`

## Steps
1. Identify all `.dart` files to move (excluding `.freezed.dart`, `.g.dart`, `.config.dart`).
2. Compute old and new `package:nox_app/...` import paths.
3. Create destination directory if needed.
4. Move each source `.dart`; also move matching `.freezed.dart` / `.g.dart` alongside it.
5. Replace old import paths with new across the single package: `lib/`, plus `test/`, `integration_test/`.
   (No domain/lib, data/lib, data/test roots — this is ONE package.)
6. Fix `part` directives inside moved files if their relative paths changed.
7. Update barrel exports if they exist.
8. fvm dart run build_runner build --delete-conflicting-outputs   # regenerate moved generated files
9. fvm dart format -l 140 <changed files>
10. fvm flutter analyze

## Important
- Use full package imports `package:nox_app/...`, never relative (except `part`).
- Do NOT move test files unless explicitly requested.
- Do NOT hand-edit `.freezed.dart` / `.g.dart` / `.config.dart` — regenerate them.
```

---

### 3.6. `/rename-class`

**Назначение:** переименовать Dart-класс и обновить все ссылки — включая имена, которые выводит codegen.

`.claude/commands/rename-class.md`:

```markdown
Rename a Dart class and update all references across the codebase (single package).

## Input
- `$ARGUMENTS`: `<OldClassName> <NewClassName>`
- Example: `/rename-class ProductModel ItemModel`

## Steps
1. Find the class definition file; rename the class.
2. Replace all occurrences across the single package: `lib/`, `test/`, `integration_test/`.
3. Update generated names:
   - `_$OldName`          -> `_$NewName`
   - `_OldName`           -> `_NewName`
   - `$OldNameFromJson`   -> `$NewNameFromJson`     (entity layer only)
   - `_$OldNameFromJson`  -> `_$NewNameFromJson`    (entity layer only)
4. Rename the file if it matches the old class `snake_case`; update imports + `part` directives.
5. Also rename related `*Entity` / `*Mapper` / `*Dao` / `*Bloc` / `*Event` / `*State` classes
   if they follow naming conventions.
6. Update DI annotations if class names appear in them (e.g. `as: <Name>Repository`).
7. fvm dart run build_runner build --delete-conflicting-outputs   # ONE run
8. fvm dart format -l 140 <changed files>
9. fvm flutter analyze
```

---

### 3.7. `/update-json`

**Назначение:** сверить и привести JSON-фикстуру в соответствие текущей структуре entity.

`.claude/commands/update-json.md`:

```markdown
Validate and update sample JSON data files against current entity structure (single package).

## Input
- `$ARGUMENTS`: `<json_file_path> [entity_path]`
- Example: `/update-json test/fixtures/item_sample_data.json lib/data/entity/item_entity.dart`

## Steps
1. Read the JSON file.
2. If an entity path is given, read it; otherwise detect the root entity from the fixture name.
3. Trace all nested entities referenced by the root.
4. Compare JSON structure against entity fields: missing fields, extra fields, type mismatches.
   Remember entities are basic-types-only: enums as `.name` String, DateTime as ISO-8601 String.
5. Report discrepancies.
6. On confirmation: add missing fields (realistic sample values), remove dropped fields, fix types.
7. Verify the JSON parses via `<Name>Entity.fromJson`.

## Important
- Preserve existing valid values.
- Generate realistic sample data matching the domain (e.g. chats-list items).
- Maintain clean JSON formatting.
- JSON maps to the ENTITY layer (`*.g.dart` fromJson), NEVER to a domain model.
```

---

## 4. Стандартный трейлер команд

Каждая *генеративная* команда (`new-model`, `new-repository`, `new-page`, `move-files`, `rename-class`) заканчивается одним и тем же verify-трейлером. Интент централизован в `/check-build`, но шаги прописаны в каждой команде, чтобы она была самодостаточной:

```bash
fvm dart run build_runner build --delete-conflicting-outputs   # ОДИН прогон (один пакет — нет data->domain->root)
fvm dart format -l 140 <конкретные изменённые файлы>           # только изменённое; длина строки 140
fvm flutter analyze                                            # ноль ошибок перед остановкой
```

- `new-page` у нас **НЕ пропускает codegen**: Freezed-BLoC `State`/`Event` требуют `*.freezed.dart`.
- Передавать форматтеру **конкретные файлы**, не diff-режим: иначе переформатируется куча несвязанного.
- Все скрипты вызывают `fvm flutter` / `fvm dart` — никогда голые `flutter`/`dart`.

---

## 5. End-of-task чеклист (запускать перед остановкой по любой задаче)

- [ ] `fvm flutter pub get` — если трогали `pubspec.yaml`.
- [ ] `fvm dart run build_runner build --delete-conflicting-outputs` — **один прогон**, если трогали `@freezed` / `@JsonSerializable` / `@injectable`-входы.
- [ ] `fvm dart format -l 140 <только изменённые файлы>` — никогда весь репозиторий.
- [ ] `fvm flutter analyze` — **ноль ошибок**.
- [ ] `fvm flutter test` (+ `bloc_test` для затронутых BLoC; юнит-тест `applyPage` для затронутой пагинации).
- [ ] Импорты — только `package:nox_app/...` (никаких `../` кроме `part`).
- [ ] Никакого `print`/`debugPrint` в `lib/` — только `LogRepository`.
- [ ] BLoC-`State`/`Event` — `@freezed sealed` с `*.freezed.dart` (никогда `*.g.dart`/`fromJson`).
- [ ] Списочные экраны — `PagingState`-в-bloc через `applyPage` (никогда `PagingController`).
- [ ] Сгенерированные файлы (`*.g.dart`, `*.freezed.dart`, `*.config.dart`, `lib/design/gen/**`) не правились руками.

---

## Чеклист

- [ ] Все повседневные команды идут через `fvm` (`fvm flutter` / `fvm dart`), Flutter 3.44.1 из `.fvmrc`.
- [ ] Codegen — **ОДНА** команда `fvm dart run build_runner build --delete-conflicting-outputs`; явно зафиксировано, что нет `data→domain→root`-порядка (один пакет).
- [ ] Форматирование — только изменённые файлы, `-l 140`, явные пути.
- [ ] `mise run secrets:decrypt:<flavor>` и `mise run build:<platform>:<channel>` (`build:android:stage`/`build:android:prod`/`build:ios:stage`/`build:ios:prod`, имена совпадают с 09 §4) + Makefile-обёртки задокументированы; `sops`/`age` напрямую не вызываются.
- [ ] `.claude/commands/*` заведены: `/check-build`, `/new-model`, `/new-repository`, `/new-page`, `/move-files`, `/rename-class`, `/update-json`.
- [ ] `/new-repository` эмитит LIST-метод `get<Feature>s` (`fetch*`=single, `watch*`=stream, без `save*`/`fetch<Feature>s`-списка) + **единственный** `@freezed Get<Feature>sConfig` (`firstPage`/`nextPage`, `defaultPage = 1`) — **не** sealed-union `…RepositoryConfigs.list`, **не** `page: 0`.
- [ ] `/new-page` эмитит **Freezed**-BLoC-трио (`@freezed sealed` State+Event, `when()`/`copyWith()`, extension-геттеры) + пагинацию через `applyPage` (`PagingState<String, …>`, key = item id, offset через `nextPage`) — **не** рукописный Equatable; и **запускает** codegen в трейлере.
- [ ] Все команды используют одно-пакетные пути (`lib/domain/...`, `lib/data/...`, `lib/presentation/...`), env-лист `[Environment.dev, Environment.prod, Environment.test]` (test обязателен), импорты `package:nox_app/...`; BigInt/IPC/swift-to-dart не эмитятся.
- [ ] Каждая генеративная команда заканчивается трейлером codegen(один прогон) → format(изменённые) → analyze.
- [ ] Команды кросс-ссылаются на [10-code-templates.md](10-code-templates.md) и нужный layer-док по каноническим именам файлов.
