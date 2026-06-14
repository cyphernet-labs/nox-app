# Контракт: тема и дизайн-токены (`AppTheme` + `Nox*`/`App*Tokens`)

> **Источник «как»:** блюпринт `docs/blueprints/mobile/06-theming.md` (главный), + `01-stack-and-tooling.md` (зависимости), `10-code-templates.md` (шаблоны). **Источник истины значений:** DTCG-токены `docs/design/system/nox-handoff/tokens/*.tokens.json` → генерируемый Dart `docs/design/system/nox-handoff/flutter/nox_*.dart`; проза UI/UX — `docs/design/spec/design-system.md` (v0.2). Требования: FR-001…FR-009, FR-017…FR-021, FR-024. Этот файл — контракт (форма + правила) полной темизации NOX, **кроме виджетов**; сами виджеты/компоненты §9 — вне объёма (см. `spec.md` / «Вне объёма»).

> **Дивергенция от дефолта блюпринта (зафиксирована решением владельца).** Блюпринт 06 §3 в исходной форме строит `_build` как **минимальную** базу (`useMaterial3` + `colorScheme` + `textTheme` + `scaffoldBackgroundColor` + `extensions`) и откладывает component-сабтемы «до первой фичи-виджета». Эта фича переопределяет дефолт: `_build` собирает **полный** набор component-сабтем из токенов и component-токенов (`design-system.md` §9). Авторитетная форма уже есть в хэндофе — `docs/design/system/nox-handoff/flutter/nox_theme.dart` (`_base(ColorScheme)`); `AppTheme._build` приводится к ней. Блюпринт 06 §3 правится в этом же change-set (правило docs-in-sync, FR-021).

---

## 1. Источник истины и правило регенерации

Канал значений — **один**: DTCG-токены `nox-handoff/tokens/*.tokens.json` → сгенерированный Dart `nox-handoff/flutter/nox_*.dart` → его **копии** в `lib/design/theme/nox_*.dart`. Контракт:

- **Generated-файлы темы (`lib/design/theme/nox_*.dart`) руками не правятся** — они регенерируются из токенов. Правка значения = правка `tokens/*.tokens.json` + перекопирование Dart, **не** ad-hoc edit в `lib/`. Правило фиксируется в шапке каждого generated-файла (`// GENERATED — … Source of truth: tokens/…`).
- **Практический источник** — уже сгенерированный Dart из `nox-handoff/flutter/` (принимается как есть). Автоматизированный DTCG→Dart-генератор (Style Dictionary и т.п.) — **вне объёма** (см. `spec.md`).
- **Авторитетен один хэндоф** — `docs/design/system/nox-handoff/`. Каталог `nox-handoff-2/` — дубликат, **не** авторитетен; уникальный non-widget-контент (`icons.md` с FILL-осью) переносится до его удаления (FR-020).
- **При расхождении прозы и токенов истина — токены.** Пример: `design-system.md` §2.1 описывает `ColorScheme.fromSeed`, но реальный контракт — **явные** `noxLightScheme`/`noxDarkScheme` (роли вручную дотюнены, `fromSeed` НЕ используется); seed-teal `Color(0xFF12B4B4)` — провенанс, не рантайм-источник.
- **Дрейфы устраняются в пользу токена** (FR-017). Известный дрейф: dark `outlineVariant` — токен `color.dark.tokens.json` сейчас несёт `#4E5B58`, а `design-system.md` §2.3 — `#3F4948`; контракт сводит к **одному** значению `#3F4948` (правится токен → регенерируется Dart), чтобы код и проза совпали.

---

## 2. `AppTheme` — сборка `ThemeData`

**Файл:** `lib/design/theme/app_theme.dart`. Класс с приватным конструктором; две публичные фабрики + один приватный сборщик:

```dart
class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(noxLightScheme, const LightAppColors());
  static ThemeData dark()  => _build(noxDarkScheme,  const DarkAppColors());

  static ThemeData _build(ColorScheme scheme, AppColors appColors) { /* … */ }
}
```

