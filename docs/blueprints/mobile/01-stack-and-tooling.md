# 01 — Стек и инструментарий

> **Назначение:** зафиксировать ровно один набор версий SDK, единый `pubspec.yaml` для одного Dart-пакета `nox_app`, кодген-стек (freezed + json_serializable + injectable + flutter_gen), `build.yaml` и строгий `analysis_options.yaml`. Это «список покупок» и tooling-контракт перед написанием любого кода.
> **Когда читать:** сразу после `00-architecture-overview.md` и до любого слоевого документа (`03`/`04`/`05`). Перед первым `pub get` + `build_runner`.
> **Связанные документы:** `00-architecture-overview.md` (общая картина), `02-dependency-injection.md` (DI-обвязка под injectable), `06-theming.md` (flutter_screenutil 360×779 + ThemeExtension), `07-pagination.md` (infinite_scroll_pagination v5), `09-build-and-secrets-infra.md` (FVM/флейворы/SOPS), `11-scaffolding-plan.md` (порядок создания), `12-dev-commands.md` (команды кодгена и форматирования).

---

## Версии SDK

- **Flutter**: `3.44.1`, пин через **FVM** в `.fvmrc`.
- **Dart SDK**: ограничение `>=3.12.0 <4.0.0` (парный к Flutter 3.44.1).
- **Длина строки**: `140` везде (`formatter: page_width: 140` в `analysis_options.yaml`; команды используют `fvm dart format -l 140`).
- **Платформы**: iOS, Android, Windows, Linux, macOS (web — вне scope). Desktop-floor по умолчанию Flutter 3.44.1: Windows 10 / macOS 10.15 / GTK3 (Linux).

`.fvmrc` в корне пакета:

```json
{
  "flutter": "3.44.1"
}
```

Всегда вызывайте Flutter/Dart через FVM (`fvm flutter ...`, `fvm dart ...`), чтобы использовалась запиненная версия. Сборочные скрипты резолвят SDK из симлинка `.fvm/flutter_sdk`. Кэш FVM (`.fvm/`) — в `.gitignore`; коммитится только `.fvmrc`. Установка SDK один раз на машину:

```bash
fvm install   # читает .fvmrc, скачивает Flutter 3.44.1 в gitignored .fvm/
```

> **Один пакет.** В этом блюпринте — **единственный Dart-пакет `nox_app`**, без раскладки на несколько path-зависимых пакетов. Слои — это папки внутри одного `lib/` (`lib/domain`, `lib/data`, `lib/presentation`, `lib/di`, `lib/general`, `lib/design`, `lib/resource`). Один `pubspec.yaml`, один `build.yaml`, один прогон `build_runner`. Поэтому ниже — **ровно один** манифест зависимостей. Подробности раскладки — в `00-architecture-overview.md` и `11-scaffolding-plan.md`.

---

## Манифест зависимостей (`pubspec.yaml`)

Полный файл ниже — готов к копированию. Имя пакета — `nox_app`, все импорты вида `package:nox_app/...`. Пины версий и inline-комментарии сохранены: они кодируют разрешённые конфликты — не трогайте без причины.

> **Соответствие актуальному скелету.** Блок ниже — канонический «полный» манифест. В реально закоммиченном `pubspec.yaml` (Feature-001) часть позиций пока **отсутствует или закомментирована**: feature-gated зависимости (`firebase_*`, `permission_handler`, `file_picker`, `image_picker`, `connectivity_plus`, vendor-SDK аналитики) лежат закомментированными плейсхолдерами и раскомментируются при активации соответствующего дока; `fonts:`-блок ещё **не объявлен** (`AppFont` — шаблон-плейсхолдер, появляется когда приедут реальные шрифтовые ассеты). Версии-пины держим здесь, потому что доки 14/15/16/17 ссылаются за ними сюда.

