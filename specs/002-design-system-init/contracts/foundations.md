# Контракт: сквозные non-widget-фундаменты дизайн-системы

> **Источник «как»:** блюпринт `docs/blueprints/mobile/06-theming.md` (главный), `01-stack-and-tooling.md`, `10-code-templates.md`.
> **Источник истины дизайна:** `docs/design/spec/design-system.md` (v0.2) §3/§8/§10/§11, `docs/design/spec/overview.md` (форматы даты/времени, file-icon-map, generated avatar, сетевой копирайт), машинные токены `docs/design/system/nox-handoff/tokens/*.tokens.json` (W3C DTCG) → генерируемый Dart `docs/design/system/nox-handoff/flutter/nox_*.dart`.
> **Покрывает требования:** FR-010 (шрифты), FR-011 (иконки + file-type-map), FR-012 (форматтеры дат), FR-013 (UI-microcopy / network), FR-014 (фундамент аватаров), FR-015 (реестр ассетов + fallback), FR-016 (system-overlay), FR-018 (устранение дублей канала ассетов), FR-020 (перенос icons.md из `nox-handoff-2`), FR-024 (a11y — в части, относящейся к этим фундаментам).
> **Природа:** контракт (форма + правила), а не реализация. Дословные copy-paste-шаблоны — в блюпринте `06`/`10`. Тема уровня `ColorScheme`/`ThemeData`/`AppColors`/component-сабтем — отдельный контракт (`theme.md`); здесь — всё, что лежит **вне** `lib/design/theme` и **не является виджетом**: иконки, шрифты, ассеты, форматтеры, microcopy, фундамент аватаров (как сквозной примитив) и канон system-overlay.

---

## 0. Обзор и границы

Эти фундаменты — то «абсолютно всё, кроме виджетов», что лежит вне `lib/design/theme`, но является дизайн-системой: подключённые иконки и шрифты, реестр ассетов, форматтеры относительного времени, канон UI-строк, детерминированный фундамент аватаров и глобальное применение system-overlay. Каждый фундамент — **единый канонический канал на роль**: после доводки нет двух параллельных классов, решающих одну задачу.

**Раскладка** (где живёт каждый фундамент):

| Фундамент | Файл / артефакт | Раздел |
|---|---|---|
| Реестр иконок `NoxIcons` + file-type-map | `lib/design/nox_icons.dart` | §1 |
| Пакет иконок | `pubspec.yaml` → `material_symbols_icons` | §1.1 |
| Стратегия шрифтов (Sans native + Mono bundled) | `pubspec.yaml::flutter.fonts` + `assets/fonts/` + `nox_text_theme.dart` (generated) | §2 |
| Реестр ассетов | `lib/design/gen/assets.gen.dart` (flutter_gen, канонический) + `pubspec.yaml::flutter.assets` | §3 |
| Форматтеры даты/времени | `lib/general/formatters/date_formatter.dart` | §4 |
| UI-microcopy (включая network/offline) | `lib/general/text_constants.dart` | §5 |
| Фундамент аватаров | `lib/design/theme/nox_brand.dart` (generated) | §6 |
| Канон system-overlay | `lib/design/app_overlay_style_tokens.dart` + применение в `AppRoot` | §7 |

**Вне объёма этого контракта** (по spec.md «Вне объёма»): сами виджеты, использующие эти фундаменты (avatar-виджет, file-chip, иллюстрации empty-state, error-screen, оболочка/страницы), реальные графические ассеты (лого-SVG, 3 иллюстрации, app icon — внешние поставки) и автоматизированный DTCG→Dart-генератор. Здесь — только реестр/плумбинг + детерминированная логика + Material-fallback.

---

## 1. Реестр иконок `NoxIcons` + file-type → `IconData`

### 1.1. Набор и пакет

Авторитетный набор — **Material Symbols Rounded** (weight 400, optical 24, grade 0), как зафиксировано в `design-system.md` §8 и в icon-map (`docs/design/system/nox-handoff/spec/icons.md`). Во Flutter он подключается пакетом **`material_symbols_icons`** (`Symbols.*`), а не стоковым `Icons.*`.

