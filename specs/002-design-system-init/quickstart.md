# Быстрый старт: проверка дизайн-системы NOX (Feature-002)

**Branch**: `002-design-system-init` | **Phase**: 1 | **Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

**Назначение.** Runnable-руководство, доказывающее, что дизайн-система NOX работает end-to-end на чистом клоне: окружение поднимается, тема собирается в light и dark и переключается, `ColorScheme`-роли полны и совпадают с токенами `nox-handoff` (нулевой дрейф), типошкала рендерится платформенно-нативным sans + бандленным `Roboto Mono` на всех пяти таргетах, иконки приходят через `material_symbols_icons`, карта «тип файла → иконка» / лестницы дат / детерминизм аватаров покрыты тестами, тесты контраста проходят, хардкод-стилей нет, spacing- и asset-каналы сведены к одному каноническому, а code-gate зелёный. Это **гайд проверки**, не имплементация: тел кода здесь нет — формы артефактов живут в [`data-model.md`](data-model.md) и [`contracts/`](contracts/), а «как» — в блюпринте [`docs/blueprints/mobile/06-theming.md`](../../docs/blueprints/mobile/06-theming.md) (+ [`01`](../../docs/blueprints/mobile/01-stack-and-tooling.md), [`10`](../../docs/blueprints/mobile/10-code-templates.md)).

**Границы.** Фича — **всё, кроме виджетов** (spec.md «Вне объёма»): реализаций компонентов §9 (bubble, list item, identity card, поля/кнопки, file-chip, composer, QR-оверлеи, snackbar/banner/dialog/appbar/error-screen, аватар-виджет, виджеты иллюстраций) и любых `lib/presentation/**`-виджетов здесь нет. Проверяется **фундамент**: примитивы темы, component-сабтемы уровня `ThemeData`, шрифты/иконки/форматтеры/microcopy/аватар-логика/реестр ассетов/overlay-канон. Реальные графические ассеты (лого-SVG, 3 иллюстрации empty-state, иконка приложения) — внешние поставки; в объёме только плумбинг + Material-fallback (проверяется деградация, не сами файлы).

**Источник истины.** Дизайн-значения происходят из `docs/design/system/nox-handoff/tokens/*.tokens.json` (W3C DTCG) → сгенерированный Dart `nox-handoff/flutter/nox_*.dart`, принятый как практический источник и скопированный в `lib/design/theme/nox_*.dart`. Правило: **руками не править, регенерировать** (правьте `tokens/*.tokens.json`, не Dart). При расхождении прозы `design-system.md` с токенами истиной считаются **токены** (`nox-handoff`); каталог-дубликат `nox-handoff-2/` авторитетным не считается.

**Терминология приёмки:**
- **token-parity** — значение в коде дизайн-слоя (`lib/design/theme/nox_*.dart`, `AppColors`, токен-классы) **побайтно равно** соответствующему `nox-handoff/tokens/*.tokens.json`; нулевой дрейф.
- **role-complete** — у `noxLightScheme` и `noxDarkScheme` задана **каждая** M3-роль `ColorScheme` (ни одна не `null`/не дефолтная), и `AppColors`-extension доступен в обеих темах.
- **single-channel** — для каждой дизайн-роли (spacing, ассеты) остаётся **ровно один** канонический канал, без двух параллельных классов.

Каждый сценарий ниже — **команда + ожидаемый результат**. Все вызовы Flutter/Dart идут через `fvm` (Flutter `3.44.1`); голые `flutter`/`dart` не используются.

---

## 1. Предварительные требования (окружение)

**Цель:** воспроизводимое окружение у любого члена команды; дизайн-слой собирается и тестируется на чистом клоне без правок структуры (каркас уже стоит из Feature-001).

### 1.1 FVM — пин Flutter SDK

```bash
brew install fvm     # macOS; для других платформ см. https://fvm.app
fvm install          # читает .fvmrc, ставит Flutter 3.44.1 в .fvm-кэш
fvm flutter --version
```