Контракт `_build(ColorScheme scheme, AppColors appColors) → ThemeData`:

| Поле `ThemeData` | Значение | Источник |
|---|---|---|
| `useMaterial3` | `true` | M3-база |
| `colorScheme` | `scheme` (`noxLightScheme` / `noxDarkScheme`) | §1, `nox_color_scheme.dart` |
| `textTheme` | `noxTextTheme` | §1, `nox_text_theme.dart` |
| `scaffoldBackgroundColor` | `scheme.surface` | роль M3 |
| `extensions` | `<ThemeExtension<dynamic>>[appColors]` | `AppColors` (§4) |
| component-сабтемы | полный набор из токенов (§6) | §9 design-system.md |

Правила:

- **`ColorScheme` НЕ из `fromSeed`** — оба `scheme` — `const` явные схемы из хэндофа (полный набор M3-ролей задан вручную). Это инвариант (FR-001).
- **Симметрия light/dark:** каждое кастомное `ThemeExtension` регистрируется в **обоих** вариантах (`LightAppColors` в `light()`, `DarkAppColors` в `dark()`). Пропуск одного → рантайм-throw `context.appColors` в этом режиме (намеренный `!`, §4).
- **Единая M3-тема на всех 5 платформах** (iOS/Android/Windows/Linux/macOS). `yaru`/платформенные desktop-темы НЕ используются; источник схемы общий для всех таргетов.
- **`_build` параметризован** ровно двумя аргументами (`scheme`, `appColors`); никакой ветвящейся по `Platform` логики внутри сборки темы.
- `pageTransitionsTheme` (Cupertino-жесты на iOS/Android) допустим как часть `_build` (есть в хэндофе); ключи `TargetPlatform.iOS/.android` относятся только к жесту перехода и **не** сужают 5-платформенный scope.

---

## 3. `themeMode` — источник и потребление

- **Источник `themeMode`** — `AppRootBloc` (app-level value-BLoC): одновариантный `@freezed AppRootState` с единственным полем `themeMode` (`ThemeMode.system` / `.light` / `.dark`). НЕ трио `Initializing/Initialized/Error` (те — для фичевых BLoC). Переключение инициируется событием (`AppRootEvent.setTheme(...)` / эквивалент), персистится через настройки, эмиттится через `copyWith`. Сам `AppRootBloc` и его проводка — `05-presentation-layer.md` (вне объёма этой фичи; здесь фиксируется лишь контракт «откуда `MaterialApp` берёт режим»).
- **Потребление:** `MaterialApp` читает обе темы статически и режим реактивно:

```dart
MaterialApp(
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  themeMode: state.themeMode, // из AppRootBloc; НИКОГДА state.theme
);
```

- **Инвариант рантайм-смены темы:** при смене `themeMode` ни одна роль `ColorScheme`/`AppColors` не остаётся неинициализированной (обе темы полны), `AppColors.lerp` интерполирует все поля (см. §4) — анимация перехода не «ломается».

---

## 4. `AppColors` (ThemeExtension) и `context.appColors`

**Файл:** `lib/design/theme/app_colors.dart`. Пять частей в одном файле (паттерн `ThemeExtension`):

1. `@immutable class AppColors extends ThemeExtension<AppColors>` — все семантические `Color`-поля + `const`-конструктор.
2. `copyWith({...})` — по одному именованному параметру на поле (контракт `ThemeExtension`).
3. `lerp(other, t)` — **каждое** поле пролерплено через `Color.lerp(...)!`; пропуск поля ломает анимацию смены темы.
4. `LightAppColors` / `DarkAppColors` — конкретные значения на режим через `super(...)`.
5. `extension AppColorsExtension on BuildContext` — `AppColors get appColors => Theme.of(this).extension<AppColors>()!`.