- В `pubspec.yaml::dependencies` MUST быть добавлен `material_symbols_icons` (текущий стабильный pin фиксируется в `01-stack-and-tooling.md` в том же change-set).
- Иконки именуются по **базовым лигатурам** (`Symbols.forum`, `Symbols.settings`, …); outlined↔filled — это **ось `FILL`** (`Icon(Symbols.forum, fill: 0|1)`), а **не** суффикс имени `*_outlined`. Это load-bearing-уточнение из `nox-handoff-2/spec/icons.md`, которое MUST быть перенесено в авторитетный `nox-handoff/spec/icons.md` (FR-020): таблица навигации авторитетного icons.md сейчас даёт `forum`/`forum_outlined` (стиль стоковых `Icons.*`), а правильная для `material_symbols_icons` форма — одна лигатура `forum` + ось `FILL 0/1`.
- Оси `weight 400` / `grade 0` / `opticalSize 24` — дефолты набора; индивидуальная иконка может переопределить `fill`/`weight`/`grade`/`opticalSize` по месту, когда дизайн экрана этого требует (например, selected-таб = `FILL 1`).

### 1.2. Реестр имён `NoxIcons`

`NoxIcons` — единый `abstract final class` с приватным `const`-конструктором, экспонирующий **семантические** алиасы поверх `Symbols.*`, чтобы код фич/виджетов ссылался на роль, а не на сырую лигатуру. Группы (по `design-system.md` §8 / icon-map):

| Группа | Роли (примеры) | Лигатура |
|---|---|---|
| Навигация | `chats`, `settings`, `add` (центр) | `forum`, `settings`, `add` |
| Действия | `back`, `paste`, `scanQr`, `attach`, `send`, `flashlightOn`/`flashlightOff`, `switchCamera`, `search`, `show`/`hide`, `copy`, `showQr`, `download`, `edit`, `removeAttachment` | `arrow_back`, `content_paste`, `qr_code_scanner`, `attach_file`, `send`, `flashlight_on`/`flashlight_off`, `cameraswitch`, `search`, `visibility`/`visibility_off`, `content_copy`, `qr_code`, `download`, `edit`, `close` |
| Статусы сообщений | `statusPending`, `statusSent`, `statusError` | `schedule`, `check`, `error` |
| Универсальные | `errorGeneral` (экран 3.1), `avatarFallback` (`forum`-glyph) | `error`, `forum` |
| Empty-state fallback | `emptyChats`, `emptyMessages`, `emptyFiles` | `forum`, `chat_bubble`, `folder_open` |

Правила реестра:

- Тип значений — `IconData` (т.е. `static const IconData chats = Symbols.forum;`). FILL/weight/grade задаются на месте отрисовки (`Icon(... , fill: 1)`), не в реестре (реестр — только маппинг роль→глиф).
- Реестр **исчерпывающе покрывает** таблицы навигации/действий/статусов/empty-state из `design-system.md` §8 + icon-map; новый экранный глиф добавляется как именованная роль, а не сырым `Symbols.*` в коде фичи.
- Имена-роли — на английском (язык кода), сгруппированы комментариями по секциям icon-map.

### 1.3. Карта «тип файла → `IconData`» с дефолтом

`design-system.md` §8 и `overview.md` («Файлы: иконки типов») фиксируют единую таблицу типов файлов; контракт реализует её как детерминированную функцию-классификатор + карту.

- Категории типов (canonical enum / набор ключей): `image`, `video`, `audio`, `pdf`, `document` (doc/docx/odt), `spreadsheet` (xls/csv), `text`, `archive` (zip/rar/7z), `other`.
- Карта `Map<NoxFileType, IconData>` (или эквивалент) → лигатуры: `image`, `videocam`, `audiotrack`, `picture_as_pdf`, `description`, `table_chart`, `article`, `folder_zip`, `insert_drive_file`.
- **Дефолт для неизвестного типа — `insert_drive_file`** (категория `other`). «Неизвестный тип» = расширение/MIME, не попавшее ни в одну распознанную категорию; функция-классификатор НИКОГДА не бросает — на любом входе возвращает иконку (минимум — дефолт).
- Классификация ведётся по расширению/MIME детерминированно; одна точка истины (`NoxFileType` + резолвер + карта), без дублирующих маппингов в коде фич.

---

## 2. Стратегия шрифтов — native Sans + bundled Mono

`design-system.md` §3 задаёт два семейства: **Sans** — системное (Roboto на Android, SF Pro на iOS) и **Mono** — `Roboto Mono` (для отображения `Your ID` в 7.1, метрики Body Large 16/24). Текущий generated `noxTextTheme` хардкодит `fontFamily: 'Roboto'` для всех слотов, что на Windows/Linux молча падает на системный шрифт и ломает типошкалу. Контракт фиксирует детерминированную, кросс-платформенную стратегию.