**Ожидаемо:** `fvm install` ставит Flutter `3.44.1` без интерактива; `fvm flutter --version` печатает `Flutter 3.44.1` и `Dart 3.x` (≥ `3.12.0`). `.fvmrc` (`{"flutter": "3.44.1"}`) — закоммичен; `.fvm/flutter_sdk` — в `.gitignore`.

### 1.2 Зависимости и codegen

```bash
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
```

**Ожидаемо:**
- `pub get` резолвит манифест без конфликтов. Новые зависимости дизайн-системы присутствуют в `pubspec.yaml`: `material_symbols_icons` (иконочный набор Material Symbols Rounded, оси FILL/weight/grade — FR-011) добавлен; `intl` (форматтеры) и `flutter_screenutil` уже на месте из Feature-001.
- `build_runner` завершается кодом 0. `flutter_gen` регенерирует `lib/design/gen/assets.gen.dart` (gitignored, исключён из анализатора) из реальных директорий `assets/`. Сгенерированный Dart токенов (`lib/design/theme/nox_*.dart`) — **копия** `nox-handoff/flutter`, его `build_runner` не трогает: это git-tracked копия, регенерируемая из токенов, а не из `build_runner`.

### 1.3 Платформенные toolchain'ы (по таргету, который проверяете)

| Таргет | Что должно стоять |
|---|---|
| iOS | Xcode + симулятор/устройство |
| Android | Android SDK + эмулятор/устройство |
| macOS | Xcode (нативный сборщик desktop) |
| Windows | Visual Studio (C++ desktop workload) |
| Linux | `ninja-build`, `libgtk-3-dev` (GTK3-embedder) |

```bash
fvm flutter doctor
```

**Ожидаемо:** `flutter doctor` зелёный для тех таргетов, что собираете. Типошкала проверяется на всех пяти таргетах (§4), потому что font-fallback расходится именно между ОС.

---

## 2. Артефакты дизайн-слоя (указатель на data-model / contracts)

**Цель:** все non-widget-фундаменты присутствуют и имеют форму, заданную авторитетом. Здесь — только указатель: точные формы классов/токенов/реестров — в [`data-model.md`](data-model.md) и [`contracts/`](contracts/), значения — в `nox-handoff/tokens`, «как собирается» — в блюпринте `06`. **Не инлайнить код** — брать verbatim из этих источников.

Карта артефактов (что проверяется в §3–§9):

| Артефакт | Где живёт | Источник формы / значений |
|---|---|---|
| `ColorScheme` light/dark (полный M3-набор) | `lib/design/theme/nox_color_scheme.dart` | `tokens/color.{light,dark}.tokens.json` |
| Типошкала (M3-слоты, Sans + Mono, wordmark) | `lib/design/theme/nox_text_theme.dart` | `tokens/typography.tokens.json`, `design-system.md` §3 |
| Токены формы/высоты/отступов/движения | `lib/design/theme/nox_tokens.dart` | `tokens/{shape,elevation,spacing,motion}.tokens.json` |
| Бренд-палитра + фикс-исключения + аватар-логика | `lib/design/theme/nox_brand.dart` | `tokens/{brand,avatars}.tokens.json` |
| `AppColors` (семантические доп-роли, полный набор) | `lib/design/theme/app_colors.dart` | `nox-handoff`-токены (US4) |
| Сборка темы + component-сабтемы | `lib/design/theme/app_theme.dart` | `design-system.md` §9 (component-токены) |
| Реестр иконок + карта «тип файла → иконка» | `lib/design/` (`NoxIcons`, file-type map) | `design-system.md` §8, `overview.md` «Файлы» |
| Отзывчивые spacing-токены (единый канал) | `lib/design/app_spacing_tokens.dart` | блюпринт `06` §4 / §4.1 |
| Канал ассетов (единый — `flutter_gen`) | `lib/design/gen/assets.gen.dart` | блюпринт `06` §7 |
| Overlay-канон (status-bar по brightness) | `lib/design/app_overlay_style_tokens.dart` + `AppRoot` | блюпринт `06` §6 / §6.1 |
| Форматтеры дат (две NOX-лестницы) | `lib/general/formatters/date_formatter.dart` | `overview.md`/`design-system.md` |
| UI-microcopy (вкл. сетевые/offline) | `lib/general/text_constants.dart` | `overview.md` «Сетевые ошибки» |