Правила доводки (FR-007):

- **Полнота вместо skeleton.** Текущее состояние — намеренный skeleton (`surfaceMuted`, `dividerSubtle`, raw-литералы прямо в `Light/DarkAppColors`). Контракт доводит `AppColors` до **полного token-driven набора** доп-ролей дизайн-системы, которых нет в стоковом `ColorScheme`; значения происходят из токенов (`nox-handoff`), а не из ad-hoc литералов.
- **`AppColors` несёт ТОЛЬКО то, чего нет в `ColorScheme`.** Всё, что выражается ролью M3 (`primary`, `surface`, `onSurfaceVariant`, `secondaryContainer`/`onSecondaryContainer` для desktop `NavigationRail` и т.п.), читается через `Theme.of(context).colorScheme.*`, а **не** дублируется в `AppColors`. Семантика метаданных bubble «время @70%» (§9.2 / §2.6) выражается как непрозрачность от роли (`onSurfaceVariant`/`onPrimaryContainer` с alpha), не как отдельный hardcoded цвет.
- **Намеренный `!`** в геттере: отсутствие расширения = баг проводки (забыли зарегистрировать в `AppTheme`), должно падать громко, не молча.
- **Атомарность добавления роли:** новая роль = поле + параметр `copyWith` + строка `lerp` + значения в обоих `super(...)` — **все четыре места за один шаг**.
- **`context.appColors` резолвится в обоих режимах** (light и dark) — проверяется переключением `themeMode` (нет throw из-за отсутствующего расширения).
- НЕТ публичного `AppColorsTokens` (роль покрыта `AppColors` + `ColorScheme` — один канал цвета).

---

## 5. Generated токен-классы — API (`nox_tokens.dart`, `nox_brand.dart`, `nox_text_theme.dart`)

Generated, руками не правятся (§1). Контракт публичного API (формы, не значений — значения в токенах):

### 5.1 `nox_tokens.dart` (из `tokens/{spacing,shape,elevation,motion}.tokens.json`)

| Класс | Форма | Члены (контракт) |
|---|---|---|
| `NoxSpacing` | `abstract final`, `static const double` | 4dp-сетка `s1=4 / s2=8 / s3=12 / s4=16 / s6=24 / s8=32`; семантика `screenPadding=16`, `minTapTarget=48` |
| `NoxRadius` | `abstract final`, `static const double` + 1 метод | `none=0 / xs=4 / s=8 / m=12 / l=16 / xl=28 / full=999`; `static BorderRadius bubble({required bool isOwn})` |
| `NoxElevation` | `abstract final`, `static const double` | M3 tonal dp: `level0=0 / level1=1 / level2=3 / level3=6 / level5=12` (нет `level4` — токена нет) |
| `NoxDuration` | `abstract final`, `static const Duration` | `splashIn=400ms / push=300ms / tabFade=150ms / snackbarIn=150ms / snackbarOut=75ms / sheet=300ms` |
| `NoxEasing` | `abstract final`, `static const Curve` | `standard=Easing.standard / emphasized=Curves.easeInOutCubicEmphasized / emphasizedDecelerate=Easing.emphasizedDecelerate` |

- `NoxRadius.bubble({required bool isOwn})` — NOX-специфика: база `l(16)`, угол `bottomRight` у своих / `bottomLeft` у чужих клипуется до `xs(4)` (ассиметрия вместо «хвоста»). Используется виджетом bubble (вне объёма), но API доступен из темы сейчас.
- `NoxEasing.emphasized` — реальная M3 two-part-кривая (`Curves.easeInOutCubicEmphasized`); cubic-bezier в JSON — simple-cubic fallback для CSS-консьюмеров (Flutter его не использует).
- `NoxElevation.*` передаётся в `Material`/`Card.elevation` (dp). Ручной `BoxShadow` запрещён — Flutter сам рисует tonal-overlay+тень из dp (dark = tonal, без тени).