```yaml
name: nox_app
description: "NOX secure messenger."
publish_to: 'none'

# CalVer + shifted-epoch build (YY.M.D+EPOCH, без ведущих нулей; см. 09-build-and-secrets-infra.md §9).
# CI переписывает это значение через commit.
version: 26.1.1+0

environment:
  sdk: '>=3.12.0 <4.0.0'
  flutter: 3.44.1

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.9     # iOS-style icons

  # --- State management ---
  flutter_bloc: 9.1.1
  bloc_concurrency: 0.3.0     # restartable()/droppable()/sequential() event transformers

  # --- Core model / reactive ---
  freezed_annotation: 3.1.0
  json_annotation: ^4.12.0    # явная зависимость для *.g.dart
  rxdart: 0.28.0              # BehaviorSubject / PublishSubject в репозиториях и блоках
  collection: 1.19.1          # collection-расширения
  intl: 0.20.2                # ТОЛЬКО форматирование дат/чисел (без i18n-инфраструктуры)
  uuid: ^4.5.3                # генерация id

  # --- DI ---
  injectable: ^3.0.0
  get_it: ^9.2.1

  # --- Network ---
  dio: ^5.9.2

  # --- Pagination / UI list ---
  infinite_scroll_pagination: 5.1.1  # v5 PagingState API (bloc-owned, не widget-owned)
  skeletonizer: ^2.1.3        # shimmer-плейсхолдеры
  flutter_screenutil: 5.9.3   # адаптивные размеры, design size 360x779
  cached_network_image: 3.4.1
  flutter_svg: ^2.3.0
  url_launcher: 6.3.2

  # --- Links ---
  app_links: ^7.1.1           # обработка входящих ссылок (deep / universal links), см. 13-deep-links.md

  # --- Local store ---
  shared_preferences: ^2.5.5       # простой key/value (флаги, themeMode)
  # flutter_secure_storage: шифрованное хранилище (refresh-токен); кросс-платформен — macOS Keychain /
  # Windows DPAPI / Linux libsecret (рантайм libsecret-1-0 — Linux packaging concern, FUTURE; см. 14 secure-storage-нота).
  flutter_secure_storage: ^10.3.1
  # sembast: документная NoSQL (schema-less) для cache-first репозиториев — OQ-1 закрыт: Sembast,
  # бэкенд databaseFactoryIo на mobile/desktop (web — вне scope).
  sembast: ^3.8.8
  path_provider: 2.1.5             # резолв директории БД для Sembast (IO-бэкенд)

  # --- Misc ---
  logger: ^2.7.0
  # 10.x безопасен — нет цепочки flutter_quill/win32; пин <10 нужен ТОЛЬКО при её появлении.
  package_info_plus: ^10.1.0

  # --- Feature-gated (в актуальном скелете ЗАКОММЕНТИРОВАНЫ; раскомментируются при активации
  #     соответствующего дока; major-пины ПРОВИЗОРНЫ — сверить latest stable перед реализацией) ---
  # firebase_*: push/FCM (mobile-only: нет desktop-impl; desktop push = disabled no-op — см. 15 §Desktop fallback).
  # firebase_core: ^4.0.0        # push/FCM bootstrap — см. 15-push-notifications.md
  # firebase_messaging: ^16.0.0  # device-токен, foreground/background handlers — 15
  # permission_handler: ^12.0.0  # iOS APNs / Android 13+ POST_NOTIFICATIONS — 15
  # file_picker: ^8.0.0          # выбор документов (pdf/docx) — см. 16-file-upload.md
  # image_picker: ^1.1.0         # камера/галерея — 16
  # connectivity_plus: ^6.1.0    # сетевое состояние (онлайн/офлайн) — см. 14-networking-and-auth.md §5
  # клиентская аналитика — vendor-neutral, opt-in; SDK не выбран (пример: mixpanel_flutter), см. 17-analytics.md:
  # <analytics_sdk>: ^x.y.z

dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter

  flutter_lints: 6.0.0
  build_runner: ^2.15.0
  freezed: ^3.2.5
  json_serializable: ^6.14.0
  injectable_generator: ^3.0.2
  flutter_gen_runner: ^5.14.1
  mockito: ^5.6.4   # 5.6.5+ тянет analyzer ^13, конфликтующий с injectable_generator (analyzer <13)
  bloc_test: ^10.0.0          # blocTest-хелперы

flutter:
  uses-material-design: true
  assets:
    - assets/
    - assets/png/
    - assets/svg/
    - assets/animation/

  # fonts:-блок в актуальном скелете НЕ объявлен (AppFont — шаблон-плейсхолдер).
  # Раскомментируйте + переименуйте + положите файлы под assets/fonts/,
  # когда приедут реальные шрифты:
  # fonts:
  #   - family: AppFont
  #     fonts:
  #       - asset: assets/fonts/app_font/Regular.otf
  #         weight: 400
  #       - asset: assets/fonts/app_font/Medium.otf
  #         weight: 500
  #       - asset: assets/fonts/app_font/Semibold.otf
  #         weight: 600

flutter_gen:
  output: lib/design/gen/
  line_length: 140
  integrations:
    flutter_svg: true
    lottie: false
  assets:
    enabled: true
    outputs:
      style: dot-delimiter
      package_parameter_enabled: false
  fonts:
    enabled: false
  colors:
    enabled: false
```