### 2.1. Sans — платформенно-нативный (НЕ хардкод `Roboto`)

- Sans-слот MUST разрешаться в **платформенно-нативный** sans (Roboto / SF / системный по ОС), а не в зашитую строку `'Roboto'`. Способ — `TextStyle.fontFamily == null` (Flutter берёт платформенный дефолт) для Sans-слотов `noxTextTheme`; явная строка семейства недопустима для Sans.
- Это устраняет молчаливый fallback на Windows/Linux (там нет `Roboto` среди bundled-семейств): нативный sans целевой ОС применяется детерминированно.
- `design-system.md` §3 — источник истины для этого решения; generated `nox_text_theme.dart` регенерируется так, чтобы Sans-слоты не несли литерал `'Roboto'` (правило «руками не править, регенерировать» — см. контракт `theme.md` / блюпринт `06` §1).

### 2.2. Mono — bundled `Roboto Mono`

- Mono-семейство `Roboto Mono` MUST **бандлиться** (детерминированный вид `Your ID` на всех пяти платформах), а не полагаться на платформенный mono:
  - файлы шрифта кладутся в `assets/fonts/` (минимум Regular; при необходимости — Medium);
  - в `pubspec.yaml::flutter.fonts` объявляется `family: Roboto Mono` с `asset:`-путями;
  - имя семейства экспонируется как `noxMonoFamily = 'Roboto Mono'` (из generated `nox_text_theme.dart`) и потребляется для mono-мест (`fontFamily: noxMonoFamily`).
- `flutter_gen::fonts.enabled` остаётся `false` (имена семейств берутся из generated-темы / `noxMonoFamily`, не из flutter_gen-генерации шрифтов).

### 2.3. Wordmark «NOX»

- Стиль wordmark (`Title Large` / Bold 700 / letter-spacing +0.12em, `design-system.md` §1/§3) — токен типографики дизайн-слоя (формально это часть type-scale-контракта `theme.md`, здесь фиксируется как зависимость): семейство wordmark — тот же native Sans (НЕ хардкод), вес/трекинг — фиксированные.

### 2.4. Граница (edge case)

- При недоступности заявленного семейства поведение MUST быть **детерминированным**: Sans — намеренно платформенный (то есть «native» и есть результат), Mono — гарантирован бандлингом. Молчаливая подмена, ломающая метрики типошкалы, недопустима (Success-критерий SC-005).

---

## 3. Реестр ассетов — `flutter_gen` (канонический), Material-fallback

`design-system.md` §10/§11 перечисляет графические слоты: финальный лого-SVG, 3 empty-state-иллюстрации (chats / messages / files), app icon. Реальные файлы — **внешние поставки** и ещё не доставлены; в объёме — только реестр/плумбинг + fallback.

### 3.1. Один канонический канал — `flutter_gen`

- Канонический канал доступа к путям ассетов — **`flutter_gen`** (`lib/design/gen/assets.gen.dart`, type-safe `Assets.png`/`Assets.svg`/`Assets.animation`); он подключён в `pubspec.yaml::flutter_gen` и прогоняется в CI (`build_runner`).
- Рукописный `AppImagesTokens` (`lib/design/app_images_tokens.dart`) — **дубль**, который MUST быть сведён к одному каналу (FR-018): `AppImagesTokens` сворачивается в пользу `Assets.*`. После сведения остаётся ровно один канал ассетов (Success-критерий SC-006).
- Директории ассетов перечисляются в `pubspec.yaml::flutter.assets` (`assets/`, `assets/png/`, `assets/svg/`, `assets/animation/`) — это бандлит файлы в APK/IPA и нужно `flutter_gen`. `assets/fonts/` (§2.2) добавляется в `flutter.fonts`, а не в `flutter.assets`.
- `assets.gen.dart` — gitignored, исключён из анализатора, регенерится `build_runner` (правится не он, а содержимое `assets/` + конфиг `flutter_gen` в pubspec).

### 3.2. Material-icon fallback для непоставленных ассетов