### 5.2 `nox_brand.dart` (из `tokens/{brand,avatars}.tokens.json`)

| Член | Форма | Назначение |
|---|---|---|
| `NoxBrand` | `abstract final`, `static const Color` | бренд-фикс-цвета вне `ColorScheme`: `teal/tealDeep/gold/amber/coral/red/lime/blue/white/canvasDark/ink/qrSurface/qrInk` |
| `noxAvatarPalette` | `const List<Color>` (8) | контраст-выверенные фоны аватаров (`violet`/`green` — только тут) |
| `noxAvatarIndex(String)` | `int` | детерминированный хеш: `h = (h*31 + codeUnit) & 0xFFFFFFFF`; `h % 8` |
| `noxAvatarColor(String)` | `Color` | `noxAvatarPalette[noxAvatarIndex(name)]` |
| `noxInitials(String)` | `String?` | 1–2 инициала; `null` → caller рисует glyph `forum` (инициалы всегда белые) |

Две **продуктовые** бренд-фиксированные поверхности, независимые от темы (`themeMode` их не флипает):
- **Splash-фон ВСЕГДА тёмный** — `NoxBrand.canvasDark` (`#0C2424`).
- **QR-поверхность ВСЕГДА светлая** — `NoxBrand.qrSurface` (`#FFFFFF`) / модули `NoxBrand.qrInk` (`#0C0C0C`).

### 5.3 `nox_text_theme.dart` (из `tokens/typography.tokens.json`)

- `const TextTheme noxTextTheme` — полный M3-набор слотов (`displaySmall`, `headlineSmall`, `titleLarge`, `titleMedium`, `bodyLarge`, `bodyMedium`, `labelLarge`, `labelMedium`, `labelSmall`); каждый слот несёт `fontSize`/`fontWeight`/`height`/`letterSpacing` из токена. `height = lineHeightPx / fontSize` (безразмерный множитель). `letterSpacing` — в логических px (из токена), сейчас в blueprint-скелете опущен → контракт требует его внести при регенерации.
- `const String noxMonoFamily = 'Roboto Mono'` — имя mono-семейства для слота отображения `Your ID` (§7.1 design-system).
- **Семейство sans НЕ хардкодится `'Roboto'`** (см. §7) — это правка относительно текущего generated-скелета (там `_sans = 'Roboto'`): на Windows/Linux хардкод даёт молчаливый fallback. Контракт: sans-слот опирается на платформенно-нативное семейство (Roboto/SF по ОС), mono-слот — на бандленный `Roboto Mono`.
- **Wordmark `NOX`** — отдельный токен-стиль (НЕ слот шкалы): Title Large / Bold `700` / letter-spacing `+0.12em`, всегда верхний регистр (FR-005).

---

## 6. `AppSpacingTokens` — единый канонический канал spacing

**Файл:** `lib/design/app_spacing_tokens.dart`. `abstract final class` с приватным `const`-ctor и **геттерами** (значение лениво вычисляется при каждом обращении — только после `ScreenUtilInit`):

```dart
abstract final class AppSpacingTokens {
  const AppSpacingTokens._();
  static double get _scale => (1.w + 1.h) / 2; // среднее факторов width/height
  static double get s4  => 4  * _scale;
  // … s8 / s12 / s16 / s24 / s28 / s32
}
```

**Решение о каноническом канале spacing (FR-018, устранение дубля `NoxSpacing` ↔ `AppSpacingTokens`):**