> **`dependency_overrides`.** В этом проекте — **пусто**. Добавляйте override только когда реально упёрлись в ошибку резолва (например, конфликт транзитивов вокруг `win32`). Не копируйте overrides «на всякий случай» из чужих проектов.

> **`config/stage.json` + `config/prod.json`.** Закоммиченные build-input файлы (не bundled-ассеты, **не** перечислены в `flutter: assets:`, новой зависимости не вводят). Каждый несёт **только** `{"app.flavor": "stage|prod"}` и потребляется через `--dart-define-from-file` — единообразный флейвор-механизм для всех платформ, включая desktop (Windows/Linux/macOS), у которых нет нативной flavor-машинерии Android/iOS (см. `09-build-and-secrets-infra.md`).

> **Почему нет `equatable`.** Библиотека **намеренно исключена** из зависимостей. Value-equality (`==` / `hashCode`) в этом проекте полностью обеспечивает **Freezed**: каждый `@freezed`-класс генерирует структурное равенство сам — это покрывает и BLoC-state/event (`05-presentation-layer.md`), и любые value-объекты. Правило: **где нужен value-объект, делайте его `@freezed`-классом — не наследуйте `Equatable` и не добавляйте `equatable`**. `equatable` тянем обратно только если найдётся кейс, который Freezed реально не закрывает (на сегодня такого нет).

> **Не тянем (desktop-shell).** Адаптивный shell строится на **кастомном breakpoint** (`NavigationBar`↔`NavigationRail`, ширина-триггер `840dp` = `Constants.railBreakpoint`; single-window; центрально-докнутый `+` FAB; 2 destination — Chats/Settings; `IndexedStack`-body; без profile-экрана), **без** `flutter_adaptive_scaffold` / `custom_adaptive_scaffold`. В скелете также **не добавляются** `window_manager` / `bitsdojo_window` / `desktop_multi_window` / `yaru`: дефолтный single-window runner, нативный оконный chrome платформы и единый Material 3 без desktop-специфичных пакетов. Любой из них вводится только когда появится конкретная потребность (custom window chrome, multi-window и т.п.), не «на всякий случай».

