# Data Model: Инициализация дизайн-системы в `lib/design` (всё, кроме виджетов)

**Branch**: `002-design-system-init` | **Phase**: 1 (Design) | **Spec**: [spec.md](spec.md)

> **Назначение.** Зафиксировать «модель» дизайн-слоя. У этой инфраструктурной фичи **нет продуктовых данных** — её «сущности» суть **артефакты дизайн-системы** (токен-классы, схемы, тема, реестры, форматтеры, microcopy), а не runtime-объекты. Каждый артефакт описан как «что это / форма (поля) / источник-токен / отношения / валидация-инварианты», с пометкой **статуса** (`EXISTING` — уже в `lib/design`/`lib/general`/`pubspec.yaml` из Feature-001; `EXPAND` — есть, но skeleton → доводится до полноты; `NEW` — заводится в этой фиче). Это структурный инвариант, который сверяется глазами и автотестами против авторитетного дизайн-корпуса и токенов.
>
> **Источник истины «значений»** — `docs/design/system/nox-handoff/tokens/*.tokens.json` (W3C DTCG) → сгенерированный Dart `docs/design/system/nox-handoff/flutter/nox_*.dart`. **Источник истины «как»** — блюпринт `docs/blueprints/mobile/06-theming.md` (+ `01`, `10`). При расхождении прозы `design-system.md` с токенами **истиной считаются токены** (FR-017, spec Edge Cases). `nox-handoff-2/` — дубликат, не авторитетен (перенести только уникальный `spec/icons.md` с FILL-осью).
>
> **Правило регенерации (несущее).** Сгенерированные `lib/design/theme/nox_*.dart` — копии хэндофа; **руками не правятся**, а регенерируются из `tokens/*.tokens.json` (правьте JSON, не Dart). Автоматизированный DTCG→Dart генератор — вне объёма; принимается уже сгенерированный Dart как практический источник (FR-017, Assumptions).

---

## 0. Карта артефактов и статусов

| # | Артефакт (entity) | Файл | Статус | Источник-токен |
|---|---|---|---|---|
| 1 | `ColorScheme` (light/dark) | `lib/design/theme/nox_color_scheme.dart` | EXISTING (verify drift) | `color.{light,dark}.tokens.json` |
| 2 | `AppColors` ThemeExtension | `lib/design/theme/app_colors.dart` | EXPAND (skeleton→full) | `color.{light,dark}.tokens.json` (производные роли) |
| 3 | `TextTheme` + Sans/Mono + wordmark | `lib/design/theme/nox_text_theme.dart` | EXISTING (+ wordmark NEW) | `typography.tokens.json` |
| 4 | `AppTextStyleTokens` (типо-обёртки) | `lib/design/app_text_style_tokens.dart` | EXPAND (align to M3) | производно от `typography.tokens.json` |
| 5 | `NoxSpacing` / `NoxRadius` / `NoxElevation` / `NoxDuration` / `NoxEasing` | `lib/design/theme/nox_tokens.dart` | EXISTING | `{spacing,shape,elevation,motion}.tokens.json` |
| 6 | `AppSpacingTokens` (responsive) | `lib/design/app_spacing_tokens.dart` | EXISTING (canonicalize) | производно от `spacing.tokens.json` |
| 7 | `NoxBrand` + аватар-логика | `lib/design/theme/nox_brand.dart` | EXISTING | `brand.tokens.json`, `avatars.tokens.json` |
| 8 | `AppTheme` + component-сабтемы | `lib/design/theme/app_theme.dart` | EXPAND (primitives→full) | `nox_theme.dart` (handoff) + §9 component-токены |
| 9 | `NoxComponentTokens` (brand-fixed §9) | `lib/design/theme/nox_component_tokens.dart` | NEW | §9.9/§9.10 component-токены |
| 10 | `NoxIcons` реестр + file-type→IconData | `lib/design/nox_icons.dart` | NEW | `design-system.md` §8 / `nox-handoff-2` `icons.md` / `overview.md` |
| 11 | Asset registry (flutter_gen canonical) | `lib/design/gen/assets.gen.dart` (+ `app_images_tokens.dart` → retire) | EXISTING (canonicalize) | `pubspec.yaml::flutter.assets` |
| 12 | `AppOverlayStyleTokens` + глобальное применение | `lib/design/app_overlay_style_tokens.dart` | EXISTING (+ apply canon) | brightness-производно |
| 13 | Шрифты (Sans native + Mono bundle) | `pubspec.yaml::flutter.fonts` + `assets/fonts/` | NEW (bundle) / EXPAND (font policy) | `typography.tokens.json` font.family |
| 14 | `DateFormatter` (лестницы дат/времени) | `lib/general/formatters/date_formatter.dart` | EXPAND (ladders) | `overview.md`/`design-system.md` форматы |
| 15 | `TextConstants` (microcopy additions) | `lib/general/text_constants.dart` | EXPAND (network/offline) | `overview.md` сетевой копирайт |
| 16 | A11y-инварианты + контраст-тесты | `test/design/contrast_test.dart` (+ docs) | NEW | `design-system.md` §2.6 |

> **Каналы цвета (инвариант блюпринта 06 §0).** Цвет приходит **только** двумя каналами: (1) роли M3 — `Theme.of(context).colorScheme.*`; (2) семантические доп-роли — `context.appColors.*`. Brand-fixed цвета (`NoxBrand`, §9.9/§9.10) — третий, узкий случай для поверхностей вне темизации. Сырые `Color`-литералы легитимны **только** в `nox_*.dart`, `app_colors.dart`, `nox_component_tokens.dart` и токен-файлах (`app_overlay_style_tokens.dart`).

---

## 1. `ColorScheme` (light/dark) — функциональная схема

**Файл:** `lib/design/theme/nox_color_scheme.dart` (GENERATED). **Статус:** EXISTING — проверить дрейф.