- **`AppSpacingTokens` (отзывчивый, `.w/.h`) — канонический канал отступов в коде фич.** Несёт те же базовые шаги, домноженные на `_scale` (адаптив на дизайн-канве `360×779`).
- **`NoxSpacing` (фиксированные dp) — узкий карв-аут** для контекстов, где скейл нежелателен: `minTapTarget` (гарантированные 48dp), `screenPadding`. Generated-значения сетки в `NoxSpacing` остаются источником-провенансом для шагов `AppSpacingTokens`.
- Это сведение «двух параллельных классов с одной ролью» к **одному** каналу-на-роль (адаптив → `AppSpacingTokens`; fixed-tap-target → `NoxSpacing`). Радиусы/elevation/motion дубля не имеют — они только в `nox_tokens.dart`.
- `.sp/.w/.h/.r`-extension'ы `flutter_screenutil` легитимны **только** внутри токен-классов; в коде фич — запрещены (правило «только токены», §9 блюпринта). Валидность `_scale` — только после `ScreenUtilInit`; отсюда геттеры, не `static const`.

> Родственный токен-класс `AppTextStyleTokens` (тонкие color-injecting фабрики `body`/`title`/`caption({required Color color})` через `.sp`) **выравнивается под каноническую M3-шкалу `noxTextTheme`** (FR-019): размеры/веса фабрик не должны расходиться с соответствующими слотами шкалы; канонический type scale — `Theme.of(context).textTheme.*`, фабрики — лишь удобство для частых стилей с цветом на месте вызова.

---

## 7. Шрифты — платформенно-нативный sans + бандленный mono (плумбинг)

Контракт конфигурации (FR-010; реализуется в `pubspec.yaml`, не в `lib/design/theme`):

- **Sans** — платформенно-нативный (Roboto на Android, SF на iOS/macOS, системный на Windows/Linux), **без** хардкода имени `'Roboto'` в `noxTextTheme` (иначе молчаливый fallback на desktop). Способ: либо платформенный дефолт (пустое `fontFamily` слота), либо бандл Roboto под все 5 платформ — но **детерминированно**, без молчаливой подмены, ломающей типошкалу.
- **Mono** — `Roboto Mono` **бандлится**: файлы в `assets/fonts/` + блок `fonts:` в `pubspec.yaml` (`family: Roboto Mono`), чтобы отображение `Your ID` выглядело одинаково на всех 5 платформах. Имя берётся из `noxMonoFamily`.
- Контракт `pubspec.yaml::flutter.fonts` — единственный источник декларации семейств; в Dart семейство задаётся через слот темы / `noxMonoFamily`, не строковым литералом в коде фич.

---

## 8. Component-сабтемы — биндинги токенов (§9 mapping)

`_build` конфигурирует сабтемы `ThemeData` так, чтобы стоковые M3-компоненты получали NOX-стиль **без** локальной стилизации (FR-008). Маппинг «сабтема → токены» (по `design-system.md` §9 + `nox_theme.dart` хэндофа):

| Сабтема `ThemeData` | Биндинги (роль / токен) | §9 |
|---|---|---|
| `appBarTheme` | bg `surface`, fg `onSurface`, `elevation: NoxElevation.level0`, `scrolledUnderElevation: NoxElevation.level2`, `centerTitle: false`, title = `noxTextTheme.titleLarge`@`onSurface` | §9.11 |
| `filledButtonTheme` | bg `primary`, fg `onPrimary`, `StadiumBorder()` (`shape/full`), text `labelLarge`, `minimumSize (0, NoxSpacing.minTapTarget)` | §9.5 |
| `textButtonTheme` | fg `primary`, `StadiumBorder()`, text `labelLarge`, `minimumSize (0, minTapTarget)` | §9.5 |
| `inputDecorationTheme` | `filled: false`, border/enabled `outline`@`NoxRadius.xs`, focused `primary` w2, error `error`, helper/counter `bodyMedium`@`onSurfaceVariant` | §9.5 |
| `cardTheme` | `surfaceContainerLow`, `NoxElevation.level1`, `RoundedRectangleBorder`@`NoxRadius.m`, `margin: EdgeInsets.zero` | §9.4 |
| `floatingActionButtonTheme` | bg `primaryContainer`, fg `onPrimaryContainer`, `NoxElevation.level3`, `CircleBorder()` (`shape/full`) | §9.1 |
| `bottomAppBarTheme` | `surfaceContainer`, `NoxElevation.level2` (notch `CircularNotchedRectangle` — на виджете оболочки) | §9.1 |
| `bottomSheetTheme` | `surface`, `NoxElevation.level5`, верхние углы `NoxRadius.xl` | §9.10 |
| `dialogTheme` | `surfaceContainerHigh`, `NoxElevation.level5`, `NoxRadius.xl`, title `headlineSmall`@`onSurface`, content `bodyMedium`@`onSurfaceVariant` | §9.11 |
| `snackBarTheme` | bg `inverseSurface`, content `bodyMedium`@`onInverseSurface`, action `inversePrimary`, `behavior: floating` (error-вариант `errorContainer`/`onErrorContainer` — per-call) | §9.11 |
| `segmentedButtonTheme` | shape `RoundedRectangleBorder`@`NoxRadius.s` (selected `secondaryContainer`/`onSecondaryContainer` — M3 default) | §9.5 |
| `dividerTheme` | color `outlineVariant`, `thickness: 1`, `space: 1` | §9.3/§9.8 |
| `progressIndicatorTheme` | color `primary`, `linearTrackColor: surfaceContainerHighest` | §9.6 |