> **Бренд-фиксированные исключения** (`design-system.md` §1/§9.9/§9.10): splash-фон **всегда тёмный** (`NoxBrand.canvasDark`), QR-поверхность **всегда светлая** (`NoxBrand.qrSurface`/`qrInk`), маска/визирь QR-сканера — именованные токены вне `ColorScheme`. Они не зависят от `themeMode` и проверяются отдельно (§3).

---

## 3. Сборка темы — light + dark, роли, паритет токенов (US1 / US2 / SC-002 / SC-003)

**Цель:** обе темы собираются, переключаются, role-complete, и каждое значение token-parity. Это минимально жизнеспособный дизайн-слой.

### 3.1 Обе темы собираются и несут полный набор ролей

```bash
fvm flutter test test/design/theme/app_theme_test.dart
```

**Ожидаемо (role-complete):** тест строит `AppTheme.light()` и `AppTheme.dark()`, обе возвращают `ThemeData` без исключений; `theme.colorScheme` — это `noxLightScheme`/`noxDarkScheme` (НЕ `ColorScheme.fromSeed`), и **каждая** M3-роль задана явно (`primary`/`onPrimary`/`primaryContainer`/`secondary*`/`tertiary*`/`error*`/`surface*`/`surfaceContainer*`/`outline`/`outlineVariant`/`inverse*`/`scrim`/`shadow` и т.д.). `theme.extension<AppColors>()` возвращает не-`null` в обеих темах (намеренный `!` в `context.appColors` не должен падать ни в одном режиме).

### 3.2 Переключение light↔dark не теряет роли

```bash
# При запущенном app shell (см. §4 quickstart Feature-001) сменить системную тему:
#   macOS:   System Settings → Appearance → Light / Dark
#   iOS:     Settings → Display & Brightness → Light / Dark
#   Android: Settings → Display → Dark theme
```

**Ожидаемо:** app shell мгновенно переключается (`themeMode: ThemeMode.system`, `MaterialApp` читает `state.themeMode` из `AppRootBloc`); ни одна роль не «теряется» и не сбрасывается на дефолт M3. Бренд-фиксированные исключения сохраняются вне зависимости от темы: splash-фон остаётся тёмным, QR-поверхность — светлой.

### 3.3 Нулевой дрейф токенов (token-parity)

```bash
fvm flutter test test/design/theme/token_parity_test.dart
```

**Ожидаемо (SC-003):** тест сверяет значения дизайн-слоя (`nox_color_scheme.dart`, `nox_tokens.dart`, `nox_brand.dart`, типошкала) с `nox-handoff/tokens/*.tokens.json` — **ноль расхождений**. Сюда входит ранее выявленный кейс dark `outlineVariant`: код обязан быть равен значению токена `color.dark.tokens.json` (а не устаревшей прозе `design-system.md` §2.3) — токены арбитр (FR-017, Edge Case «расхождение прозы и токенов»). Если токен и проза расходятся, тест следует токену; рассинхрон прозы фиксируется в том же change-set (docs-in-sync, FR-021).

> **Правило регенерации.** `lib/design/theme/nox_*.dart` — копии `nox-handoff/flutter`, **руками не правятся**. Любая правка цвета/радиуса/высоты/отступа/длительности идёт в `tokens/*.tokens.json` → регенерация. Это зафиксировано в блюпринте `06` (§1/§4.1) и проверяется ревью, а token-parity-тест ловит ручной дрейф.