- **Что это.** Полный явный `const ColorScheme` для light (`noxLightScheme`) и dark (`noxDarkScheme`) — **не** `ColorScheme.fromSeed`. Все M3-роли заданы поимённо из токенов; seed-teal `Color(0xFF12B4B4)` — лишь отправная точка генерации, не рантайм-источник (FR-001; блюпринт 06 §1).
- **Форма (M3 role set, по две схемы).** Каждая роль — `Color`:

  | Группа | Роли |
  |---|---|
  | primary | `primary`, `onPrimary`, `primaryContainer`, `onPrimaryContainer` |
  | secondary | `secondary`, `onSecondary`, `secondaryContainer`, `onSecondaryContainer` |
  | tertiary | `tertiary`, `onTertiary`, `tertiaryContainer`, `onTertiaryContainer` |
  | error | `error`, `onError`, `errorContainer`, `onErrorContainer` |
  | surface | `surface`, `onSurface`, `onSurfaceVariant`, `surfaceTint` |
  | surface tiers | `surfaceContainerLowest`, `surfaceContainerLow`, `surfaceContainer`, `surfaceContainerHigh`, `surfaceContainerHighest` |
  | outline | `outline`, `outlineVariant` |
  | inverse | `inverseSurface`, `onInverseSurface`, `inversePrimary` |
  | misc | `shadow`, `scrim`, `brightness` |
  | deprecated | `surfaceVariant` (`// ignore: deprecated_member_use`; держится под `LinearProgress` track) |

- **Источник-токен.** `color.light.tokens.json` → `noxLightScheme`; `color.dark.tokens.json` → `noxDarkScheme`.
- **Отношения.** Потребляется `AppTheme._build` как `colorScheme:` (§8). Питает component-сабтемы и контраст-тесты (§16). Производные роли для `AppColors` (§2) выводятся из этих же токенов, не дублируют `ColorScheme`.
- **Валидация / инварианты.**
  - **Полнота:** обе схемы задают **все** перечисленные роли — ни одна не `null`/пропущена при переключении `themeMode` (SC-002).
  - **Нулевой дрейф:** каждое значение === соответствующий `$value` в `color.{light,dark}.tokens.json` (FR-017, SC-003).
  - **`outlineVariant` (dark) — трёхсторонний дрейф к разрешению (SC-003).** Текущий код = `#4E5B58`; токен `color.dark.tokens.json` = `#4E5B58` (код **совпадает с токеном**); проза `design-system.md` §2.3 = `#3F4948`. По FR-017 истина — токен, значит код и токен уже согласованы, а устаревшая проза §2.3 правится под токен (docs-in-sync, FR-021). **OPEN:** если владелец хочет фактическое значение `#3F4948` (как в §2.3 и в dark `surfaceVariant`/`onSurfaceVariant`), правится **токен** (`color.dark.tokens.json`), затем регенерируется Dart — но не наоборот (руками Dart не правят).
  - **Prose-vs-token (dark surface tiers).** `design-system.md` §2.3 указывает dark `surfaceContainer*` как `#090F0F/#161D1D/#1A2120/#242B2B/#2F3635`; токен и код = `#0C1312/#1C2423/#222A28/#2C3431/#37403C`. По FR-017 истина — токен (код корректен); §2.3 правится под токен.

---

## 2. `AppColors` (ThemeExtension) — семантические доп-роли

**Файл:** `lib/design/theme/app_colors.dart`. **Статус:** EXPAND — skeleton (2 поля) → полный token-driven набор (US4, FR-007).

- **Что это.** Типизированное mode-зависимое `ThemeExtension<AppColors>` поверх `ColorScheme` для семантических ролей NOX, которых **нет** в стоковом M3. Доступ — `context.appColors.xxx`. Пять частей в одном файле: `@immutable AppColors`, `copyWith`, `lerp` (пролерпить **каждое** поле), `LightAppColors`/`DarkAppColors`, `extension AppColorsExtension on BuildContext` (намеренный `!`).
- **Форма (текущий skeleton).** `surfaceMuted`, `dividerSubtle` (raw-литералы `#F2F2F2`/`#BDBDBD` light, `#2D2D2D`/`#000000` dark — **ad-hoc, не из токенов** → подлежат замене).
- **Форма (полный набор — кандидаты ролей).** Доп-роли выводятся из §9 component-токенов, которые **не сводятся** к одной готовой роли `ColorScheme` или несут модифицированную непрозрачность. Канонический список фиксируется на plan/tasks; кандидаты:

  | Роль (поле) | Назначение (§ design-system) | Источник значения |
  |---|---|---|
  | `bubbleOwnBackground` | фон своего bubble (§9.2) | = `colorScheme.primaryContainer` |
  | `bubbleOwnText` | текст своего bubble (§9.2) | = `colorScheme.onPrimaryContainer` |
  | `bubbleOtherBackground` | фон чужого bubble (§9.2) | = `colorScheme.surfaceContainerHigh` |
  | `bubbleOtherText` | текст чужого bubble (§9.2) | = `colorScheme.onSurface` |
  | `timestampOwn` | время в своём bubble @70% (§9.2, §2.6) | `onPrimaryContainer` @ 0.70 |
  | `timestampOther` | время в чужом bubble (§9.2) | = `colorScheme.onSurfaceVariant` |
  | `dividerSubtle` | тонкий разделитель списка (§9.3) | = `colorScheme.outlineVariant` |
  | `fileChipBackground` | фон file-chip (§9.7) | = `colorScheme.surfaceContainerHighest` |
  | `dragHandle` | drag-handle bottom-sheet @40% (§9.10) | `onSurfaceVariant` @ 0.40 |

  > **Решение «роль vs ColorScheme».** Если значение точно равно роли `ColorScheme` без модификаций — предпочтительно читать его напрямую из `colorScheme.*` (не плодить дубль-роль). В `AppColors` заводятся **только** роли с модификацией (непрозрачность 70%/40%) или с семантикой, отсутствующей в M3. Финальный минимальный набор утверждается на plan; таблица — кандидаты, не контракт.

- **Источник-токен.** Производные от `color.{light,dark}.tokens.json` (через роли `ColorScheme`) + правила непрозрачности `design-system.md` §9.2/§9.10/§2.6. Значения — **из токенов/ролей**, не ad-hoc-литералы (FR-007).
- **Отношения.** Регистрируется в `AppTheme._build` через `extensions:` для light **и** dark (§8). `surfaceMuted` skeleton удаляется/заменяется на token-driven роль. Скелетные ad-hoc-литералы — единственный текущий нарушитель «значения из токенов».
- **Валидация / инварианты.**
  - `copyWith` + `lerp` покрывают **все** поля (пропуск ломает анимацию смены темы).
  - `context.appColors` резолвится в **обоих** режимах (нет throw из-за незарегистрированного расширения) — проверяется переключением `themeMode` (US2 AS-1).
  - Все значения происходят из токенов/ролей (нет ad-hoc literal после доводки, FR-007).
  - Виджеты-потребители **не** создаются (граница «кроме виджетов», FR-023).