- Пока реальный файл (лого-SVG, иллюстрация) не поставлен, реестр/потребитель MUST **деградировать к Material-иконке-fallback**, не падая (edge case spec.md):
  - 5.1 «нет чатов» → `NoxIcons.emptyChats` (`forum`, FILL 0);
  - 5.2 «нет сообщений» → `NoxIcons.emptyMessages` (`chat_bubble`, FILL 0);
  - 5.4 «нет файлов» → `NoxIcons.emptyFiles` (`folder_open`);
  - цвет fallback-глифа — `colorScheme.onSurfaceVariant` (`design-system.md` §10).
- Контракт фиксирует **карту слот→fallback**; сами виджеты иллюстраций — вне объёма (их строит фича, потребляя эту карту). Реальные SVG подключаются по мере поставки без изменения публичного контракта потребителя.

---

## 4. Форматтеры даты/времени — `DateFormatter` (две лестницы)

`overview.md` («Форматы времени и даты») задаёт две относительные «лестницы», которые `DateFormatter` (`lib/general/formatters/date_formatter.dart`, статическая утилита, приватный ctor, без DI) MUST реализовывать. Текущий скелет несёт только `short`/`time` — он расширяется этими лестницами.

### 4.1. Лестница списка чатов (5.1) — относительный timestamp

Вход — `DateTime`, выход — короткая относительная строка (English microcopy):

| Условие (относительно «сейчас») | Формат | Пример |
|---|---|---|
| < 1 мин | `now` | `now` |
| < 1 ч | `<N> min` | `5 min` |
| сегодня (≥ 1 ч) | `<N> h` | `2 h` |
| вчера | `Yesterday` | `Yesterday` |
| ранее, текущий год | `d MMM` | `12 May` |
| прошлый год и старше | `d MMM yyyy` | `12 May 2025` |

### 4.2. Лестница ленты чата (5.2) — date-separator

Разделитель дня в ленте:

| Условие | Формат | Пример |
|---|---|---|
| сегодня | `Today` | `Today` |
| вчера | `Yesterday` | `Yesterday` |
| в пределах текущей недели | день недели | `Tuesday` |
| ранее, текущий год | `d MMM` | `12 May` |
| прошлый год и старше | `d MMM yyyy` | `12 May 2025` |

Время каждого сообщения в ленте — `HH:mm` (существующий `DateFormatter.time`).

### 4.3. Правила

- Лестницы детерминированы и тестопригодны (вход `DateTime` + «now»-якорь → стабильная строка); пороги (`now`/`min`/`h`/`Yesterday`/год) — ровно как в таблицах. SC-007 требует детерминированного воспроизведения.
- Литералы-копирайт (`now`, `min`, `h`, `Yesterday`, `Today`) — English; держатся согласованно с каноном microcopy (§5) либо в `DateFormatter`, либо ссылками на `TextConstants` (единый источник строк; конкретное размещение фиксируется реализацией, без дублирования одной строки в двух местах).
- Локаль-зависимые компоненты (название месяца `MMM`, день недели) идут через `intl` `DateFormat` с дефолт-локалью `Constants.defaultLocale` (приложение: English + Ukrainian; см. §5). Существующие имена методов (`short`/`time`) не переименовываются — новые лестницы добавляются как отдельные методы (например, `relativeListStamp(...)` / `daySeparator(...)`).

---

## 5. UI-microcopy — `TextConstants` (+ network/offline)

Вся пользовательская копи — в одном `abstract final class TextConstants` (`lib/general/text_constants.dart`, English, ARB-ready); строковых литералов копи в коде фич/виджетов нет (блюпринт `06` §8.3.0). Контракт **добавляет** сетевые/offline-строки к существующему набору (`appName`/`chats`/`settings`/`errorGeneralTitle`/`actionTryAgain`/`noData`/`comingSoon`).

### 5.1. Сетевой копирайт (`overview.md` «Сетевые ошибки», «Offline»)

- Канонический паттерн сетевой ошибки — `Could not <verb>. Check your connection and try again.` Слово — **`connection`**, не `internet`.
- **Исключение для 5.1 (список чатов):** `Could not load chats. Pull to refresh.` (привязано к pull-to-refresh, `FeatureFlags.enablePullToRefresh`).
- Постоянный offline-баннер: `No connection` (текст `MaterialBanner`, вешается сверху 5.1/5.2 на время offline).

Добавляемые строки (имена — иллюстративные; English values — фиксированы дизайн-корпусом):

| Роль | Значение |
|---|---|
| `offlineBanner` | `No connection` |
| `errorLoadChatsPullToRefresh` | `Could not load chats. Pull to refresh.` |
| `errorNetworkGenericTemplate` | `Could not <verb>. Check your connection and try again.` (шаблон; `<verb>` подставляется на месте — допускается параметризованный геттер) |