Правила:

- **Цвет сабтем — только роли `ColorScheme`** (адаптируются light/dark); сырых `Color`-литералов в сабтемах нет.
- **Форма — `NoxRadius.*`**, **высота — `NoxElevation.*`**, **текст — слоты `noxTextTheme`** (никаких inline-чисел/`TextStyle`).
- `NavigationBarTheme`/`NavigationRailTheme` — оболочка NOX кастомная (`BottomAppBar`+docked-FAB / `NavigationRail` leading-FAB, см. `app-shell.md`), selected-indicator берёт стоковый `secondaryContainer`/`onSecondaryContainer`; отдельная роль `AppColors` не нужна. Сама оболочка-виджет — вне объёма; тут фиксируется лишь, что цвета индикатора приходят из `ColorScheme`.
- **error-вариант SnackBar** (`errorContainer`/`onErrorContainer`) задаётся на месте вызова, не в сабтеме (одна сабтема несёт нейтральный вариант).

---

## 9. Бренд-фиксированные component-токены (не сводятся к `ColorScheme`)

Часть component-токенов §9 **не** выражается ролью `ColorScheme` (читаемость поверх живого видео / гарантированная сканируемость QR) — они доступны как именованные токены дизайн-слоя (FR-009), но **не** реализуются как виджеты (виджеты QR-оверлея/sheet — вне объёма):

| Токен (§9.9 / §9.10) | Значение | Где живёт |
|---|---|---|
| Затемняющая маска QR-сканера (вне прицела) | `#000000` @ 55% | бренд-фикс-токен дизайн-слоя |
| Прицел (рамка) QR-сканера | stroke `NoxBrand.white` (`#FAFAFA`), 3dp, углы `NoxRadius.m`, ≈70% ширины | `NoxBrand.white` + `NoxRadius.m` |
| Overlay-инструкция сканера | текст `#FAFAFA` (фикс, не theme), `Body Large` | бренд-фикс-токен |
| QR-поверхность (карточка под код) | `NoxBrand.qrSurface` (`#FFFFFF`, фикс-светлая) | `nox_brand.dart` |
| QR-модули | `NoxBrand.qrInk` (`#0C0C0C`) | `nox_brand.dart` |

- Эти значения — `NoxBrand.*` (генерируются из `brand.tokens.json`) либо именованные бренд-фикс-токены маски/визиря; они **независимы от `themeMode`**.
- Permission-denied overlay сканера, напротив, **тематичен** (непрозрачная `surface` + роли) — это не бренд-фикс-исключение.

---

## 10. A11y-инварианты (контракт темы)