### 3.4 Component-сабтемы — стоковые M3-компоненты в NOX-стиле (US2 / FR-008)

```bash
fvm flutter test test/design/theme/component_subthemes_test.dart
```

**Ожидаемо:** `ThemeData` несёт сконфигурированные из токенов и component-токенов (`design-system.md` §9) сабтемы (`CardTheme`, `FilledButtonTheme`, `AppBarTheme`, `SnackBarTheme`, `DialogTheme`, `NavigationBarTheme`/`NavigationRailTheme`, `SegmentedButtonTheme` и т.д.). Тест проверяет, что стоковый M3-компонент под темой получает NOX-радиусы (`NoxRadius`), высоты (`NoxElevation`) и роли (`ColorScheme`) **без локальной стилизации** — стиль приходит из темы. Это переопределяет дефолт блюпринта `06` §3 («сабтемы с первой фичей-виджетом»); блюпринт `06` обновлён в этом change-set (SC-009). Сами виджеты не пишутся (FR-023) — проверка идёт на стоковых компонентах.

> **Бренд-фиксированные component-токены** (§9.9 маска/визирь QR-сканера, §9.10 QR-поверхность), не сводящиеся к ролям `ColorScheme`, доступны как именованные токены дизайн-слоя (FR-009) — проверяется их наличие, не виджет.

---

## 4. Типографика — нативный Sans + бандленный Mono на пяти таргетах (US3 / SC-005 / SC-010)

**Цель:** типошкала рендерится с заявленными семействами на всех пяти платформах — без молчаливого системного fallback, который ломает шкалу на Windows/Linux.

### 4.1 Стратегия шрифтов задана корректно

```bash
fvm flutter test test/design/theme/typography_test.dart
```

**Ожидаемо (FR-010 / FR-002):**
- **Sans — платформенно-нативный** (Roboto/SF по ОС, `design-system.md` §3): `noxTextTheme` НЕ хардкодит `fontFamily: 'Roboto'` (это и есть исправляемый дрейф — на Windows/Linux 'Roboto' молча падает на системный шрифт). Sans-слот наследует платформенный дефолт, не именованное семейство.
- **Mono — `Roboto Mono`, бандленный**: семейство объявлено в `pubspec.yaml` (`fonts:` → `family: Roboto Mono`, файлы под `assets/fonts/`) и используется для mono-слота (отображение `Your ID`, `design-system.md` §9.4). Тест проверяет, что mono-слот ссылается на бандленное семейство (`noxMonoFamily`), а не на платформенный `monospace`.
- M3-слоты типошкалы заданы с метриками из `tokens/typography.tokens.json` (`height = lineHeightPx / fontSize`).

### 4.2 Wordmark «NOX» как токен

**Ожидаемо (FR-005):** стиль wordmark (Title Large / Bold 700 / letter-spacing +0.12em) доступен как токен типографики (а не литерал на месте) — проверяется в том же тесте.

### 4.3 Рендер на всех пяти таргетах (нет молчаливого fallback)

```bash
# launch/compile-verify по таргету (как в quickstart Feature-001 §4):
fvm flutter run   -d macos                   --dart-define-from-file=config/stage.json
fvm flutter run   -d <ios-sim>               --dart-define-from-file=config/stage.json
fvm flutter run   -d <android-emulator>      --dart-define-from-file=config/stage.json
fvm flutter build windows --debug            --dart-define-from-file=config/stage.json
fvm flutter build linux   --debug            --dart-define-from-file=config/stage.json
```

**Ожидаемо (SC-005):** на каждой ОС текст рендерится платформенным sans (Roboto на Android, SF на iOS/macOS, системный sans на Windows/Linux) **без сломанной шкалы**; mono-места (ID) рендерятся бандленным `Roboto Mono` **идентично на всех пяти** (детерминированный вид ID). Бандлинг шрифта — единственная гарантия, что mono-слот не «уплывёт» на десктопе.