> **Feature-gated зависимости.** `firebase_core`/`firebase_messaging`/`permission_handler` (push — `15`), `file_picker`/`image_picker` (upload — `16`), `connectivity_plus` (`14` §5), vendor-SDK аналитики (`17`) вынесены отдельной группой выше и в актуальном скелете **закомментированы** — они вводятся **при активации соответствующей фичи**, не нужны для скелета. **Major-версии ПРОВИЗОРНЫ**: перед реализацией сверить latest stable (pub.dev) и согласовать с владельцем. Доки 15/16/17/14 ссылаются сюда за версиями — поэтому пины живут тут, а не дублируются в каждом доке. Push-зависимости (`firebase_*`) — **mobile-only**: desktop-impl нет, desktop push = disabled no-op, вводится с первым desktop-консьюмером (см. 15 §Desktop fallback).

> **Аналитика — vendor-neutral, opt-in.** Конкретный SDK аналитики **не выбран**: в манифесте он стоит плейсхолдером-комментарием, `mixpanel_flutter` приведён лишь как **пример** вендора. NOX — E2EE-продукт: аналитика **opt-in** (выключена до явного согласия), без PII. Детали — `17-analytics.md`. Не хардкодьте конкретного вендора в зависимостях скелета.

### Почему именно эти зависимости

| Пакет | Роль в архитектуре |
|---|---|
| `flutter_bloc` + `bloc_concurrency` | управление состоянием; event-трансформеры (`restartable`/`droppable`/`sequential`) поверх Freezed-событий. См. `05-presentation-layer.md`. |
| `freezed_annotation` (+ dev `freezed`) | sealed unions для State/Event и доменных моделей (`*.freezed.dart`, без `*.g.dart` на BLoC-типах). См. `03`/`05`. |
| `json_annotation` (+ dev `json_serializable`) | сериализация **entity-слоя** (`*.g.dart`). Доменные модели JSON не несут. См. `04-data-layer.md`. |
| `rxdart` | `BehaviorSubject<RepositoryResult<...>>` в репозиториях поверх реактивного Sembast-DAO. |
| `injectable` + `get_it` (+ dev `injectable_generator`) | единый `configureDependencies(String env)` + `$initGetIt`. См. `02-dependency-injection.md`. |
| `dio` | HTTP-клиент к бэкенду NOX (эндпойнты вроде `/api/v1/...` — пример; бэкенд/протокол NOX ещё не выбран, заменить на реальный контракт). |
| `infinite_scroll_pagination` 5.1.1 | stateless `PagingState`-в-bloc (без `PagingController`). См. `07-pagination.md`. |
| `flutter_screenutil` 5.9.3 | адаптивные spacing/typography токены, design size 360×779. См. `06-theming.md`. |
| `skeletonizer` | shimmer-плейсхолдеры для загрузки. |
| `cached_network_image` / `flutter_svg` | растровые картинки (например, аватары) и векторные ассеты. |
| `sembast` + `path_provider` | cache-first DAO; env-scoped `AppDatabase` (Dev/Prod = IO `databaseFactoryIo` на mobile/desktop, Test = memory). См. `04`. |
| `shared_preferences` | простые флаги, `themeMode`. |
| `flutter_secure_storage` | шифрованное хранилище refresh-токена; кросс-платформенно (macOS Keychain / Windows DPAPI / Linux libsecret). |
| `logger` | реализация обязательного `LogRepository` (единый канал, без raw `print`). |
| `package_info_plus` | версия/билд приложения (регистрируется в DI-бутстрапе первым консьюмером). |
| `app_links` | приём входящих ссылок (deep / universal links) — cold-start + warm-поток; парсятся в `DeepLinkRepository`. См. `13-deep-links.md`. |

---

## Кодген-стек

Четыре генератора работают под одним вызовом `build_runner`:

| Генератор | Срабатывает на | Производит |
|---|---|---|
| `freezed` | `@freezed`-классы | `*.freezed.dart` |
| `json_serializable` | `@JsonSerializable` / freezed-фабрики с `fromJson` | `*.g.dart` |
| `injectable_generator` | `@injectable` / `@LazySingleton` / `@singleton` | `lib/di/configure_dependencies.config.dart` |
| `flutter_gen_runner` | ассеты из `pubspec` | `lib/design/gen/assets.gen.dart` |