Доступность фиксируется как инварианты дизайн-слоя + автотесты (FR-024, `design-system.md` §2.6):

- **Контраст пар роль/фон `ColorScheme`** — WCAG AA: **≥4.5:1** для body-текста, **≥3:1** для крупного текста/иконок. Покрывается автотестами контраста для целевых пар (`onSurface`/`surface`, `onSurfaceVariant`/`surface`, `onPrimary`/`primary`, `onPrimaryContainer`/`primaryContainer`, `onSurface`/`surfaceContainerHigh`, `onInverseSurface`/`inverseSurface`, `onErrorContainer`/`errorContainer` и т.п.) в обоих режимах.
- **Аватар-фоны** (`noxAvatarPalette`, 8 шт.) дают контраст к белым инициалам **≥4.5:1** (§2.5).
- **Непрозрачность timestamp = 70%** (метаданные bubble, §9.2) — выражается как alpha от роли (`onPrimaryContainer`/`onSurfaceVariant`), задокументирована как инвариант.
- **Смысл не кодируется только цветом** — статусы сообщений/ошибки сопровождаются иконкой/текстом (`schedule`/`check`/`error_outline`); это требование к будущим виджетам, но иконочные имена-токены поставляются дизайн-слоем (см. `icons-and-assets.md`).

---

## Чеклист

- [ ] `AppTheme.light()/dark()` → `_build(scheme, appColors)`: `useMaterial3:true`, `colorScheme: noxLight/DarkScheme` (НЕ `fromSeed`), `textTheme: noxTextTheme`, `scaffoldBackgroundColor: scheme.surface`, `extensions:[appColors]`, полный набор component-сабтем (§8).
- [ ] `themeMode` берётся из `AppRootBloc` (`state.themeMode`), `MaterialApp(theme/darkTheme/themeMode)`; обе темы полны, смена режима не теряет ролей.
- [ ] `AppColors` доведён со skeleton до полного token-driven набора доп-ролей; `copyWith`/`lerp` покрывают КАЖДОЕ поле; `Light/DarkAppColors` зарегистрированы в обоих методах; намеренный `!`; нет дублирования ролей `ColorScheme`.
- [ ] Generated токен-классы (`NoxSpacing/NoxRadius/NoxElevation/NoxDuration/NoxEasing`, `NoxBrand`+аватары, `noxTextTheme`+`noxMonoFamily`) соответствуют контракту форм §5; руками не правятся.
- [ ] Канонический канал spacing сведён: адаптив → `AppSpacingTokens`, fixed-tap-target → `NoxSpacing`; нет двух параллельных классов на одну роль (FR-018).
- [ ] `AppTextStyleTokens`-фабрики выровнены под `noxTextTheme` (FR-019); sans НЕ хардкодит `'Roboto'`; mono = бандленный `Roboto Mono` (FR-010).
- [ ] Component-сабтемы §8 связаны только ролями `ColorScheme` + `NoxRadius`/`NoxElevation`/`noxTextTheme` (нет сырых литералов); error-SnackBar — per-call.
- [ ] Бренд-фикс component-токены (QR-маска/прицел/инструкция §9.9, QR-поверхность/модули §9.10) доступны как именованные токены (`NoxBrand.*` / маска-токены), независимы от `themeMode` (FR-009).
- [ ] Источник истины — `nox-handoff/tokens`; правило «руками не править, регенерировать» зафиксировано; dark `outlineVariant` сведён к `#3F4948` (нулевой дрейф, FR-017); авторитетен один хэндоф (FR-020).
- [ ] A11y-инварианты + автотесты контраста (≥4.5:1 body / ≥3:1 large/icons) проходят в обоих режимах; timestamp 70% задокументирован (FR-024).
- [ ] Блюпринт 06 §3 приведён в соответствие (полные сабтемы в `_build`) — docs-in-sync (FR-021); виджеты §9 НЕ реализованы (граница «кроме виджетов»).