---

## 5. Иконки — Material Symbols Rounded + реестр + карта типов файлов (US3 / FR-011 / SC-007)

**Цель:** иконочный набор подключён, реестр имён покрывает нужды дизайна, карта «тип файла → иконка» детерминирована с дефолтом.

### 5.1 Набор и реестр

```bash
fvm flutter test test/design/icons/nox_icons_test.dart
```

**Ожидаемо (FR-011):** пакет `material_symbols_icons` подключён (Material Symbols Rounded, оси FILL/weight/grade — `design-system.md` §8 + `icons.md` из `nox-handoff-2`, перенесённый в авторитетный handoff, FR-020). Реестр `NoxIcons` несёт навигацию (`forum`/`forum_outlined`, `settings`/`settings_outlined`, `add`), действия (`arrow_back`, `content_paste`, `qr_code_scanner`, `attach_file`, `send`, `search`, `content_copy`, `qr_code`, `download`, `edit`, `close`, …) и статусы сообщений (`schedule`/`check`/`error_outline`).

### 5.2 Карта «тип файла → иконка» с дефолтом

```bash
fvm flutter test test/design/icons/file_type_icon_map_test.dart
```

**Ожидаемо (FR-011 / SC-007):** карта детерминированно возвращает иконку по типу файла согласно `overview.md` «Файлы»:

| Тип | Иконка |
|---|---|
| Изображение | `image` |
| Видео | `videocam` |
| Аудио | `audiotrack` |
| PDF | `picture_as_pdf` |
| Документ (doc/docx/odt) | `description` |
| Таблица (xls/csv) | `table_chart` |
| Текст | `article` |
| Архив (zip/rar/7z) | `folder_zip` |
| Прочее / неизвестно | `insert_drive_file` (дефолт) |

Для **неизвестного типа** возвращается дефолт `insert_drive_file` (Edge Case «что считается неизвестным типом» — закрыт явным дефолтом, без падения).

---

## 6. Форматтеры дат и аватар-логика — детерминизм (US3 / SC-007 / FR-012 / FR-014)

**Цель:** обе NOX-лестницы дат и генерация аватаров воспроизводят правила дизайн-корпуса детерминированно.

### 6.1 Две лестницы относительного времени

```bash
fvm flutter test test/general/formatters/date_formatter_test.dart
```

**Ожидаемо (FR-012):** форматтеры дают форматы из `overview.md`/`design-system.md`:
- **Список чатов (5.1)** — относительная лестница: `now`, `5 min`, `2 h`, `Yesterday`, `12 May`, `12 May 2025` (для прошлых лет).
- **Лента чата (5.2)** — время сообщения `HH:mm`; date-separator между днями: `Today`, `Yesterday`, день недели (в пределах недели), иначе `12 May` / `12 May 2025`.

Тест подаёт фиксированные `DateTime` (относительно фиксированного `now`) и сверяет строку с лестницей — детерминированно, без зависимости от часов машины.

### 6.2 Детерминизм генерируемых аватаров

```bash
fvm flutter test test/design/theme/nox_brand_avatar_test.dart
```

**Ожидаемо (FR-014 / SC-007):** для строки имени индекс/цвет/инициалы детерминированы и совпадают с правилом `design-system.md` §2.5:
- хеш `h = (h*31 + charCodeAt(i)) >>> 0`, индекс `h % 8` по 8-цветовой палитре `noxAvatarPalette` (значения из `avatars.tokens.json`: `#0E7C7C`, `#8A6A00`, `#AD4A15`, `#5C7300`, `#2E6FB0`, `#C0392B`, `#7A4DB3`, `#1E7268`);
- инициалы — 1–2 символа, всегда белые (`#FFFFFF`);
- **fallback** для имени без корректных инициалов (эмодзи/символы/пусто): `noxInitials` → `null`, caller показывает glyph `forum` белым на том же hash-фоне (Edge Case fallback закрыт).

