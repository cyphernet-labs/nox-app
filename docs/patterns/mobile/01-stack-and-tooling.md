# 01 — Стек и инструментарий

> **Назначение:** зафиксировать ровно один набор версий SDK, единый `pubspec.yaml` для одного Dart-пакета `nox_app`, кодген-стек (freezed + json_serializable + injectable + flutter_gen), `build.yaml` и строгий `analysis_options.yaml`. Это «список покупок» и tooling-контракт перед написанием любого кода.
> **Когда читать:** сразу после `00-architecture-overview.md` и до любого слоевого документа (`03`/`04`/`05`). Перед первым `pub get` + `build_runner`.
> **Связанные документы:** `00-architecture-overview.md` (общая картина), `02-dependency-injection.md` (DI-обвязка под injectable), `06-theming.md` (flutter_screenutil 360×779 + ThemeExtension), `07-pagination.md` (infinite_scroll_pagination v5), `09-build-and-secrets-infra.md` (FVM/флейворы/SOPS), `11-scaffolding-plan.md` (порядок создания), `12-dev-commands.md` (команды кодгена и форматирования).

---

## Версии SDK

- **Flutter**: `3.44.1`, пин через **FVM** в `.fvmrc`.
- **Dart SDK**: ограничение `>=3.12.0 <4.0.0` (парный к Flutter 3.44.1).
- **Длина строки**: `140` везде (`formatter: page_width: 140` в `analysis_options.yaml`; команды используют `fvm dart format -l 140`).

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

```yaml
name: nox_app
description: "NOX secure messenger (iOS + Android)."
publish_to: 'none'

# CalVer + shifted-epoch build (YY.M.D+EPOCH, без ведущих нулей; см. 09-build-and-secrets-infra.md §9); CI переписывает это значение через commit.
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
  flutter_secure_storage: ^10.3.1  # шифрованное хранилище (refresh-токен)
  sembast: ^3.8.8                  # документная NoSQL (schema-less) для cache-first репозиториев — OQ-1 закрыт: Sembast; web-клиент переиспользует через sembast_web (databaseFactoryWeb)
  path_provider: 2.1.5             # резолв директории БД для Sembast (IO-бэкенд)

  # --- Misc ---
  logger: ^2.7.0
  # 10.x безопасен — у нас НЕТ цепочки flutter_quill/win32; пин <10 нужен ТОЛЬКО при её появлении.
  package_info_plus: ^10.1.0

  # --- Feature-gated (вводятся при активации соответствующего дока; major-пины ПРОВИЗОРНЫ — сверить latest stable перед реализацией) ---
  firebase_core: ^4.0.0        # push/FCM bootstrap — см. 15-push-notifications.md
  firebase_messaging: ^16.0.0  # device-токен, foreground/background handlers — 15
  permission_handler: ^12.0.0  # iOS APNs / Android 13+ POST_NOTIFICATIONS — 15
  file_picker: ^8.0.0          # выбор документов (pdf/docx) — см. 16-file-upload.md
  image_picker: ^1.1.0         # камера/галерея — 16
  connectivity_plus: ^6.1.0    # сетевое состояние (онлайн/офлайн) — см. 14-networking-and-auth.md §5
  mixpanel_flutter: ^2.3.0     # клиентская аналитика — см. 17-analytics.md

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
  mockito: ^5.7.0
  bloc_test: ^10.0.0          # blocTest-хелперы

flutter:
  uses-material-design: true
  assets:
    - assets/
    - assets/png/
    - assets/svg/
    - assets/animation/

  fonts:
    - family: AppFont          # переименуйте + положите файлы под assets/fonts/
      fonts:
        - asset: assets/fonts/app_font/Regular.otf
          weight: 400
        - asset: assets/fonts/app_font/Medium.otf
          weight: 500
        - asset: assets/fonts/app_font/Semibold.otf
          weight: 600

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

> **Почему нет `equatable`.** Библиотека **намеренно исключена** из зависимостей. Value-equality (`==` / `hashCode`) в этом проекте полностью обеспечивает **Freezed**: каждый `@freezed`-класс генерирует структурное равенство сам — это покрывает и BLoC-state/event (`05-presentation-layer.md`), и любые value-объекты. Правило: **где нужен value-объект, делайте его `@freezed`-классом — не наследуйте `Equatable` и не добавляйте `equatable`**. `equatable` тянем обратно только если найдётся кейс, который Freezed реально не закрывает (на сегодня такого нет).

> **Feature-gated зависимости.** `firebase_core`/`firebase_messaging`/`permission_handler` (push — `15`), `file_picker`/`image_picker` (upload — `16`), `connectivity_plus` (`14` §5), `mixpanel_flutter` (`17`) вынесены отдельной группой выше — они вводятся **при активации соответствующей фичи**, не нужны для скелета. **Major-версии ПРОВИЗОРНЫ**: перед реализацией сверить latest stable (pub.dev) и согласовать с владельцем. Доки 15/16/17/14 ссылаются сюда за версиями — поэтому пины живут тут, а не дублируются в каждом доке.

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
| `sembast` + `path_provider` | cache-first DAO; env-scoped `AppDatabase` (Dev/Prod = IO, Test = memory). См. `04`. |
| `shared_preferences` | простые флаги, `themeMode`. |
| `flutter_secure_storage` | шифрованное хранилище refresh-токена. |
| `logger` | реализация обязательного `LogRepository` (единый канал, без raw `print`). |
| `package_info_plus` | версия/билд приложения (регистрируется в DI-бутстрапе). |
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

Единственная значимая не-дефолтная настройка — **`explicit_to_json: true`** (вложенные модели сериализуются через собственный `toJson()`):

```yaml
targets:
  $default:
    builders:
      json_serializable:
        options:
          any_map: false
          checked: false
          constructor: ""
          create_factory: true
          create_field_map: false
          create_json_keys: false
          create_per_field_to_json: false
          create_to_json: true
          disallow_unrecognized_keys: false
          explicit_to_json: true
          field_rename: none
          generic_argument_factories: false
          ignore_unannotated: false
          include_if_null: true