---

## 3. `TextTheme` / типошкала + Sans/Mono + wordmark

**Файл:** `lib/design/theme/nox_text_theme.dart` (GENERATED). **Статус:** EXISTING; стиль wordmark `NOX` — NEW токен.

- **Что это.** `const TextTheme noxTextTheme` — полная M3-шкала из токенов; плюс семейства Sans/Mono и (новый) стиль wordmark.
- **Форма (M3-слоты, заданные сейчас).** Каждый слот — `TextStyle(fontFamily, fontSize, height = lineHeightPx/fontSize, fontWeight, letterSpacing)`:

  | Слот | Size/Line | Weight | letterSpacing | Применение (NOX) |
  |---|---|---|---|---|
  | `displaySmall` | 36/44 | 400 | 0 | резерв |
  | `headlineSmall` | 24/32 | 400 | 0 | заголовок empty-state; title Logout-dialog |
  | `titleLarge` | 22/28 | 400 | 0 | AppBar title; **база wordmark** |
  | `titleMedium` | 16/24 | 500 | 0.15 | имя чата в списке; author header |
  | `bodyLarge` | 16/24 | 400 | 0.5 | текст сообщения; поля; ID (mono-слот) |
  | `bodyMedium` | 14/20 | 400 | 0.25 | превью; helper; размер файла |
  | `labelLarge` | 14/20 | 500 | 0.1 | текст кнопок |
  | `labelMedium` | 12/16 | 500 | 0.5 | подписи табов; counter `N/32` |
  | `labelSmall` | 11/16 | 500 | 0.5 | время в bubble; unread badge |

- **Семейства (font families).**
  - **Sans** — `font.family.sans` = `[Roboto, system-ui, sans-serif]`. **Дрейф к разрешению:** генерируемый Dart хардкодит `const String _sans = 'Roboto'` → молчаливый fallback на Windows/Linux. Политика (FR-010, Clarifications): Sans **платформенно-нативный** (Roboto на Android, SF на iOS/macOS, системный на Windows/Linux) — `_sans` НЕ хардкодит `'Roboto'`. Реализация — §13.
  - **Mono** — `noxMonoFamily = 'Roboto Mono'` (= `font.family.mono` `[Roboto Mono, ui-monospace, monospace]`). Используется только для `Your ID` (7.1), метрики как `bodyLarge` (16/24). Бандлится — §13.
- **Wordmark `NOX` (NEW токен, FR-005).** Не слот M3, а именованный стиль: база `titleLarge`, `fontWeight: 700` (`font.weight.bold`), `letterSpacing: +0.12em` (≈ `fontSize * 0.12` в logical px). Заводится как `static const`/фабрика рядом с темой (например `noxWordmarkStyle` в `nox_text_theme.dart` либо в `AppTextStyleTokens`). Цвет — на месте вызова (`brand/white` на splash / `onSurface` в AppBar).
- **Источник-токен.** `typography.tokens.json` (слоты + `font.family` + `font.weight`).
- **Отношения.** `noxTextTheme` → `AppTheme.textTheme` (§8); слоты — канонический type scale (читать `Theme.of(context).textTheme.*`). `AppTextStyleTokens` (§4) — тонкая обёртка поверх. `height` — безразмерный множитель (не умножается на UI-скейл — иначе квадратично).
- **Валидация / инварианты.**
  - Каждое `fontSize`/`height`/`weight`/`letterSpacing` === `typography.tokens.json` (нулевой дрейф).
  - Sans применяется **без** молчаливого системного fallback при включённом font-policy на всех 5 платформах (SC-005); Mono детерминирован за счёт бандла (SC-010).
  - Wordmark: weight 700 + letter-spacing +0.12em (FR-005).

---

## 4. `AppTextStyleTokens` — типо-обёртки (color-injecting)

**Файл:** `lib/design/app_text_style_tokens.dart`. **Статус:** EXPAND — выровнять под M3-шкалу (FR-019).

- **Что это.** `abstract final class` с приватным ctor; тонкие фабрики `body`/`title`/`caption({required Color color})` поверх `noxTextTheme`. Цвет передаётся на месте вызова; `fontSize` масштабируется `.sp` (учитывает `minTextAdapt`).
- **Дрейф к разрешению (FR-019).** Текущие фабрики рассинхронны с M3-шкалой: `title` = `18/w600` — **нет** такого слота (M3 `titleMedium` 16/w500, `titleLarge` 22/w400); `body`/`caption` совпадают с `bodyMedium`/`labelMedium` по размеру/весу. Доводка: размеры/веса фабрик выравниваются под канонические слоты `noxTextTheme` (без «магического» 18/w600), либо обёртки сводятся к чтению слотов темы напрямую. Семейство фабрики не задают (наследуют тему).
- **Источник-токен.** Производно от `typography.tokens.json` (через `noxTextTheme`).
- **Отношения.** Канонический type scale — `noxTextTheme` (читать из темы); `AppTextStyleTokens` — удобство для частых стилей с цветом на месте. `.sp` легитимен только внутри токен-класса.
- **Валидация / инварианты.** Размер/вес каждой фабрики совпадает с соответствующим слотом M3 (нет рассинхрона, FR-019); `color` обязателен; `height` не задаётся.

---

## 5. Токен-классы — `NoxSpacing` / `NoxRadius` / `NoxElevation` / `NoxDuration` / `NoxEasing`

**Файл:** `lib/design/theme/nox_tokens.dart` (GENERATED). **Статус:** EXISTING.