Тот же ввод → тот же выход на любом прогоне (детерминизм проверяется повторными вызовами).

---

## 7. Доступность — контраст и непрозрачность timestamp (US1 / FR-024 / SC-010)

**Цель:** контраст пар роль/фон `ColorScheme` соответствует WCAG AA; инварианты a11y зафиксированы и покрыты автотестами.

```bash
fvm flutter test test/design/theme/contrast_test.dart
```

**Ожидаемо (FR-024 / SC-010):** автотест считает контраст (WCAG-формула относительной яркости) для целевых пар роль/фон обеих схем и требует:
- **≥ 4.5:1** для body-текста: `onSurface`/`surface`, `onPrimary`/`primary`, `onPrimaryContainer`/`primaryContainer`, `onSecondaryContainer`/`secondaryContainer`, `onError`/`error`, `onSurfaceVariant`/`surface` и т.д. (для light и dark).
- **≥ 3:1** для крупного текста/иконок: иконочные/large-роли (`outline` на `surface`, selected-indicator-пары `NavigationBar`/`NavigationRail` и т.п.).
- **8 аватар-фонов** дают ≥ 4.5:1 с белыми инициалами (`avatars.tokens.json` это декларирует — тест подтверждает).

Инвариант непрозрачности timestamp — **70%** (`design-system.md` §2.6 / §9.2): метаданные bubble (время) рендерятся на `onPrimaryContainer @70%` (своё) / `onSurfaceVariant` (чужое). На этой фиче bubble-виджет вне объёма (FR-023), поэтому инвариант **документирован** как правило дизайн-слоя и проверяется на уровне токена/константы непрозрачности, а не виджета.

---

## 8. Гигиена дизайн-слоя — ноль хардкода, единый канал (US4 / SC-004 / SC-006)

**Цель:** вне токенного/тематического слоя нет хардкод-стилей; для spacing и ассетов остаётся ровно один канонический канал.

### 8.1 Ноль хардкод-стилей (FR-022 / SC-004)

```bash
grep -rnE "Color\(0x|EdgeInsets\.|TextStyle\(|SystemUiOverlayStyle\(|BorderRadius\.(circular|only)\(|Duration\(" lib \
  | grep -vE "lib/design/" \
  | grep -vE "\.(freezed|g|config)\.dart"
```

**Ожидаемо (SC-004):** ноль попаданий вне дизайн-слоя. Сырые `Color`/`EdgeInsets`/`TextStyle`/`SystemUiOverlayStyle`/`BorderRadius`/`Duration`-литералы легитимны **только** внутри `lib/design/**` (сгенерированные `nox_*.dart`, `app_colors.dart`, токен-классы) — всё остальное берёт цвет/отступ/типографику/радиус/длительность/overlay из токенов/темы (`context.appColors`, `Theme.of(context).colorScheme`, `AppSpacingTokens`, `Theme.of(context).textTheme`, `NoxRadius`, `NoxDuration`, `AppOverlayStyleTokens`).

> На этой фиче `lib/presentation/**` несёт только каркас Feature-001 (`AppShell`, placeholder-страницы) — греп уже должен быть чист; команда — регрессионный гейт против будущего хардкода.

### 8.2 Единый канал spacing и ассетов (FR-018 / SC-006)

```bash
# Каналы spacing: должен остаться один канонический для адаптивных отступов в коде фич.
grep -rn "AppSpacingTokens\|NoxSpacing" lib

# Канал ассетов: один канонический (flutter_gen Assets.*), рукописный реестр сведён.
grep -rn "AppImagesTokens\|Assets\." lib | grep -vE "\.gen\.dart"
```