```

Опции, которые держим verbatim:

| Опция | Значение | Зачем |
|---|---|---|
| `create_factory` / `create_to_json` | `true` | генерируем `fromJson` / `toJson` |
| `explicit_to_json` | `true` | вложенные модели сериализуются своим `toJson()` |
| `field_rename` | `none` | без авто-переименования; управление per-field через `@JsonKey` |
| `include_if_null` | `true` | null-поля сохраняются в выводе |
| `disallow_unrecognized_keys` | `false` | толерантность к лишним/forward-совместимым полям API |

> Пример: бэкенд возвращает unified-конверт `{data, timestamp, trace_id, meta}`; entity-слой парсит его через `ResponseEntity<T>` + `EntityConverter<E>` (см. `04-data-layer.md`). `explicit_to_json: true` критичен для вложенных entity внутри `data`. (Форма конверта — пример: бэкенд/протокол NOX ещё не выбран, заменить на реальный контракт; сам паттерн `ResponseEntity<T>` + `EntityConverter<E>` сохраняется независимо от формы.)

### Запуск кодгена

```bash
fvm dart run build_runner build --delete-conflicting-outputs
```

`--delete-conflicting-outputs` удаляет устаревшие сгенерированные файлы перед регенерацией. Так как пакет один — это **один** прогон без порядка «data → domain → root» (такой порядок осмыслен только при раскладке на несколько path-зависимых пакетов; здесь он не нужен). Канонический скрипт-обёртка и watch-режим — в `12-dev-commands.md`.

---

## Конфигурация линтера (`analysis_options.yaml`)

Один файл в корне пакета. Используем **стандартный линтер Flutter** — `flutter_lints` (последняя мажорная, `6.x`) **как есть**, без кастомных правил и без `errors`-карты. Форматирование — 140 колонок через `formatter: page_width: 140`. Сгенерированные файлы исключены из анализа.

```yaml
# Стандартный линтер Flutter + форматирование на 140 колонок.
include: package:flutter_lints/flutter.yaml