- **Что это.** Фиксированные (не-скейленные) не-цветовые константы из дизайн-токенов. `abstract final class` каждый, приватный ctor.
- **Форма.**

  | Класс | Форма / поля | Источник-токен |
  |---|---|---|
  | `NoxSpacing` | 4dp-сетка `s1=4 s2=8 s3=12 s4=16 s6=24 s8=32` + семантика `screenPadding=16`, `minTapTarget=48` | `spacing.tokens.json` |
  | `NoxRadius` | `none=0 xs=4 s=8 m=12 l=16 xl=28 full=999` + `bubble({required bool isOwn}) → BorderRadius` (асимметрия: «свой» bottom-right / «чужой» bottom-left клипуется до `xs=4` вместо хвоста) | `shape.tokens.json` |
  | `NoxElevation` | M3 tonal dp: `level0=0 level1=1 level2=3 level3=6 level5=12` | `elevation.tokens.json` |
  | `NoxDuration` | `splashIn=400 push=300 tabFade=150 snackbarIn=150 snackbarOut=75 sheet=300` (мс) | `motion.tokens.json` |
  | `NoxEasing` | `standard` (`Easing.standard`), `emphasized` (`Curves.easeInOutCubicEmphasized`), `emphasizedDecelerate` (`Easing.emphasizedDecelerate`) | `motion.tokens.json` |

- **Источник-токен.** `{spacing,shape,elevation,motion}.tokens.json`.
- **Отношения.** `NoxRadius`/`NoxElevation`/`NoxDuration`/`NoxEasing` — единственный канал своих ролей (конфликтов нет). `NoxSpacing` (fixed dp) **дублирует** базовые шаги `AppSpacingTokens` (responsive) — сведение §6. `bubble(...)` потребляется будущим bubble-виджетом (вне объёма) — здесь только токен.
- **Валидация / инварианты.**
  - Каждое значение === соответствующий токен (нулевой дрейф, SC-003).
  - **`NoxElevation.level4` намеренно отсутствует:** `elevation.tokens.json` не содержит `level/4` (8dp помечен «—»/unused в `design-system.md` §5). Код корректен; добавлять `level4` **не** нужно (иначе дрейф от токена).
  - `minTapTarget = 48` — гарантированный tap-target (контекст, где скейл нежелателен).

---

## 6. `AppSpacingTokens` — responsive отступы

**Файл:** `lib/design/app_spacing_tokens.dart`. **Статус:** EXISTING — канонизировать канал (FR-018).

- **Что это.** Отзывчивый `sN`-масштаб: `abstract final class`, приватный ctor, **геттеры** `s4..s32 = N * _scale`, где `_scale => (1.w + 1.h) / 2` (среднее факторов width/height из `flutter_screenutil`, дизайн-канва `Size(360, 779)`).
- **Форма.** `s4 s8 s12 s16 s24 s28 s32` (геттеры `double`).
- **Источник-токен.** Производно от `spacing.tokens.json` (те же базовые шаги, домноженные на `_scale`).
- **Отношения / дубль к сведению (FR-018, SC-006).** `AppSpacingTokens` (responsive) и `NoxSpacing` (fixed dp) несут одни и те же базовые шаги — **два параллельных канала**. Канон для кода фич — `AppSpacingTokens` (адаптив); `NoxSpacing` — только где скейл нежелателен (`minTapTarget`). Решение фичи: оставить **один канонический канал на роль** (адаптивный отступ ← `AppSpacingTokens`; гарантированный dp ← `NoxSpacing.minTapTarget`/`screenPadding`), без двух взаимозаменяемых классов для одной роли.
- **Валидация / инварианты.** `_scale` валиден только после `ScreenUtilInit` → доступ только в `build` под `AppRoot` (геттеры, не `const`). `.w/.h` легитимны только внутри токен-класса. Для каждой роли — один канал (SC-006).

---

## 7. `NoxBrand` + фундамент аватаров

**Файл:** `lib/design/theme/nox_brand.dart` (GENERATED). **Статус:** EXISTING.

- **Что это.** Brand-фиксированные цвета (вне `ColorScheme`, не зависят от темы) + детерминированная аватар-логика. Два продуктовых исключения темизации: splash-фон всегда тёмный (`canvasDark`), QR-поверхность всегда светлая (`qrSurface`/`qrInk`).
- **Форма.**

  | Часть | Поля / форма | Источник-токен |
  |---|---|---|
  | `NoxBrand` (палитра) | `teal #12B4B4`, `tealDeep #0E7C7C`, `gold #F4C20C`, `amber #FBB00C`, `coral #FB7A12`, `red #E11D1D`, `lime #8FA50C`, `blue #2E6FB0`, `white #FAFAFA` | `brand.tokens.json` |
  | `NoxBrand` (brand-fixed exceptions) | `canvasDark #0C2424` (splash), `ink #0C0C0C`, `qrSurface #FFFFFF`, `qrInk #0C0C0C` | `brand.tokens.json` |
  | `noxAvatarPalette` | `List<Color>` из **8** контраст-выверенных фонов (`#0E7C7C #8A6A00 #AD4A15 #5C7300 #2E6FB0 #C0392B #7A4DB3 #1E7268`) | `avatars.tokens.json` |
  | `noxAvatarIndex(name)` | хеш `h = (h*31 + charCode) & 0xFFFFFFFF; return h % 8` | `avatars.tokens.json` (зеркалит `src/tokens.jsx`) |
  | `noxAvatarColor(name)` | `noxAvatarPalette[noxAvatarIndex(name)]` | производно |
  | `noxInitials(name)` | 1–2 инициала (первые буквы первых двух слов, иначе первые 1–2 alnum); `null` → caller рисует `forum`-fallback (белый) | `design-system.md` §2.5 / `overview.md` |

- **Отношения.** `noxAvatarColor`/`noxInitials` — фундамент будущего avatar-виджета (вне объёма). Fallback-glyph `forum` берётся из `NoxIcons` (§10). Палитра аватаров — **отдельная** от бренд-палитры (затемнённые производные; `violet`/`green` есть только здесь).
- **Валидация / инварианты.**
  - Хеш/индекс/инициалы **детерминированы** и совпадают с правилом §2.5 (проверяемо тестом, SC-007): для одного `name` всегда тот же цвет/инициалы.
  - Все 8 фонов дают контраст к белым инициалам ≥ 4.5:1 (WCAG AA, §2.5) — покрыто §16.
  - Значения === `brand.tokens.json` / `avatars.tokens.json` (нулевой дрейф).
  - Brand-fixed exceptions независимы от `themeMode` (US1 AS-2).

---

## 8. `AppTheme` — сборка темы + component-сабтемы

**Файл:** `lib/design/theme/app_theme.dart`. **Статус:** EXPAND — primitives-only → **полная** тема с component-сабтемами (FR-006/FR-008).