**Ожидаемо (single-channel / SC-006):**
- **Spacing:** для адаптивных отступов в коде фич — один канал `AppSpacingTokens` (responsive `.w/.h`); `NoxSpacing` (фиксированные dp) остаётся только под намеренно не-скейлимые семантические значения (`minTapTarget`/`screenPadding`), а не как параллельный отступной канал. Нет двух классов, конкурирующих за одну роль (блюпринт `06` §4.1 — дубль сведён, блюпринт обновлён).
- **Ассеты:** один канонический канал — `flutter_gen` (`Assets.*`); рукописный `AppImagesTokens` свёрнут (или сведён к плумбингу слотов с Material-fallback). Реестр покрывает слоты дизайн-системы (лого, 3 иллюстрации empty-state) и **деградирует к Material-иконке-fallback**, когда реальный файл ещё не поставлен (FR-015, Edge Case «ассет не поставлен» — не падает; per-screen: 5.1 → `forum_outlined`, 5.2 → `chat_bubble_outline`, 5.4 → `folder_open`).

### 8.3 Типо-обёртки выровнены под M3-шкалу (FR-019)

**Ожидаемо:** `AppTextStyleTokens`-фабрики не рассинхронизированы с `noxTextTheme` по размерам/весам (выровнены под каноническую M3-шкалу) — проверяется в `typography_test.dart` (§4.1). Канонический type scale — `Theme.of(context).textTheme.*`; обёртки — тонкий color-injecting слой поверх него, не альтернативная шкала.

### 8.4 Overlay-канон применяется глобально (FR-016)

**Ожидаемо:** `AppOverlayStyleTokens.{light,dark}` — единственный источник стилей статус-бара; применяются глобально в `AppRoot` по текущему `Brightness` (блюпринт `06` §6.1), per-screen `AnnotatedRegion` — только документированное исключение (splash). Греп §8.1 уже гарантирует отсутствие сырого `SystemUiOverlayStyle(` вне дизайн-слоя.

---

## 9. Code-gate (зелёный gate — SC-008)

**Цель:** на чистом клоне полный gate проходит с нулём ошибок. Порядок: **кодоген (один прогон) → формат изменённых файлов (`-l 140`) → analyze (ноль ошибок) → тесты**.

```bash
# 1. Кодоген — ОДИН прогон по всему lib/
fvm dart run build_runner build --delete-conflicting-outputs

# 2. Формат — ТОЛЬКО изменённые файлы, явные пути, line length 140
fvm dart format -l 140 <изменённые .dart-пути>

# 3. Статический анализ — ноль ошибок
fvm flutter analyze

# 4. Тесты дизайн-слоя + регрессия Feature-001
fvm flutter test
```

**Ожидаемо по шагам (SC-008):**
1. `build_runner` завершается кодом 0, без конфликтов; `assets.gen.dart` регенерирован. Сгенерированный Dart токенов (`nox_*.dart`) — git-tracked копия `nox-handoff/flutter`, форматированию/правке руками не подлежит.
2. Форматирование стабильно при `-l 140`; повторный прогон не даёт диффа. Генерируемые файлы (`*.g.dart`, `*.freezed.dart`, `*.config.dart`, `lib/design/gen/**`, `lib/design/theme/nox_*.dart`) не форматируются вручную.
3. `fvm flutter analyze` — **ноль ошибок** (стоковый `flutter_lints`).
4. `fvm flutter test` — зелёный: тесты дизайн-слоя (тема/паритет/сабтемы/типографика/иконки/file-type-map/даты/аватары/контраст) **плюс** baseline-набор `Item`-harness Feature-001 (не сломан изменениями темы).

> Локальное зеркало CI (тот же порядок, что `ci.yml`): `make generate && make format && make analyze && make test`. `make format` форматирует всё дерево с `--set-exit-if-changed` — это **CI-гейт**, не шаг завершения задачи; в работе форматируйте только изменённые файлы.

---

## 10. Границы фичи — ноль продуктовых виджетов, блюпринт в синхроне (US4 / SC-009)