### `build.yaml`

Актуальный `build.yaml` — **минимальный**: в нём только не-дефолтные опции `json_serializable`. Остальные опции — дефолты генератора, их не объявляем.

```yaml
targets:
  $default:
    builders:
      json_serializable:
        options:
          field_rename: snake
          explicit_to_json: true
          create_to_json: true
```

Опции, которые держим verbatim:

| Опция | Значение | Зачем |
|---|---|---|
| `create_to_json` (+ дефолтный `create_factory`) | `true` | генерируем `toJson` / `fromJson` |
| `explicit_to_json` | `true` | вложенные модели сериализуются своим `toJson()` |
| `field_rename` | `snake` | entity-поля в camelCase ↔ snake_case JSON-ключи бэкенда; per-field override через `@JsonKey` |

> `explicit_to_json: true` — load-bearing настройка: вложенные entity внутри конверта `data` сериализуются собственным `toJson()`. `field_rename: snake` соответствует snake_case-payload'ам бэкенда (точечные исключения — через `@JsonKey(name: ...)`).

> Пример: бэкенд возвращает unified-конверт `{data, timestamp, trace_id, meta}`; entity-слой парсит его через `ResponseEntity<T>` + `EntityConverter<E>` (см. `04-data-layer.md`). (Форма конверта — пример: бэкенд/протокол NOX ещё не выбран, заменить на реальный контракт; сам паттерн `ResponseEntity<T>` + `EntityConverter<E>` сохраняется независимо от формы.)

### Запуск кодгена

```bash
fvm dart run build_runner build --delete-conflicting-outputs
```

`--delete-conflicting-outputs` удаляет устаревшие сгенерированные файлы перед регенерацией. Так как пакет один — это **один** прогон без порядка «data → domain → root» (такой порядок осмыслен только при раскладке на несколько path-зависимых пакетов; здесь он не нужен). Канонический скрипт-обёртка и watch-режим — в `12-dev-commands.md`.

---

## Конфигурация линтера (`analysis_options.yaml`)

Один файл в корне пакета. Используем **стандартный линтер Flutter** — `flutter_lints` (последняя мажорная, `6.x`) **как есть**, без кастомных правил. `errors`-карта — **минимальная**: единственная запись подавляет annotation-noise от freezed/json_serializable. Форматирование — 140 колонок через `formatter: page_width: 140`. Сгенерированные файлы и design-system handoff Dart исключены из анализа.

```yaml
# Стандартный линтер Flutter + форматирование на 140 колонок.
include: package:flutter_lints/flutter.yaml

analyzer:
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
    - "**/*.config.dart"
    - "lib/design/gen/**"
    - "docs/**"          # design-system handoff Dart lives here; not part of the app
    - "build/**"
  errors:
    invalid_annotation_target: ignore   # freezed/json_serializable annotation noise

formatter:
  page_width: 140
```

Принципы конфигурации:

- **Только стандартный `flutter_lints`.** Большие кастомные спеки (десятки явных правил + `errors`-карта, поднимающая часть проблем до уровня ошибки) в этом блюпринте **намеренно не используются**: проект опирается на рекомендованный Dart/Flutter-линтер. Если конкретное правило когда-нибудь действительно понадобится — добавляйте его **осознанно и точечно**, а не копируйте чужой большой набор «на всякий случай».
- **Минимальная `errors`-карта.** Единственная запись — `invalid_annotation_target: ignore`: гасит annotation-noise генераторов (freezed/json_serializable кладут аннотации на таргеты, которые анализатор иначе считает невалидными). Больше ничего в `errors` не поднимаем.
- **Длина строки — 140.** `formatter: page_width: 140` в `analysis_options.yaml` — единственный источник истины; `fvm dart format` подхватывает его автоматически (команды форматирования — в `12-dev-commands.md`; для явности они также передают `-l 140`).
- **Исключения из анализа.** Сгенерированные файлы (`*.g.dart`, `*.freezed.dart`, `*.config.dart`, `lib/design/gen/**`) **никогда не правятся руками** — только регенерация через `build_runner`. Дополнительно исключён `docs/**`: там лежит сгенерированный design-system handoff Dart (`docs/design/system/nox-handoff/flutter/`), который не часть приложения. Шаблоны `*.gr.dart` / `*.mocks.dart` в исключениях **пока нет** — добавьте их, когда появятся соответствующие генераторы (router-кодген / mockito-`@GenerateMocks`).