- **Что это.** `class AppTheme` с приватным ctor; `static ThemeData light()/dark()` через общий `_build(ColorScheme scheme, AppColors appColors)`. Связывает `ColorScheme` (§1) + `noxTextTheme` (§3) + `AppColors`-extension (§2) + (новые) component-сабтемы из токенов.
- **Текущая форма (skeleton).** `_build` задаёт только `useMaterial3`, `colorScheme`, `textTheme`, `scaffoldBackgroundColor: scheme.surface`, `extensions: [appColors]`.
- **Целевая форма — component-сабтемы (FR-008; переопределяет дефолт блюпринта 06 §3 «сабтемы с первой фичей» → блюпринт обновляется, FR-021/SC-009).** Источник биндингов — уже сгенерированный `docs/design/system/nox-handoff/flutter/nox_theme.dart` (копируется в `lib/design/theme`/встраивается в `_build`) + §9 component-токены. Сабтемы:

  | Сабтема (`ThemeData`-поле) | Биндинг из токенов (§ design-system) |
  |---|---|
  | `appBarTheme` | `surface`/`onSurface`, elevation `level0`, `scrolledUnderElevation: level2`, `titleTextStyle: titleLarge` (§9.11) |
  | `filledButtonTheme` | `primary`/`onPrimary`, `StadiumBorder` (`full`), `labelLarge`, `minimumSize (0, minTapTarget)` (§9.5) |
  | `textButtonTheme` | `primary`, `StadiumBorder`, `labelLarge`, `minTapTarget` (§9.5) |
  | `inputDecorationTheme` | `shape/xs`, border `outline` / focus `primary`(w2) / error `error`, helper/counter `onSurfaceVariant` (§9.5) |
  | `cardTheme` | `surfaceContainerLow`, `level1`, `shape/m`, `margin: zero` (§9.4) |
  | `floatingActionButtonTheme` | `primaryContainer`/`onPrimaryContainer`, `level3`, `CircleBorder` (`full`) (§9.1) |
  | `bottomAppBarTheme` | `surfaceContainer`, `level2` (§9.1; notch — на виджете, вне объёма) |
  | `bottomSheetTheme` | `surface`, `level5`, top `shape/xl` (§9.10) |
  | `dialogTheme` | `surfaceContainerHigh`, `level5`, `shape/xl`, title `headlineSmall`/`onSurface`, body `bodyMedium`/`onSurfaceVariant` (§9.11) |
  | `snackBarTheme` | `inverseSurface`/`onInverseSurface`, action `inversePrimary`, floating (error-вариант — per-call) (§9.11) |
  | `segmentedButtonTheme` | `shape/s` (selected `secondaryContainer`/`onSecondaryContainer` — M3 default) (§9.5) |
  | `dividerTheme` | `outlineVariant`, thickness 1, space 1 (§9.3) |
  | `progressIndicatorTheme` | `primary`, linearTrack `surfaceContainerHighest`/`surfaceVariant` (§9.6) |
  | `navigationBarTheme` / `navigationRailTheme` | selected `primary`, unselected `onSurfaceVariant`, indicator `secondaryContainer`/`onSecondaryContainer` (§9.1, блюпринт 06 §3) |
  | `pageTransitionsTheme` | Cupertino на iOS/Android (жест перехода; не сужает scope) |

  > **Дрейф в handoff `nox_theme.dart` к разрешению.** Сгенерированный `pageTransitionsTheme` использует `ZoomPageTransitionsBuilder` (Android) — блюпринт 06 §3 канонизирует Cupertino-жест (iOS+Android) или стоковый M3; согласовать при сборке (FR-021).

- **Источник-токен.** `nox_color_scheme.dart` + `nox_text_theme.dart` + `nox_tokens.dart` + §9 component-токены (через `nox_theme.dart`).
- **Отношения.** Потребляется `MaterialApp` (`theme:`/`darkTheme:`/`themeMode:` из `AppRootBloc`, блюпринт 05 — вне объёма). `Light*` регистрируется в `light()`, `Dark*` в `dark()` (синхронность обоих режимов). НЕТ `colorSchemeSeed`/`_PaletteColors`/`fromSeed`.
- **Валидация / инварианты.**
  - Обе темы собираются и переключаются без потери ролей (SC-002).
  - Стоковые M3-компоненты (`Card`/`FilledButton`/`SnackBar`/...) под темой получают NOX-стиль (форма/цвет/высота из токенов) **без** локального хардкода (US2 AS-2, FR-008).
  - **Сами виджеты не пишутся** (граница, FR-023) — проверка только тест/golden на `ThemeData` (несёт extension + сабтемы).
  - Единая M3-тема из одного teal-seed на всех 5 платформах; `yaru`/desktop-темы не используются.

---

## 9. `NoxComponentTokens` — brand-fixed component-токены (§9)

**Файл:** `lib/design/theme/nox_component_tokens.dart`. **Статус:** NEW (FR-009).

- **Что это.** Именованные токены для brand-fixed component-значений, которые **не сводятся** к роли `ColorScheme` (читаемость поверх живого видео / гарантированно светлая QR-поверхность). Сейчас разбросаны прозой в `design-system.md` §9.9/§9.10 — фиксируются как токены дизайн-слоя.
- **Форма (кандидаты).**

  | Токен | Значение | Источник (§) |
  |---|---|---|
  | `qrScannerMask` | `#000000` @ 55% (затемнение вне прицела) | §9.9 |
  | `qrScannerReticleStroke` | `brand/white #FAFAFA`, ширина 3dp, углы `shape/m` (12), ≈70% ширины экрана | §9.9 |
  | `qrScannerInstructionInk` | `#FAFAFA` (фикс, не theme) | §9.9 |
  | `qrSurface` | `brand/qr-surface #FFFFFF` (фикс светлая) | §9.10 → = `NoxBrand.qrSurface` |
  | `qrInk` | `brand/qr-ink #0C0C0C` | §9.10 → = `NoxBrand.qrInk` |
  | `qrQuietZone` | ≥ 4 модуля / ~16dp padding | §9.10 |

  > QR-поверхность/чернила уже есть в `NoxBrand` (§7) — `NoxComponentTokens` агрегирует/ре-экспортирует их как именованные component-токены и добавляет недостающие (mask/reticle/instruction/quiet-zone). Возможна консолидация в `NoxBrand`, если так чище (решается на plan).