**Цель:** граница «всё, кроме виджетов» соблюдена; docs-in-sync выполнен.

```bash
# Ни одного нового продуктового виджета в presentation вне каркаса Feature-001:
git diff --stat master -- lib/presentation
```

**Ожидаемо (SC-009 / FR-023):**
- В `lib/presentation/**` нет новых виджетов §9 (bubble, list item, identity card, поля/кнопки, file-chip, composer, QR-оверлеи, snackbar/banner/dialog/appbar/error-screen, аватар-виджет, виджеты иллюстраций). Допустима только verification-проверка (тест/golden) фундаментов, не продуктовые виджеты.
- **Блюпринт `06`/`10` приведён в соответствие** с реализованным дизайн-слоем в этом же change-set (FR-021): дефолт §3 «сабтемы с первой фичей» переопределён на «полная component-темизация в дизайн-слое»; `06` §2 (`AppColors` skeleton → полный набор), §4.1 (spacing-дубль сведён), §7 (asset-канал сведён), §1/§5 (стратегия шрифтов: нативный Sans, бандленный Mono) обновлены.
- Уникальный non-widget-контент из `nox-handoff-2/` (например `icons.md` с FILL-осью) перенесён в авторитетный `nox-handoff/`; удаление дубликата `nox-handoff-2/` может быть отдельным change-set (FR-020).

---

## Итоговый чеклист приёмки (Phase 1)

- [ ] **SC-003:** `fvm install` + `pub get` + один `build_runner` → окружение и codegen подняты на чистом клоне без правок структуры.
- [ ] **SC-002 / FR-006:** `AppTheme.light()`/`dark()` собираются, role-complete, переключаются по `themeMode`; бренд-фиксированные исключения (тёмный splash, светлая QR-поверхность) держатся вне темы.
- [ ] **SC-003 / FR-017:** token-parity — ноль дрейфа между дизайн-слоем и `nox-handoff/tokens` (вкл. dark `outlineVariant`: код = токен); правило «руками не править, регенерировать» зафиксировано.
- [ ] **FR-008 / SC-009:** component-сабтемы `ThemeData` дают стоковым M3-компонентам NOX-стиль без локальной стилизации; бренд-фикс component-токены (QR-маска/поверхность) доступны как именованные токены.
- [ ] **SC-005 / SC-010:** типошкала рендерится платформенно-нативным Sans + бандленным `Roboto Mono` на всех пяти таргетах (нет молчаливого fallback); wordmark — токен.
- [ ] **FR-011 / SC-007:** иконки через `material_symbols_icons` (Rounded, FILL/weight/grade); реестр `NoxIcons` + карта «тип файла → иконка» с дефолтом `insert_drive_file`.
- [ ] **SC-007 / FR-012 / FR-014:** две лестницы дат и генерация аватаров (хеш/индекс/инициалы/`forum`-fallback) детерминированы, покрыты тестами.
- [ ] **SC-010 / FR-024:** автотесты контраста зелёные (≥4.5:1 body, ≥3:1 large/иконки) для пар роль/фон обеих схем; timestamp-непрозрачность 70% задокументирована как инвариант.
- [ ] **SC-004 / FR-022:** ноль хардкод-стилей вне `lib/design/**` (греп чист).
- [ ] **SC-006 / FR-018:** один канонический канал spacing (`AppSpacingTokens`) и один канал ассетов (`flutter_gen`); типо-обёртки выровнены под M3-шкалу; overlay-канон глобален.
- [ ] **SC-008:** code-gate зелёный (кодоген один прогон → формат `-l 140` → analyze ноль ошибок → тесты дизайн-слоя + регрессия Feature-001).
- [ ] **SC-009:** ноль продуктовых виджетов в рамках фичи; блюпринт `06`/`10` приведён в синхрон; уникальный контент `nox-handoff-2/` перенесён.