---

## Импорты и сгенерированные файлы

- Все импорты — полные `package:nox_app/...`. Относительные `../` запрещены, исключение — директивы `part`/`part of` (для `*.freezed.dart` / `*.g.dart`).
- Сгенерированные артефакты (`*.g.dart`, `*.freezed.dart`, `*.config.dart`, `lib/design/gen/**`) исключены из анализа и не редактируются руками — только регенерация через `build_runner`.
- Имя пакета `nox_app` владелец может переименовать; в таком случае это отмечается **один раз в `README.md`**, и меняются все `package:`-префиксы разом.

---

## Чеклист

- [ ] `.fvmrc` закоммичен со значением `{"flutter": "3.44.1"}`; `.fvm/` в `.gitignore`; `fvm install` отработал.
- [ ] Один `pubspec.yaml` с `name: nox_app`, `description: "NOX secure messenger."`, `sdk: '>=3.12.0 <4.0.0'`, `flutter: 3.44.1`.
- [ ] Рантайм-набор присутствует целиком: `flutter_bloc`, `bloc_concurrency`, `rxdart`, `freezed_annotation`, `json_annotation`, `get_it`, `injectable`, `dio`, `infinite_scroll_pagination: 5.1.1`, `flutter_screenutil: 5.9.3`, `skeletonizer`, `cached_network_image`, `flutter_svg`, `url_launcher`, `app_links`, `intl`, `uuid`, `collection`, `logger`, `path_provider`, `shared_preferences`, `flutter_secure_storage`, `sembast`, `package_info_plus` (^10), `cupertino_icons`.
- [ ] Feature-gated зависимости (`firebase_*`, `permission_handler`, `file_picker`, `image_picker`, `connectivity_plus`, vendor-SDK аналитики) — закомментированы; раскомментируются при активации дока 14/15/16/17.
- [ ] `dev_dependencies` содержит `build_runner`, `freezed`, `json_serializable`, `injectable_generator`, `flutter_gen_runner`, `flutter_lints: 6.0.0`, `mockito: ^5.6.4` (с комментарием про конфликт analyzer/injectable_generator), `bloc_test`, `integration_test`, `flutter_test`.
- [ ] `dependency_overrides` отсутствует (или содержит только реально необходимые из-за конфликта резолва).
- [ ] `build.yaml` создан минимальным: `field_rename: snake`, `explicit_to_json: true`, `create_to_json: true`; `flutter_gen` пишет в `lib/design/gen/`.
- [ ] `analysis_options.yaml` = стандартный `flutter_lints` + `formatter: page_width: 140` + минимальная `errors`-карта (`invalid_annotation_target: ignore`); из анализа исключены `*.g.dart`/`*.freezed.dart`/`*.config.dart`/`lib/design/gen/**`/`docs/**`/`build/**`.
- [ ] Все импорты — `package:nox_app/...`; относительные `../` отсутствуют (кроме `part`-директив).
- [ ] Первый `fvm dart pub get` + `fvm dart run build_runner build --delete-conflicting-outputs` прошли без ошибок; сгенерированные файлы появились.
- [ ] `fvm flutter analyze` проходит без ошибок.
- [ ] Нигде нет ссылок на трёх-пакетную раскладку (`domain:`/`data:` как path-deps, отдельные `build.yaml` по слоям, порядок «data → domain → root»).
</content>
</invoke>