- **Источник-токен.** `design-system.md` §9.9/§9.10 (component-токены; в `*.tokens.json` могут отсутствовать → завести при необходимости как новый токен-файл/секцию).
- **Отношения.** Потребляются будущими QR-виджетами (scanner-overlay, QR bottom-sheet — вне объёма). Не зависят от `themeMode`.
- **Валидация / инварианты.** Доступны как именованные токены (US2 AS-3, FR-009); brand-fixed (тема не меняет). Виджеты не пишутся.

---

## 10. `NoxIcons` реестр + карта «тип файла → IconData»

**Файл:** `lib/design/nox_icons.dart`. **Статус:** NEW (FR-011). Зависит от нового пакета `material_symbols_icons` (§13/`pubspec`).

- **Что это.** Иконочный фундамент: набор Material Symbols Rounded (оси FILL/weight/grade) через `material_symbols_icons` (`Symbols.*`) + реестр имён `NoxIcons` (nav/action/status/file-type) + детерминированная карта «тип файла → `IconData`» с дефолтом.
- **Форма.**

  | Группа | Поля (имя → ligature) |
  |---|---|
  | navigation (§8) | `chats = forum`, `settings = settings`, `add = add` (selected = FILL 1, unselected = FILL 0 — ось FILL, не суффикс `_outlined`) |
  | actions (§8) | `back arrow_back`, `paste content_paste`, `scan qr_code_scanner`, `attach attach_file`, `send`, `flashlightOn/Off`, `cameraswitch`, `search`, `visibility/visibilityOff`, `copy content_copy`, `qr qr_code`, `save download`, `edit`, `removeAttachment close` |
  | status (§8/§9.2) | `pending schedule`, `sent check`, `error error_outline` (цвета — роли, не в реестре) |
  | empty-state fallback | `noChats forum`(FILL0), `noMessages chat_bubble`(FILL0), `noFiles folder_open` |
  | misc | `universalError error_outline`, `avatarFallback forum` |

- **Карта «тип файла → IconData» (`fileTypeIcon`).** Детерминированная функция/`Map` с **дефолтом** для неизвестного типа:

  | Тип | IconData (`Symbols.*` / `Icons.*`) |
  |---|---|
  | image | `image` |
  | video | `videocam` |
  | audio | `audiotrack` |
  | pdf | `picture_as_pdf` |
  | document (doc/docx/odt) | `description` |
  | spreadsheet (xls/csv) | `table_chart` |
  | text | `article` |
  | archive (zip/rar/7z) | `folder_zip` |
  | **default / unknown** | `insert_drive_file` |

- **Источник-токен.** `design-system.md` §8 + `nox-handoff` `spec/icons.md` (+ перенос FILL-оси из `nox-handoff-2/spec/icons.md`, FR-020). `overview.md` «Файлы: иконки типов» — карта типов.
- **Отношения.** Питает будущие nav/file-chip/avatar-fallback/empty-state/error-виджеты (вне объёма). Авторитетный набор макета — Material Symbols Rounded; `material_symbols_icons` даёт оси FILL/weight/grade (стоковые `Icons.*` запекают fill в имя).
- **Валидация / инварианты.**
  - Реестр + карта покрывают **все** позиции §8 / `overview.md` (SC-001).
  - Карта возвращает иконку для известного типа и **дефолт** `insert_drive_file` для неизвестного (US3 AS-2, FR-011, детерминированно — SC-007).
  - Иконки не рендерятся в продуктовых виджетах (граница).

---

## 11. Asset registry — flutter_gen (канонический канал)

**Файлы:** `lib/design/gen/assets.gen.dart` (GENERATED, gitignored) + `lib/design/app_images_tokens.dart` (рукописный → retire). **Статус:** EXISTING — канонизировать в один канал (FR-018, SC-006).

- **Что это.** Канал доступа к путям ассетов. Сейчас **два** параллельных канала: type-safe `Assets.png/.svg/.animation` (flutter_gen) и рукописный `AppImagesTokens`.
- **Форма.**
  - `assets.gen.dart` — генерируется `flutter_gen_runner` из реальных файлов под `assets/` (конфиг `pubspec.yaml::flutter_gen`: `output: lib/design/gen/`, `flutter_svg: true`, `fonts.enabled: false`, `line_length: 140`); gitignored, исключён из анализатора.
  - `AppImagesTokens` — `abstract final class` со `static const`-путями (`_base='assets/png'`, `logo`, `emptyState`).
- **Слоты дизайн-системы (§10/§11).** Логотип (splash); 3 empty-state иллюстрации (5.1 chats / 5.2 messages / 5.4 files); app icon (launcher). **Реальные графические файлы ещё не поставлены** (внешние дизайн-поставки) — в объёме только реестр/плумбинг + fallback (см. ниже).
- **Источник-токен.** Директории `pubspec.yaml::flutter.assets` (`assets/`, `assets/png/`, `assets/svg/`, `assets/animation/` — сейчас все с `.gitkeep`).
- **Отношения / решение (FR-018).** Канонический канал — **flutter_gen** (подключён в pubspec + CI). Рукописный `AppImagesTokens` сворачивается в пользу `Assets.*` (один канал на роль, SC-006). Fallback к Material-иконке (из `NoxIcons` §10) для отсутствующих empty-state ассетов: 5.1 → `forum_outlined`, 5.2 → `chat_bubble_outline`, 5.4 → `folder_open` (§10 design-system).
- **Валидация / инварианты.**
  - Один канонический канал ассетов (нет двух параллельных реестров, SC-006).
  - Реестр деградирует к Material-fallback, **не падая**, когда реальный файл ещё не поставлен (US3, FR-015, Edge Case).
  - Реальные SVG/иконка приложения — внешние поставки (вне объёма); подключаются по мере доставки.

---

## 12. `AppOverlayStyleTokens` + глобальное применение

**Файл:** `lib/design/app_overlay_style_tokens.dart`. **Статус:** EXISTING (токены) + canon применения (FR-016).