### 5.2. Правила

- UI-строки — **English** даже в этом русскоязычном артефакте (языки приложения — English + Ukrainian; русский UI-языком не бывает — языковая дисциплина NOX).
- Класс остаётся migration-ready под ARB + `flutter_localizations` (отдельная i18n-фича); никаких литералов копи вне `TextConstants` (FR-013, FR-022).
- Date-микрокопи (§4: `now`/`Yesterday`/`Today`/…) — часть того же канона строк; единый источник, без дублей.

---

## 6. Фундамент генерируемых аватаров

Аватар чата генерируется детерминированно из имени (`design-system.md` §2.5, `overview.md` «Generated avatar»). Фундамент — **данные + чистая логика** (`lib/design/theme/nox_brand.dart`, generated из `tokens/avatars.tokens.json`); сам avatar-**виджет** — вне объёма.

Контракт фундамента (уже реализован в generated `nox_brand.dart`; контракт его фиксирует и верифицирует):

- **Палитра** `noxAvatarPalette` — ровно **8** контраст-выверенных фонов (`#0E7C7C`, `#8A6A00`, `#AD4A15`, `#5C7300`, `#2E6FB0`, `#C0392B`, `#7A4DB3`, `#1E7268`); инициалы всегда **белые** `#FFFFFF`. Все 8 фонов дают контраст с белым ≥ 4.5:1 (WCAG AA, §2.5) — инвариант, проверяемый автотестом контраста (FR-024).
- **Хеш-индекс** `noxAvatarIndex(name)` — детерминированный: `h = (h * 31 + charCode) & 0xFFFFFFFF` по code units имени, индекс `= h % 8`. Точно зеркалит канонический `src/tokens.jsx` (правило «руками не править, регенерировать»).
- `noxAvatarColor(name)` = `noxAvatarPalette[noxAvatarIndex(name)]`.
- **Инициалы** `noxInitials(name)` — 1–2 символа: первые буквы первых двух слов, иначе первые 1–2 буквенно-цифровых; **`null`** при отсутствии валидных инициалов (эмодзи/символы/пусто — charset имени чата не ограничен).
- **`forum`-fallback:** когда `noxInitials` вернул `null`, потребитель (avatar-виджет, вне объёма) рисует glyph `NoxIcons.avatarFallback` (`forum`) белым на том же hash-фоне.
- Детерминизм (индекс/цвет/инициалы) воспроизводим тестами (SC-007, US3 Acceptance #4).

---

## 7. Канон применения system-overlay

`AppOverlayStyleTokens` (`lib/design/app_overlay_style_tokens.dart`) — `static const SystemUiOverlayStyle light`/`dark`, **только** поля статус-бара (`statusBarColor`/`statusBarIconBrightness`/`statusBarBrightness`); поля Android-навбара опущены (блюпринт `06` §6). Контракт фиксирует **единый канон применения** (FR-016).

- **Глобально, по `Brightness`:** overlay-стиль ставится в **`AppRoot`** (корневой `MaterialApp`, см. блюпринт `05` §6.2 / `06` §6.1) — единственное место по умолчанию: при сборке дерева выбирается `AppOverlayStyleTokens.dark`/`light` по текущей яркости (`MediaQuery.platformBrightnessOf(context)` либо производный от `themeMode` `Brightness`) и применяется через `SystemChrome.setSystemUIOverlayStyle(...)`. Статус-бар согласован с активной темой на всех экранах без дублирования.
- **`AnnotatedRegion<SystemUiOverlayStyle>` — задокументированное исключение, не правило:** допустимо только когда экран осознанно переопределяет яркость относительно темы (например, splash на фиксированном `NoxBrand.canvasDark` независимо от light-темы). Вне таких случаев overlay в коде фич не задаётся.
- Сырой `SystemUiOverlayStyle(...)` в коде фич запрещён — только токены `AppOverlayStyleTokens.*` (FR-022, блюпринт `06` §9). `const Color`-литералы легитимны только внутри файла токенов overlay.
- Применение overlay — часть глобального плумбинга этой фичи (overlay «применяется глобально», spec.md «Решения»), даже несмотря на то, что сам `AppRoot`-виджет уже существует: контракт фиксирует, что канон применения задан и единственен.

---

## 8. Источник истины и гигиена (в части этих фундаментов)

- **Один канал на роль:** ассеты — только `flutter_gen` (`AppImagesTokens` свёрнут, §3.1); строки — только `TextConstants` (§5); иконки — только `NoxIcons`/file-type-map (§1); даты — только `DateFormatter`-лестницы (§4). Двух параллельных классов на одну роль не остаётся (SC-006).
- **Регенерация, не ручная правка:** `nox_brand.dart` (аватары, §6) и `nox_text_theme.dart` (семейства, §2) — generated из `nox-handoff/tokens`; правятся токены, не Dart (блюпринт `06` §1; правило «руками не править, регенерировать»).
- **Перенос из `nox-handoff-2`:** FILL-axis-уточнение icon-map (§1.1) MUST быть перенесено в авторитетный `nox-handoff/spec/icons.md` до удаления дубликата (FR-020); само удаление `nox-handoff-2/` — отдельный change-set.
- **Docs-in-sync:** если блюпринт `06`/`10` расходится с реализованным фундаментом (например, native-Sans-стратегия §2 против хардкода `'Roboto'`, или подключение `material_symbols_icons` §1), блюпринт приводится в корректный вид в том же change-set (FR-021).

---

## Чеклист

- [ ] `pubspec.yaml::dependencies` содержит `material_symbols_icons` (pin в `01-stack-and-tooling.md`); иконки именуются базовыми лигатурами + ось `FILL` (не суффикс `*_outlined`).
- [ ] `NoxIcons` (`lib/design/nox_icons.dart`) — `abstract final class`, приватный ctor; покрывает навигацию/действия/статусы/универсальные/empty-state из `design-system.md` §8; значения — `IconData` (`Symbols.*`).
- [ ] File-type → `IconData` карта + резолвер (`NoxFileType`) покрывает image/video/audio/pdf/document/spreadsheet/text/archive; **дефолт `insert_drive_file`** для неизвестного; функция не бросает.
- [ ] Sans-слоты `noxTextTheme` НЕ хардкодят `'Roboto'` (native-резолв `fontFamily: null`); Mono `Roboto Mono` бандлится (`assets/fonts/` + `pubspec.yaml::flutter.fonts`, `noxMonoFamily`); `flutter_gen::fonts.enabled = false`.
- [ ] Wordmark-стиль (Title Large / 700 / +0.12em) — native Sans, не хардкод семейства.
- [ ] Ассеты: единственный канал — `flutter_gen` (`Assets.*`); `AppImagesTokens` свёрнут (FR-018); директории в `pubspec.yaml::flutter.assets`; `assets/fonts/` — в `flutter.fonts`.
- [ ] Material-icon fallback для непоставленных ассетов (5.1→`forum`, 5.2→`chat_bubble`, 5.4→`folder_open`, цвет `onSurfaceVariant`) — карта слот→fallback задана, не падает.
- [ ] `DateFormatter` реализует обе лестницы: список чатов (`now`/`N min`/`N h`/`Yesterday`/`d MMM`/`d MMM yyyy`) и date-separator (`Today`/`Yesterday`/день недели/`d MMM`/`d MMM yyyy`); `time` = `HH:mm`; детерминизм тестопригоден; `short`/`time` не переименованы.
- [ ] `TextConstants` дополнен network/offline-строками (`No connection`; `Could not load chats. Pull to refresh.`; шаблон `Could not <verb>. Check your connection and try again.` со словом `connection`); все строки English; нет литералов копи в коде фич.
- [ ] Фундамент аватаров (`nox_brand.dart`, generated): палитра из 8 (контраст ≥ 4.5:1 к белому), `noxAvatarIndex` `h*31+charCode & 0xFFFFFFFF % 8`, `noxAvatarColor`, `noxInitials` (1–2, `null`→`forum`-fallback); детерминизм покрыт тестами.
- [ ] System-overlay: применяется глобально в `AppRoot` по `Brightness` (`SystemChrome.setSystemUIOverlayStyle`), `AnnotatedRegion` — документированное исключение; сырой `SystemUiOverlayStyle` в коде фич запрещён.
- [ ] FILL-axis icon-map перенесён в `nox-handoff/spec/icons.md` (FR-020); блюпринт `06`/`10` приведён в соответствие (native Sans, `material_symbols_icons`) — docs-in-sync (FR-021).
- [ ] Один канонический канал на каждую роль (иконки/ассеты/строки/даты); generated-фундаменты не правятся руками — регенерируются из токенов.