formatter:
  page_width: 140

analyzer:
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
    - "**/*.config.dart"
    - "**/*.gr.dart"
    - "**/*.mocks.dart"
    - lib/design/gen/**
    - build/**
```

Принципы конфигурации:

- **Только стандартный `flutter_lints`.** Большие кастомные спеки (десятки явных правил + `errors`-карта, поднимающая часть проблем до уровня ошибки) в этом блюпринте **намеренно не используются**: проект опирается на рекомендованный Dart/Flutter-линтер. Если конкретное правило когда-нибудь действительно понадобится — добавляйте его **осознанно и точечно**, а не копируйте чужой большой набор «на всякий случай».
- **Длина строки — 140.** `formatter: page_width: 140` в `analysis_options.yaml` — единственный источник истины; `fvm dart format` подхватывает его автоматически (команды форматирования — в `12-dev-commands.md`; для явности они также передают `-l 140`).
- **Сгенерированные файлы** (`*.g.dart`, `*.freezed.dart`, `*.config.dart`, `*.mocks.dart`, `lib/design/gen/**`) исключены из анализа и **никогда не правятся руками** — только регенерация через `build_runner`.

---

## Импорты и сгенерированные файлы

- Все импорты — полные `package:nox_app/...`. Относительные `../` запрещены, исключение — директивы `part`/`part of` (для `*.freezed.dart` / `*.g.dart`).
- Сгенерированные артефакты (`*.g.dart`, `*.freezed.dart`, `*.config.dart`, `lib/design/gen/**`) исключены из анализа и не редактируются руками — только регенерация через `build_runner`.
- Имя пакета `nox_app` владелец может переименовать; в таком случае это отмечается **один раз в `README.md`**, и меняются все `package:`-префиксы разом.

---

## Чеклист

- [ ] `.fvmrc` закоммичен со значением `{"flutter": "3.44.1"}`; `.fvm/` в `.gitignore`; `fvm install` отработал.
- [ ] Один `pubspec.yaml` с `name: nox_app`, `sdk: '>=3.12.0 <4.0.0'`, `flutter: 3.44.1`.
- [ ] Рантайм-набор присутствует целиком: `flutter_bloc`, `bloc_concurrency`, `rxdart`, `freezed_annotation`, `json_annotation`, `get_it`, `injectable`, `dio`, `infinite_scroll_pagination: 5.1.1`, `flutter_screenutil: 5.9.3`, `skeletonizer`, `cached_network_image`, `flutter_svg`, `url_launcher`, `app_links`, `intl`, `uuid`, `collection`, `logger`, `path_provider`, `shared_preferences`, `flutter_secure_storage`, `sembast`, `package_info_plus` (^10), `cupertino_icons`.
- [ ] `dev_dependencies` содержит `build_runner`, `freezed`, `json_serializable`, `injectable_generator`, `flutter_gen_runner`, `flutter_lints: 6.0.0`, `mockito`, `bloc_test`, `integration_test`, `flutter_test`.
- [ ] `dependency_overrides` отсутствует (или содержит только реально необходимые из-за конфликта резолва).
- [ ] `build.yaml` создан с `explicit_to_json: true`; `flutter_gen` пишет в `lib/design/gen/`.
- [ ] `analysis_options.yaml` = стандартный `flutter_lints` + `formatter: page_width: 140`; без кастомных правил и без `errors`-карты; сгенерированные файлы (`*.g.dart`, `*.freezed.dart`, `*.config.dart`, `lib/design/gen/**`) исключены из анализа.
- [ ] Все импорты — `package:nox_app/...`; относительные `../` отсутствуют (кроме `part`-директив).
- [ ] Первый `fvm dart pub get` + `fvm dart run build_runner build --delete-conflicting-outputs` прошли без ошибок; сгенерированные файлы появились.
- [ ] `fvm flutter analyze` проходит без ошибок.
- [ ] Нигде нет ссылок на трёх-пакетную раскладку (`domain:`/`data:` как path-deps, отдельные `build.yaml` по слоям, порядок «data → domain → root»).