- **Что это.** `abstract final class`, приватный ctor; `static const SystemUiOverlayStyle light`/`dark` — **только** поля статус-бара (`statusBarColor` прозрачный, `statusBarIconBrightness`, `statusBarBrightness`). Поля Android-навбара намеренно опущены (Android-only; scope — 5 платформ).
- **Форма.** `light` (тёмные иконки на светлом), `dark` (светлые иконки на тёмном); оба `statusBarColor: 0x00000000`.
- **Канон применения (FR-016).** Overlay применяется **глобально в `AppRoot`** по текущему `Brightness` (`MediaQuery.platformBrightnessOf` / `themeMode`-производный) через `SystemChrome.setSystemUIOverlayStyle(...)`. Per-screen `AnnotatedRegion<SystemUiOverlayStyle>` — **задокументированное исключение** (экран осознанно переопределяет brightness, напр. splash на `canvasDark`), не правило.
- **Источник-токен.** Brightness-производно (не из `*.tokens.json` — это поведенческий токен).
- **Отношения.** Применяется в `AppRoot` (root-виджет — блюпринт 05; глобальное применение в объёме как плумбинг, без продуктовых виджетов).
- **Валидация / инварианты.** Сырой `SystemUiOverlayStyle` в коде фич запрещён (только эти константы); один источник истины применения (глобально, без дублей по экранам).

---

## 13. Шрифты — Sans native + Mono bundle

**Файлы:** `pubspec.yaml::flutter.fonts` + `assets/fonts/` + font-policy в `nox_text_theme.dart`. **Статус:** NEW (bundle Roboto Mono) / EXPAND (Sans policy). FR-010.

- **Что это.** Подключение и политика шрифтов для детерминированной типошкалы на 5 платформах.
- **Форма / решение.**
  - **Sans — платформенно-нативный** (FR-010, Clarifications): Roboto (Android), SF (iOS/macOS), системный (Windows/Linux). НЕ хардкодить `'Roboto'` в `_sans` — иначе молчаливый fallback на Windows/Linux ломает шкалу. Реализация: `_sans = null`/платформенно-разрешаемое семейство (точный механизм — на plan).
  - **Mono — `Roboto Mono` бандлится:** файлы шрифта в `assets/fonts/` + блок `fonts:` в `pubspec.yaml` (`family: Roboto Mono`, `fonts: [asset: ...]`). Сейчас `pubspec.yaml` **не содержит** `flutter.fonts` и `assets/fonts/` — оба NEW.
  - **Зависимость пакета иконок:** `material_symbols_icons` добавляется в `dependencies` (для §10). Сейчас в `pubspec.yaml` отсутствует — NEW.
- **Источник-токен.** `typography.tokens.json` `font.family.{sans,mono}`.
- **Отношения.** Mono-слот (`noxMonoFamily`) питает отображение `Your ID` (7.1). `flutter_gen` `fonts.enabled: false` (шрифты не генерятся flutter_gen — конфиг остаётся).
- **Валидация / инварианты.** Заявленные семейства применяются **без** молчаливого системного fallback при включённом бандле на всех 5 платформах (SC-005, US3 AS-1); Mono детерминирован (бандл). Реальные TTF/OTF Roboto Mono — поставка ассета (плумбинг готов даже до файла).

---

## 14. `DateFormatter` — лестницы дат/времени

**Файл:** `lib/general/formatters/date_formatter.dart`. **Статус:** EXPAND — узкий скелет → NOX-лестницы (FR-012).

- **Что это.** Статическая утилита (без DI) для относительного форматирования по двум NOX-лестницам.
- **Текущая форма (скелет).** `short(date)` = `MMM dd, yyyy`; `time(date)` = `HH:mm`.
- **Целевая форма — две лестницы (FR-012, `overview.md`/`design-system.md`).**

  | Лестница | Правило (по убыванию свежести) |
  |---|---|
  | **Список чатов (5.1)** — относительное | `now` → `N min` → `N h` → `Yesterday` → `12 May` (текущий год) → `12 May 2025` (прошлые годы) |
  | **Разделитель дня в ленте (5.2)** | `Today` → `Yesterday` → день недели (в пределах недели) → `12 May` / `12 May 2025`; время каждого сообщения — `HH:mm` |

- **Источник-токен.** `overview.md` «Форматы времени и даты» + `design-system.md` §3 (типографика времени).
- **Отношения.** Потребляется будущими chat-list-item / day-separator / bubble-виджетами (вне объёма). Строки `now`/`min`/`h`/`Yesterday`/`Today` — UI-microcopy (English, согласовать с `TextConstants` §15). `intl` `DateFormat` для абсолютных частей.
- **Валидация / инварианты.** Лестницы воспроизводят форматы спеки **детерминированно** (проверяемо тестом на фиксированных `DateTime`, SC-007, US3 AS-3); язык — English; приватный ctor.

---

## 15. `TextConstants` — microcopy additions

**Файл:** `lib/general/text_constants.dart`. **Статус:** EXPAND — добавить сетевые/offline-строки (FR-013).

- **Что это.** Единый `abstract final class` со всей UI-microcopy (English, ARB-ready). Никаких строковых литералов копи в виджетах.
- **Текущая форма.** `appName='NOX'`, `chats`, `settings`, `errorGeneralTitle`, `actionTryAgain`, `noData`, `comingSoon`.
- **Целевые добавления (FR-013, `overview.md` сетевой копирайт).**

  | Кандидат-строка | Значение (English) | Источник |
  |---|---|---|
  | сетевой паттерн | `Could not <verb>. Check your connection and try again.` (слово `connection`, не `internet`) | `overview.md` «Сетевые ошибки — копирайт» |
  | offline banner | `No connection` (persistent `MaterialBanner` на 5.1/5.2) | `overview.md` |
  | исключение 5.1 | `Could not load chats. Pull to refresh.` | `overview.md` |
  | relative-time юниты | `now`, `min`, `h`, `Yesterday`, `Today` (для §14) | `overview.md` |

- **Источник-токен.** `overview.md` (микрокопирайт); строки English даже в RU-доке (языки приложения — English + Ukrainian; русский UI-языком не бывает).
- **Отношения.** Потребляется будущими error/banner/empty-state-виджетами и `DateFormatter` (§14). Migration-ready под ARB + `flutter_localizations` (отдельная i18n-фича).
- **Валидация / инварианты.** Сетевые/offline-строки заданы и **не** хардкодятся в коде фич (FR-013); английский; приватный ctor.

---

## 16. A11y-инварианты + контраст-тесты

**Файлы:** `test/design/contrast_test.dart` + документированные инварианты (в `06-theming.md`/spec). **Статус:** NEW (FR-024).

- **Что это.** Зафиксированные правила доступности (`design-system.md` §2.6) + автотесты контраста пар роль/фон `ColorScheme`.
- **Форма (проверяемые пары / пороги).**

  | Пара роль/фон | Порог | Тип |
  |---|---|---|
  | `onSurface` / `surface` | ≥ 4.5:1 | body |
  | `onSurfaceVariant` / `surface` | ≥ 4.5:1 | body (captions/helper) |
  | `onPrimary` / `primary` | ≥ 4.5:1 | body на кнопке |
  | `onPrimaryContainer` / `primaryContainer` | ≥ 4.5:1 | own-bubble текст |
  | `onSecondaryContainer` / `secondaryContainer` | ≥ 4.5:1 | SegmentedButton selected |
  | `onError`/`error`, `onErrorContainer`/`errorContainer` | ≥ 4.5:1 | error |
  | `onInverseSurface` / `inverseSurface` | ≥ 4.5:1 | snackbar |
  | white / каждый из 8 avatar-фонов | ≥ 4.5:1 | инициалы (§2.5) |
  | иконки / крупный текст к фону | ≥ 3:1 | large/icons |
  | timestamp own (`onPrimaryContainer` @70%) | задокументировано как осознанное исключение; проверка контраста при 70% непрозрачности | §9.2/§2.6 |

- **Инварианты (документированные, §2.6).**
  - Контраст текста к фону — WCAG AA (≥ 4.5:1 body, ≥ 3:1 large/icons).
  - Смысл **не** кодируется только цветом (статусы/ошибки — иконка + текст).
  - Непрозрачность timestamp — **70%** (осознанное, не ниже AA для своего размера).
- **Источник-токен.** Значения ролей из `color.{light,dark}.tokens.json` (§1); пороги — `design-system.md` §2.6.
- **Отношения.** Контраст-тесты считают по значениям `noxLightScheme`/`noxDarkScheme` (§1) и `noxAvatarPalette` (§7) — обе темы.
- **Валидация / инварианты.** Тесты проходят для **всех** целевых пар в light **и** dark (SC-010, FR-024); провал = блокер gate.

---

## 17. Источник истины и гигиена (US4 cross-cutting)

- **Единый handoff.** Авторитетный источник — `docs/design/system/nox-handoff/` (DTCG + генерируемый Dart). `nox-handoff-2/` — дубликат: переносится только уникальный non-widget-контент (`spec/icons.md` с FILL-осью → в §10/перенос в `nox-handoff/spec/icons.md`), удаление дубликата — отдельный change-set (FR-020).
- **Правило регенерации.** `lib/design/theme/nox_*.dart` — копии хэндофа; руками не правятся, регенерируются из `tokens/*.tokens.json` (FR-017). Зафиксировать в блюпринте 06 (уже есть §0/§1) и соблюсти.
- **Устранённые дубли (один канал на роль, FR-018/SC-006).** spacing: `AppSpacingTokens` (adaptive) vs `NoxSpacing` (fixed dp) — §6; assets: `flutter_gen` vs `AppImagesTokens` — §11.
- **Исправленные дрейфы (FR-017/SC-003).** dark `outlineVariant` (§1), prose-vs-token surface tiers (§1) — разрешаются в пользу токена; устаревшая проза §2.3 правится под токен (docs-in-sync).
- **Выровненные обёртки (FR-019).** `AppTextStyleTokens` под M3-шкалу `noxTextTheme` — §4.
- **Docs-in-sync (FR-021/SC-009).** Блюпринт 06 §3 (component-сабтемы «с первой фичей») переопределяется фичей (сабтемы — в этой фиче) → блюпринт 06 обновляется в том же change-set; `nox_theme.dart` `pageTransitions`-дрейф согласуется (§8).

---

## 18. Сводка соответствия

| Артефакт (entity) | Статус | Источник (spec FR) | Источник (дизайн/блюпринт) |
|---|---|---|---|
| `ColorScheme` light/dark | EXISTING | FR-001, FR-017 | `color.*.tokens.json`, блюпринт 06 §1 |
| `AppColors` ThemeExtension | EXPAND | FR-007 | §9.2/§9.10, блюпринт 06 §2 |
| `TextTheme` + Sans/Mono + wordmark | EXISTING + NEW | FR-002, FR-005, FR-010 | `typography.tokens.json`, §3 |
| `AppTextStyleTokens` | EXPAND | FR-019 | §3, блюпринт 06 §5 |
| `NoxSpacing/Radius/Elevation/Duration/Easing` | EXISTING | FR-003 | `{spacing,shape,elevation,motion}.tokens.json`, §4–§7 |
| `AppSpacingTokens` | EXISTING | FR-018 | блюпринт 06 §4/§4.1 |
| `NoxBrand` + аватары | EXISTING | FR-004, FR-014 | `brand`/`avatars.tokens.json`, §2.4/§2.5 |
| `AppTheme` + component-сабтемы | EXPAND | FR-006, FR-008 | `nox_theme.dart`, §9, блюпринт 06 §3 |
| `NoxComponentTokens` (brand-fixed §9) | NEW | FR-009 | §9.9/§9.10 |
| `NoxIcons` + file-type map | NEW | FR-011 | §8, `icons.md`, `overview.md` |
| Asset registry (flutter_gen) | EXISTING | FR-015, FR-018 | §10/§11, блюпринт 06 §7 |
| `AppOverlayStyleTokens` + apply | EXISTING | FR-016 | блюпринт 06 §6/§6.1 |
| Шрифты (Sans native + Mono bundle) | NEW/EXPAND | FR-010 | `typography.tokens.json`, §3 |
| `DateFormatter` ladders | EXPAND | FR-012 | `overview.md`, §3 |
| `TextConstants` microcopy | EXPAND | FR-013 | `overview.md` сетевой копирайт |
| A11y-инварианты + контраст-тесты | NEW | FR-024 | §2.6 |
| Источник истины / гигиена | cross-cut | FR-017–FR-021 | `nox-handoff/`, блюпринт 06 |
| Виджеты §9 / реальные ассеты / DTCG-генератор | OUT | FR-023, Вне объёма | — (FUTURE / внешние поставки) |
