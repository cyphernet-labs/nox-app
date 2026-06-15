# 06 — Темизация и дизайн-токены

> **Назначение:** канонический контракт темизации NOX — светлая и тёмная темы поверх Material 3 `ColorScheme`, сборка `AppTheme.light()/dark()`, набор классов дизайн-токенов (отзывчивые отступы на `flutter_screenutil`, цвето-инъецирующие текстовые стили, overlay-стили, пути ассетов) и поддерживающий слой `lib/general/` (Constants, PlatformUtils, форматтеры, UI-микрокопи, фиче-флаги). Цвет приходит из M3 `ColorScheme` (через `Theme.of(context).colorScheme`) и семантических доп-ролей `AppColors`-расширения темы (`context.appColors`); все прочие токены — статические классы. Сырые `Color`/`EdgeInsets`/`TextStyle`/`SystemUiOverlayStyle` в коде фич запрещены.
> **Когда читать:** при настройке внешнего вида приложения — сборка темы для `MaterialApp`, подключение токенов вместо «магических» значений, форматирование чисел и дат; перед реализацией любого экрана (первый реальный экран — список чатов).
> **Связанные документы:** `05-presentation-layer.md` (где `AppTheme.light()/dark()` потребляются `MaterialApp` под управлением `AppRootBloc`, и где живёт `AppRootBloc` с `themeMode`), `00-architecture-overview.md` (раскладка single-package), `01-stack-and-tooling.md` (зависимости `flutter_screenutil`, `intl`, `flutter_svg`, `flutter_gen_runner`), `02-dependency-injection.md` (регистрация `@lazySingleton ValueFormatter`), `08-conventions-and-constitution.md` (дисциплина именования и правило «только токены»).
>
> **Источник дизайна (актуальный).** Конкретные авторитетные значения — токены (`color`/`typography`/`spacing`/`shape`/`elevation`/`motion`/`brand`/`avatars`) — живут в [`docs/design/system/nox-handoff/`](../../design/system/nox-handoff/): `tokens/*.tokens.json` (W3C DTCG — тул-агностичный **источник истины**) плюс сгенерированный из них Flutter-код в `flutter/` (`nox_color_scheme.dart`, `nox_text_theme.dart`, `nox_tokens.dart`, `nox_brand.dart`, `nox_theme.dart`). Сгенерированные файлы темы в коде приложения (`lib/design/theme/nox_*.dart`) — это **копии** этого хэндофа; их **не редактируют руками**, а регенерируют из токенов (правьте `tokens/*.tokens.json`, не Dart). Этот документ описывает, КАК эти значения собираются в `ThemeData` и потребляются виджетами.

---

## 0. Где всё лежит

Темизация и дизайн-токены живут в `lib/design/`, поддерживающие утилиты — в `lib/general/`. Обе папки — части единого пакета `nox_app`; никаких отдельных пакетов или path-зависимостей (см. `00-architecture-overview.md`). Слой `lib/resource/` существует как заявленный слой, но **сейчас это зарезервированный пустой плейсхолдер** (`.gitkeep`) — тема в нём НЕ живёт.

```
lib/
├── design/
│   ├── app_spacing_tokens.dart         # ОТЗЫВЧИВЫЙ sN-масштаб на flutter_screenutil (.w/.h)
│   ├── app_text_style_tokens.dart      # цвето-инъецирующие фабрики полной M3-шкалы (8 ролей, .sp)
│   ├── app_overlay_style_tokens.dart   # static const SystemUiOverlayStyle (status-bar)
│   ├── nox_icons.dart                  # семантический icon-реестр (NoxIcons → Assets.svg.icons.*)
│   ├── gen/
│   │   └── assets.gen.dart             # flutter_gen → Assets.png/.svg/.animation (генерится, gitignored)
│   └── theme/
│       ├── app_colors.dart             # ThemeExtension<AppColors> + Light/DarkAppColors + context.appColors
│       ├── app_theme.dart              # AppTheme.light()/dark() — сборка ThemeData из generated-handoff + AppColors
│       ├── nox_color_scheme.dart       # GENERATED: const ColorScheme noxLightScheme / noxDarkScheme
│       ├── nox_text_theme.dart         # GENERATED: const TextTheme noxTextTheme (Roboto / Roboto Mono)
│       ├── nox_tokens.dart             # GENERATED: NoxSpacing / NoxRadius(+bubble) / NoxElevation / NoxDuration / NoxEasing
│       └── nox_brand.dart              # GENERATED: NoxBrand (brand-fixed colors) + noxAvatarColor / noxInitials
└── general/
    ├── constants.dart                  # final class Constants: конфиг, regex, размеры, railBreakpoint
    ├── platform_utils.dart             # PlatformUtils.isDesktop / isMobile / per-OS геттеры
    ├── text_constants.dart             # abstract final TextConstants: вся UI-микрокопи (English)
    ├── feature_flags.dart              # abstract final FeatureFlags: compile-time тогглы
    └── formatters/
        ├── value_formatter.dart        # @lazySingleton: locale-aware форматирование чисел (intl)
        └── date_formatter.dart         # static DateFormat-хелперы (short / time)
```

Архитектурное решение по темизации в NOX — **generated-handoff поверх Material 3 + точечное `ThemeExtension`-расширение**:

- **Палитра и типографика — не «семя» (`seed`), а явные сгенерированные схемы.** `AppTheme` собирает `ThemeData` из готового `const ColorScheme` (`noxLightScheme`/`noxDarkScheme` в `nox_color_scheme.dart`) и `const TextTheme` (`noxTextTheme` в `nox_text_theme.dart`) — оба генерируются из токенов NOX (`docs/design/system/nox-handoff/tokens`). Это **не** `ColorScheme.fromSeed`: роли вручную дотюнены под бренд (seed-teal `Color(0xFF12B4B4)` использовался только как отправная точка генерации; финальные роли — точные значения из токенов). См. §1.
- **Семантические доп-роли, которых нет в стоковом `ColorScheme`,** живут в `ThemeExtension<AppColors>` (`app_colors.dart`) и читаются через `context.appColors`. См. §2.
- **Не-цветовые измерения** (отзывчивые отступы, текстовые фабрики, overlay-стили, пути ассетов) — статические классы-токены `App*Tokens`. См. §4–§7.
- **Generated non-color токены** (фиксированные dp-сетки spacing/radius/elevation + длительности/кривые анимаций) — `nox_tokens.dart`; брендовые фикс-цвета и логика аватаров — `nox_brand.dart`. См. §1.1 и §4.1.

> **Где живёт цвет.** Два канала: (1) **роли M3** — `Theme.of(context).colorScheme.primary/surface/...` (приходят из сгенерированного `noxLightScheme`/`noxDarkScheme`); (2) **семантические доп-роли NOX** — `context.appColors.xxx` (`AppColors`-расширение темы). Сырые `Color`-литералы в коде фич запрещены — они объявляются **только** внутри сгенерированных файлов темы (`nox_*.dart`), `app_colors.dart` (skeleton-литералы доп-ролей) и файлов токенов (`app_overlay_style_tokens.dart` с его `const Color`-литералами). Брендовые фикс-цвета (splash-фон, QR-поверхность) — отдельный случай, см. §1.1.

> **Замечание по `lib/design/gen/` (flutter_gen).** Пути к картиночным ассетам **генерируются** `flutter_gen_runner` (см. `01-stack-and-tooling.md`) в `lib/design/gen/assets.gen.dart` — type-safe аксессоры `Assets.png/.svg/.animation`. Файл исключён из анализатора, **gitignored** (`.gitignore` → `lib/design/gen/`) и регенерится `build_runner`. Блок `flutter_gen:` в `pubspec.yaml` (`output: lib/design/gen/`, `flutter_svg: true`, `fonts.enabled: false`, `line_length: 140`) задаёт его конфиг. Это **единственный** канал путей к ассетам: рукописный `AppImagesTokens` удалён, а семантику иконок несёт `NoxIcons` (§7).

---

## 1. Источник цвета и типографики — сгенерированный handoff (`nox_color_scheme.dart` / `nox_text_theme.dart`)

В NOX палитра и типографика **не выводятся из seed** в рантайме — они приходят готовыми из сгенерированных, git-tracked файлов, которые являются Dart-проекцией токенов дизайн-системы. Это даёт точное попадание в роли M3, заданные дизайном, и убирает любую неоднозначность алгоритма `fromSeed`.

**Файл (генерируется из `docs/design/system/nox-handoff/tokens/color.{light,dark}.tokens.json`, НЕ редактировать руками):** `lib/design/theme/nox_color_scheme.dart`

```dart
// GENERATED — NOX design tokens → Flutter ColorScheme.
// Source of truth: tokens/color.{light,dark}.tokens.json.
// Seed: Color(0xFF12B4B4) (brand teal). Roles are hand-tuned — use these
// explicit schemes rather than ColorScheme.fromSeed for an exact match.
import 'package:flutter/material.dart';

const ColorScheme noxLightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF006A6A),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFF6FF7F6),
  // … все роли M3 заданы явно (secondary*, tertiary*, error*, surface*, outline*, …)
  surface: Color(0xFFF4FBFA),
  onSurface: Color(0xFF161D1D),
  secondaryContainer: Color(0xFFCCE8E7),
  onSecondaryContainer: Color(0xFF051F1F),
);

const ColorScheme noxDarkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF4CDADA),
  // … зеркальный набор ролей для тёмной темы
  surface: Color(0xFF0E1514),
  onSurface: Color(0xFFDDE4E3),
);
```

**Файл (генерируется из `tokens/typography.tokens.json`, НЕ редактировать руками):** `lib/design/theme/nox_text_theme.dart`

```dart
// GENERATED — NOX M3 type scale → Flutter TextTheme.
// Source: tokens/typography.tokens.json. height = lineHeightPx / fontSize.
import 'package:flutter/material.dart';

const String _sans = 'Roboto';
const String noxMonoFamily = 'Roboto Mono'; // ID string only — для моноширинных мест (ID/ключи)

const TextTheme noxTextTheme = TextTheme(
  displaySmall: TextStyle(fontFamily: _sans, fontSize: 36, height: 1.222, fontWeight: FontWeight.w400), // 36/44
  titleLarge:   TextStyle(fontFamily: _sans, fontSize: 22, height: 1.273, fontWeight: FontWeight.w400), // 22/28
  titleMedium:  TextStyle(fontFamily: _sans, fontSize: 16, height: 1.500, fontWeight: FontWeight.w500), // 16/24
  bodyLarge:    TextStyle(fontFamily: _sans, fontSize: 16, height: 1.500, fontWeight: FontWeight.w400), // 16/24
  bodyMedium:   TextStyle(fontFamily: _sans, fontSize: 14, height: 1.429, fontWeight: FontWeight.w400), // 14/20
  labelLarge:   TextStyle(fontFamily: _sans, fontSize: 14, height: 1.429, fontWeight: FontWeight.w500), // 14/20
  labelMedium:  TextStyle(fontFamily: _sans, fontSize: 12, height: 1.333, fontWeight: FontWeight.w500), // 12/16
  // … полный M3-набор слотов
);
```

Семейство шрифтов — `Roboto` (sans, начертания 400/500/700) и `Roboto Mono` (моноширинный 400, для отображения ID/ключей); оба **забандлены** в `assets/fonts/` и объявлены в `pubspec.yaml` (`fonts:`), поэтому рендерятся одинаково на всех пяти платформах. `height` в каждом стиле — безразмерный множитель `lineHeightPx / fontSize` (так типографика приходит из дизайна без отдельного скейла высоты).

> **Почему не `ColorScheme.fromSeed`.** `fromSeed` детерминирован, но его алгоритм Material You может разойтись с конкретными ролями, заданными дизайнером NOX. Поэтому генерируется **полный явный** `ColorScheme` — каждая роль точно равна токену. Seed-teal `0xFF12B4B4` остаётся брендовой константой (см. `nox_brand.dart`, §1.1), но участвует лишь как отправная точка при генерации, а не как рантайм-источник схемы.

### 1.1 Брендовые фикс-цвета и аватары — `nox_brand.dart`

Часть цветов NOX **не зависит от темы** и живёт **вне** `ColorScheme` — это продуктовые константы, зафиксированные дизайном. `nox_brand.dart` генерируется из `tokens/brand.tokens.json` + `tokens/avatars.tokens.json`.

**Файл (генерируется, НЕ редактировать руками):** `lib/design/theme/nox_brand.dart`

```dart
abstract final class NoxBrand {
  static const Color teal = Color(0xFF12B4B4);       // бренд-акцент / seed
  static const Color tealDeep = Color(0xFF0E7C7C);
  static const Color gold = Color(0xFFF4C20C);
  static const Color canvasDark = Color(0xFF0C2424); // splash-фон ВСЕГДА тёмный
  static const Color ink = Color(0xFF0C0C0C);
  static const Color qrSurface = Color(0xFFFFFFFF);  // QR-поверхность ВСЕГДА светлая
  static const Color qrInk = Color(0xFF0C0C0C);
  // … gold/amber/coral/red/lime/blue/white — палитра бренда
}

/// Generated-avatar backgrounds (avatar-only). Initials are always white.
const List<Color> noxAvatarPalette = [/* 8 цветов */];

/// Deterministic palette index from a name: h = (h*31 + charCode) >>> 0; h % 8.
Color noxAvatarColor(String name) => noxAvatarPalette[noxAvatarIndex(name)];

/// 1–2 инициала из имени (null → caller показывает glyph-фолбэк `forum`).
String? noxInitials(String name) { /* … */ }
```

Две **продуктовые** исключения из темы (см. CLAUDE.md, NOX product model):

- **Splash-фон всегда тёмный** — рисуется на `NoxBrand.canvasDark`, независимо от `themeMode`.
- **QR-поверхность всегда светлая** — `NoxBrand.qrSurface` / `NoxBrand.qrInk`, чтобы QR гарантированно сканировался при любой теме.

Кроме того `nox_brand.dart` несёт **генерацию аватаров чатов**: `noxAvatarColor(name)` детерминированно выбирает цвет из 8-цветовой палитры по хэшу имени, `noxInitials(name)` строит 1–2 инициала (инициалы всегда белые). Это реализует продуктовое решение NOX «аватары генерируются: инициалы + цвет по хэшу из фиксированной палитры».

---

## 2. Семантические доп-роли — `ThemeExtension<AppColors>`

Стоковый M3 `ColorScheme` покрывает большинство цветовых нужд, но NOX-у нужны **дополнительные семантические роли**, которых в `ColorScheme` нет (например, приглушённая поверхность списка или тонкий разделитель с конкретным дизайн-значением). Их несёт `ThemeExtension<AppColors>` — типизированное, зависящее от режима расширение `ThemeData`, прицепленное к обеим темам.

Паттерн состоит из пяти частей в одном файле:

1. `@immutable AppColors extends ThemeExtension<AppColors>` со всеми семантическими `Color`-полями и `const`-конструктором.
2. `copyWith()` — переопределяет отдельные цвета (требуется контрактом `ThemeExtension`).
3. `lerp()` — интерполирует между светлой/тёмной при анимации смены темы (требуется контрактом). **Каждое поле должно быть пролерплено**, иначе анимация смены темы выглядит сломанной.
4. Подклассы `LightAppColors` / `DarkAppColors` с конкретными значениями для каждого режима через `super(...)`.
5. Расширение `BuildContext`, чтобы виджеты читали роли как `context.appColors.xxx`.

**Файл (skeleton — текущее состояние):** `lib/design/theme/app_colors.dart`

```dart
import 'package:flutter/material.dart';

/// Semantic, mode-dependent colors layered on top of the M3 ColorScheme via
/// ThemeExtension. Raw Color literals are allowed ONLY in this theme file.
/// Skeleton uses a minimal set; the full token-driven palette (from
/// docs/design/system/nox-handoff/) lands in US4.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({required this.surfaceMuted, required this.dividerSubtle});

  final Color surfaceMuted;
  final Color dividerSubtle;

  @override
  AppColors copyWith({Color? surfaceMuted, Color? dividerSubtle}) {
    return AppColors(surfaceMuted: surfaceMuted ?? this.surfaceMuted, dividerSubtle: dividerSubtle ?? this.dividerSubtle);
  }

  /// Linear interpolation between two color sets (theme transitions).
  /// IMPORTANT: lerp EVERY field, or animated theme changes will look wrong.
  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      dividerSubtle: Color.lerp(dividerSubtle, other.dividerSubtle, t)!,
    );
  }
}

class LightAppColors extends AppColors {
  const LightAppColors() : super(surfaceMuted: const Color(0xFFF2F2F2), dividerSubtle: const Color(0xFFBDBDBD));
}

class DarkAppColors extends AppColors {
  const DarkAppColors() : super(surfaceMuted: const Color(0xFF2D2D2D), dividerSubtle: const Color(0xFF000000));
}

/// Read semantic roles anywhere: `context.appColors.surfaceMuted`.
/// The `!` is INTENTIONAL: if the extension is missing, that is a wiring bug
/// (you forgot to register it in AppTheme) and must fail loudly, not silently.
extension AppColorsExtension on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}
```

> **Состояние и план.** Текущий `AppColors` — намеренный **skeleton** с двумя полями (`surfaceMuted`, `dividerSubtle`) и raw-`Color`-литералами прямо в `Light/DarkAppColors`. Полный семантический набор доп-ролей, выведенный из `docs/design/system/nox-handoff/`, **прилетает в US4** (отмечено в комментарии кода). До тех пор большинство цветов берётся из стокового `ColorScheme` (`Theme.of(context).colorScheme`), а `AppColors` покрывает только то, чего в нём нет.

Для новой семантической роли добавляйте поле в `AppColors`, соответствующий параметр `copyWith`, строку в `lerp` и значения в `super(...)` обоих подклассов — **все четыре места в едином шаге**. Пропуск любого ломает либо компиляцию, либо анимацию темы. Регистрация в `ThemeData` — через `extensions:` (см. §3).

---

## 3. Сборка темы — `AppTheme`

Один класс с приватным конструктором строит `light()` и `dark()` `ThemeData` через общий приватный `_build`. Каждая тема стартует от Material 3 базы (`useMaterial3: true`), берёт сгенерированный `ColorScheme` (§1) и `TextTheme` (§1), задаёт `scaffoldBackgroundColor` из `scheme.surface` и **регистрирует** соответствующий вариант `AppColors` (§2) через `extensions: [...]`.

**Файл:** `lib/design/theme/app_theme.dart`

```dart
import 'package:flutter/material.dart';
import 'package:nox_app/design/theme/app_colors.dart';
import 'package:nox_app/design/theme/nox_color_scheme.dart';
import 'package:nox_app/design/theme/nox_text_theme.dart';

/// NOX Material 3 theme. The `ColorScheme` and `TextTheme` come from the
/// token-generated design-system handoff (`lib/design/theme/nox_*.dart`,
/// regenerated from `docs/design/system/nox-handoff/tokens` — never hand-edited),
/// so the palette is the hand-tuned NOX teal scheme, not a raw `fromSeed`.
/// Semantic, mode-dependent extras ride along via the AppColors ThemeExtension.
class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(noxLightScheme, const LightAppColors());

  static ThemeData dark() => _build(noxDarkScheme, const DarkAppColors());

  static ThemeData _build(ColorScheme scheme, AppColors appColors) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: noxTextTheme,
      scaffoldBackgroundColor: scheme.surface,
      extensions: <ThemeExtension<dynamic>>[appColors],
    );
  }
}
```

Правило синхронности светлой и тёмной темы: каждое кастомное `ThemeExtension` регистрируется в **обоих** методах (`Light*` в `light()`, `Dark*` в `dark()`). Забыть один вариант — значит получить рантайм-исключение `context.appColors` в этом режиме (из-за намеренного `!`, §2).

> **Инвариант кросс-платформенной темы.** Единая Material 3 тема из одного teal-seed на всех 5 платформах (iOS, Android, Windows, Linux, macOS); `yaru` / платформенные desktop-темы НЕ используются. (Источник схемы — сгенерированные `noxLightScheme`/`noxDarkScheme` из `nox-handoff`, общие для всех таргетов.)

> **Цвета desktop `NavigationRail`.** Selected-indicator и labels десктопного `NavigationRail` берутся из стокового M3 `ColorScheme` (`secondaryContainer` / `onSecondaryContainer`) — новой роли в `AppColors` не нужно.

> **Переходы между экранами.** Если на каком-то таргете нужен платформенно-нативный жест перехода (Cupertino на iOS/Android), его задают через `pageTransitionsTheme` с `PageTransitionsTheme(builders: {TargetPlatform.iOS: CupertinoPageTransitionsBuilder(), TargetPlatform.android: CupertinoPageTransitionsBuilder()})`. В скелете `_build` его пока не задаёт (стоковые M3-переходы) — добавляется при первой навигируемой фиче. Ключи `TargetPlatform.iOS/.android` относятся только к жестам перехода и не сужают scope: тема и приложение покрывают все 5 платформ.

### 3.1 Потребление в `MaterialApp`

Полная сборка root-виджета — в `05-presentation-layer.md`. `AppRootBloc` (он же app-level BLoC) держит `themeMode` в своём состоянии — это канонический пример **минимального value-BLoC** (одно поле, одно состояние); тот же паттерн применяется к любой logic-less навигируемой странице (Инвариант 3a: у неё всё равно свой минимальный BLoC; переиспользуемые виджеты `lib/presentation/widgets/` BLoC не требуют). `MaterialApp` читает обе темы статически и переключается реактивно:

```dart
BlocBuilder<AppRootBloc, AppRootState>(
  builder: (context, state) {
    return MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: state.themeMode, // ThemeMode.system / light / dark — из AppRootBloc
      // ...
    );
  },
);
```

> **Перекрёстная ссылка.** `AppRootState` — это **одновариантный** `@freezed`-value-объект с единственным полем `themeMode` (НЕ трио `Initializing`/`Initialized`/`Error` — те подсостояния относятся к фичевым BLoC, не к app-level; см. `05-presentation-layer.md`). `MaterialApp` читает `state.themeMode` напрямую (никогда `state.theme`). Само переключение темы инициируется событием (`AppRootEvent.setTheme(...)` / эквивалент), персистится через настройки и эмиттится в новое состояние через `copyWith`.
>
> **Дивергенция со скелетом.** В текущем скелете `AppShell` своего BLoC не имеет, а placeholder-страницы — stateless. Это допустимые упрощения скелета до прихода реальных фич; целевая норма (свой BLoC у каждого навигируемого `*Page`) — Инвариант 3a.

---

### 3.2 UI-скейл — `ScreenUtilInit` в корне (дизайн-канва + нейтрализация OS-шрифта)

**Цель.** Приложение должно выглядеть **плюс-минус одинаково** на всём парке устройств с разным физическим размером и разрешением экрана. Решение: единый **дизайн-скейл** (`flutter_screenutil`), от которого выводятся размеры в классах-токенах — отступы (`AppSpacingTokens`, §4) и шрифты (`AppTextStyleTokens`, §5). Никаких «магических» числовых литералов размеров в коде фич.

**Дизайн-канва.** `Constants.designSize = Size(360, 779)` (`lib/general/constants.dart`, §8.1) — это размер макета, в котором дизайн нарисован. `ScreenUtil` сравнивает реальный экран с канвой и даёт факторы `scaleWidth = deviceWidth / 360`, `scaleHeight = deviceHeight / 779` (и производный `scaleText`).

**Настройка в корне** (`AppRoot`, полный код — в [05-presentation-layer.md](05-presentation-layer.md) §6.2). `MaterialApp` оборачивается так:

```dart
MediaQuery(                                          // (1) снаружи: убираем OS-масштаб шрифта
  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
  child: ScreenUtilInit(                             // (2) инициализируем глобальный ScreenUtil
    designSize: Constants.designSize,                //     Size(360, 779)
    minTextAdapt: true,                              //     текст адаптируется по меньшему фактору
    builder: (context, child) => MaterialApp(
      // theme / darkTheme / themeMode / onGenerateRoute ...
      builder: (context, child) => MediaQuery(       // (3) внутри: повторно пиним textScaler = 1.0
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  ),
)
```

Зачем **двойной** `MediaQuery`:

- **(1) внешний `TextScaler.noScaling`** — отключает системную настройку «размер шрифта» (OS accessibility) для всего поддерева: размер текста задаёт только наш дизайн-скейл, а не ОС. Без этого пользователь с крупным системным шрифтом ломал бы вёрстку.
- **(3) внутренний `TextScaler.linear(1.0)`** — `MaterialApp` переустанавливает `MediaQuery` для своего поддерева, поэтому масштаб `1.0` пинится ещё раз уже **внутри** `MaterialApp.builder`, чтобы OS-масштаб не «вернулся» ни на одном экране.
- **`minTextAdapt: true`** — заставляет `ScreenUtil().scaleText` брать меньший из факторов width/height (а не только width), чтобы текст не раздувался на узких/высоких экранах.

**Два источника скейла** (умышленно разные):

| Токены | Источник `_scale` | Почему так |
|---|---|---|
| `AppSpacingTokens.sN` (§4) | `(1.w + 1.h) / 2` — **среднее** факторов width и height | отступы/размеры контейнеров масштабируются сбалансированно по обеим осям |
| `AppTextStyleTokens` (§5) | `.sp` (учитывает `minTextAdapt`) | типографика масштабируется консервативнее, по меньшему фактору |

> **Важно.** `_scale` валиден только **после** того, как `ScreenUtilInit` отработал в дереве, поэтому к `AppSpacingTokens.sN` / `AppTextStyleTokens.xxx()` обращаются только внутри `build`-методов под `AppRoot` — никогда в top-level `static`-инициализаторах или до `runApp`. Поэтому токен-классы используют **геттеры** (`static double get sN`), а не `static const`-поля.

> **Версия и границы.** `flutter_screenutil: 5.9.3` (пин в `01-stack-and-tooling.md`). `splitScreenMode` не используется (дефолт `false`). `.sp` / `.w` / `.h` / `.r`-extension'ы пакета в **коде фич** (`lib/presentation/`) **не применяются** — единственный канал размеров — токены `App*Tokens`. При этом **сами классы-токены** легитимно используют `.w`/`.h`/`.sp` внутри себя (это и есть единая точка скейла), как и видно в коде §4–§5. Правило «только токены» — §9.

> **Высота строки и скейл.** `height` в `TextStyle` — безразмерный множитель от `fontSize`, поэтому он масштабируется опосредованно (вместе с `fontSize`) и **сам на `_scale` не умножается** — иначе высота строки скейлилась бы квадратично. Сгенерированный `noxTextTheme` (§1) уже задаёт корректные `height` как отношение `lineHeightPx / fontSize`; фабрики `AppTextStyleTokens` (§5) `height` вовсе не задают.

---

## 4. Дизайн-токены — отзывчивые отступы (`AppSpacingTokens`)

Токены отступов — **отзывчивый `sN`-масштаб**: каждое значение умножается на `_scale`, выведенный из `flutter_screenutil` (среднее `1.w` и `1.h`; полный механизм скейла — §3.2). Это даёт пропорциональные отступы на разных размерах экранов при дизайн-размере `360x779`. Именование: `sN`, где `N` — базовое пиксельное значение. Все `EdgeInsets`/`SizedBox`/`gap` в коде фич ссылаются на токен, а не на литерал. Класс — `abstract final class` с приватным `const`-конструктором и **геттерами** (значения вычисляются лениво при каждом обращении, уже после `ScreenUtilInit`).

**Файл:** `lib/design/app_spacing_tokens.dart`

```dart
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Responsive spacing scale. Each step is the design-px value scaled by
/// flutter_screenutil (`.w`/`.h`), so it adapts to device width.
abstract final class AppSpacingTokens {
  const AppSpacingTokens._();

  // Mean of width/height scale factors, so spacing stays balanced on extreme
  // aspect ratios (desktop/landscape), not just width-driven (blueprint 06 §4).
  static double get _scale => (1.w + 1.h) / 2;

  static double get s4 => 4 * _scale;
  static double get s8 => 8 * _scale;
  static double get s12 => 12 * _scale;
  static double get s16 => 16 * _scale;
  static double get s24 => 24 * _scale;
  static double get s28 => 28 * _scale;
  static double get s32 => 32 * _scale;
}
```

Использование:

```dart
Padding(
  padding: EdgeInsets.all(AppSpacingTokens.s16),
  child: SizedBox(height: AppSpacingTokens.s32),
);
```

> Текущий набор намеренно узкий (`s4`..`s32`). Шаги добавляются по мере появления реальных макетов — не «про запас».

### 4.1 Generated non-color токены — `nox_tokens.dart`

Параллельно `App*Tokens` существует сгенерированный из дизайн-токенов набор **фиксированных (не-скейленных)** не-цветовых констант — `nox_tokens.dart`. Они генерируются из `tokens/{spacing,shape,elevation,motion}.tokens.json` и **не редактируются руками**.

**Файл (генерируется, НЕ редактировать руками):** `lib/design/theme/nox_tokens.dart`

```dart
/// 4dp base grid. Min tap-target 48.
abstract final class NoxSpacing {
  static const double s1 = 4;  static const double s2 = 8;  static const double s3 = 12;
  static const double s4 = 16; // screen horizontal padding
  static const double s6 = 24; static const double s8 = 32;
  static const double screenPadding = 16;
  static const double minTapTarget = 48;
}

/// Corner radii. `full` → StadiumBorder / circle.
abstract final class NoxRadius {
  static const double none = 0, xs = 4, s = 8, m = 12, l = 16, xl = 28, full = 999;

  /// Message bubble: base l(16); the "own" bottom-right / "other" bottom-left
  /// corner clips to xs(4) — asymmetry instead of a tail.
  static BorderRadius bubble({required bool isOwn}) => BorderRadius.only(
    topLeft: const Radius.circular(l),
    topRight: const Radius.circular(l),
    bottomLeft: Radius.circular(isOwn ? l : xs),
    bottomRight: Radius.circular(isOwn ? xs : l),
  );
}

abstract final class NoxElevation { /* level0..level5 — M3 tonal dp */ }
abstract final class NoxDuration  { /* splashIn / push / tabFade / snackbarIn/Out / sheet */ }
abstract final class NoxEasing    { /* standard / emphasized / emphasizedDecelerate */ }
```

`NoxRadius.bubble({required bool isOwn})` — NOX-специфика: бабл сообщения скругляется ассиметрично (нижний правый угол у своих, нижний левый у чужих клипуется до `xs`) вместо «хвостика». `NoxDuration`/`NoxEasing` — M3-длительности и кривые (splash — one-shot, без зацикленных анимаций).

> **`NoxSpacing` (фиксированные dp) vs `AppSpacingTokens` (отзывчивые `.w/.h`) — два параллельных набора.** `NoxSpacing` несёт «сырые» дизайн-значения на 4dp-сетке (плюс семантику `screenPadding`/`minTapTarget`), `AppSpacingTokens` — те же шаги, но домноженные на `_scale` для адаптива. В коде фич канонический отступной канал — `AppSpacingTokens` (адаптив). `NoxSpacing` уместен для контекстов, где скейл нежелателен (например, `minTapTarget` — гарантированные 48dp). Эта дубликация (одни и те же базовые шаги в двух классах) — **точка, которую нужно свести** при разрастании UI; до тех пор выбирайте по правилу выше. Радиусы/elevation/motion-токены конфликта не имеют — они только в `nox_tokens.dart`.

---

## 5. Дизайн-токены — текстовые стили (`AppTextStyleTokens`)

Канонический type scale NOX — это сгенерированный `noxTextTheme` (§1), доступный через `Theme.of(context).textTheme.*` (`bodyMedium`, `titleMedium`, …). `AppTextStyleTokens` — **фабрики цвето-инъекции** поверх него: по фабрике на каждую из 8 ролей M3-шкалы (`displaySmall`, `headlineSmall`, `titleLarge`, `titleMedium`, `bodyLarge`, `bodyMedium`, `labelLarge`, `labelMedium`), где удобнее задать цвет на месте вызова: каждый метод принимает обязательный `Color color` и масштабирует `fontSize` через `.sp` (учитывает `minTextAdapt`, §3.2). Цвет не зашит в стиль — он передаётся на месте вызова (обычно из `context.appColors.xxx` или `Theme.of(context).colorScheme.*`), что делает стиль независимым от темы. Класс — `abstract final class` с приватным `const`-конструктором.

**Файл:** `lib/design/app_text_style_tokens.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Full M3 type scale (8 roles) as color-injecting factories — no `height`
/// (comes from noxTextTheme), no `fontFamily` (inherited from the theme).
abstract final class AppTextStyleTokens {
  const AppTextStyleTokens._();

  static TextStyle displaySmall({required Color color}) => TextStyle(fontSize: 36.sp, fontWeight: FontWeight.w400, color: color);
  static TextStyle headlineSmall({required Color color}) => TextStyle(fontSize: 24.sp, fontWeight: FontWeight.w400, color: color);
  static TextStyle titleLarge({required Color color}) => TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w400, color: color);
  static TextStyle titleMedium({required Color color}) => TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w500, color: color);
  static TextStyle bodyLarge({required Color color}) => TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w400, color: color);
  static TextStyle bodyMedium({required Color color}) => TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w400, color: color);
  static TextStyle labelLarge({required Color color}) => TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500, color: color);
  static TextStyle labelMedium({required Color color}) => TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500, color: color);
}
```

Использование:

```dart
Text(item.displayName, style: AppTextStyleTokens.bodyMedium(color: context.appColors.surfaceMuted));

// Канонический type scale напрямую из темы:
Text(item.displayName, style: Theme.of(context).textTheme.bodyMedium);
```

> **Семейства шрифтов.** Реальная типографика NOX — `Roboto` (sans) и `Roboto Mono` (моноширинный, для ID/ключей) — приходит из сгенерированного `noxTextTheme` (§1). Фабрики `AppTextStyleTokens` семейство явно не задают (наследуют дефолт темы); для моноширинных мест используйте слот темы либо `fontFamily: noxMonoFamily` из `nox_text_theme.dart`. Семейства **забандлены** (`Roboto` 400/500/700 + `Roboto Mono` 400) в секции `fonts:` `pubspec.yaml` — см. `01-stack-and-tooling.md`.
>
> **План.** Набор покрывает все 8 ролей `noxTextTheme`; дополнительные хелперы (`extension on TextStyle` с `withMonospace`/`withPrimaryColor` и т.п.) добавляются при появлении реальной потребности.

---

## 6. Дизайн-токены — overlay-стили (`AppOverlayStyleTokens`)

Класс токенов системного overlay — `static const SystemUiOverlayStyle` под светлый и тёмный режим. Сырой `SystemUiOverlayStyle` в коде фич запрещён — задавайте overlay только через эти константы; канон их применения (глобально в `AppRoot` по текущему `Brightness`; per-screen `AnnotatedRegion` — только как исключение) описан ниже в §6.1. Класс — `abstract final class` с приватным `const`-конструктором.

**Файл:** `lib/design/app_overlay_style_tokens.dart`

```dart
import 'package:flutter/services.dart';

/// System UI overlay (status bar) styles per brightness.
abstract final class AppOverlayStyleTokens {
  const AppOverlayStyleTokens._();

  static const SystemUiOverlayStyle light = SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  );

  static const SystemUiOverlayStyle dark = SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  );
}
```

> **Только статус-бар.** Токены задают **только** поля статус-бара (`statusBarColor`/`statusBarIconBrightness`/`statusBarBrightness`); поля системного нав-бара (`systemNavigationBarColor`/`systemNavigationBarIconBrightness`) намеренно опущены — системный навбар есть только на Android, а scope NOX — 5 платформ. При необходимости Android-специфичной настройки навбара её добавляют точечно.

### 6.1 Где применять `dark`/`light` — единый канон

**Канон (единственный источник истины): overlay применяется глобально в `AppRoot` по текущему `Brightness`.** `AppRoot` (корневой `MaterialApp`, см. [05-presentation-layer.md](05-presentation-layer.md) §6.2) — единственное место, где overlay-стиль ставится по умолчанию: при сборке дерева выбирается `AppOverlayStyleTokens.dark` или `AppOverlayStyleTokens.light` в зависимости от текущей яркости (`MediaQuery.platformBrightnessOf(context)` либо `themeMode`-производный `Brightness`), и применяется через `SystemChrome.setSystemUIOverlayStyle(...)`. Так статус-бар согласован с активной темой на всех экранах без дублирования в каждом виджете.

**Per-screen `AnnotatedRegion<SystemUiOverlayStyle>` — задокументированное исключение, не правило.** Оборачивать отдельный экран в `AnnotatedRegion` допустимо **только** тогда, когда экран осознанно переопределяет яркость относительно темы приложения — например, полноэкранная поверхность с фиксированным тёмным фоном независимо от светлой темы (ср. splash на `NoxBrand.canvasDark`, §1.1). Вне таких случаев overlay в коде фич не задаётся: глобальный канон `AppRoot` уже всё покрывает. Это держит «один источник истины» для системного overlay и убирает рассинхрон между экранами.

---

## 7. Картиночные ассеты — `assets.gen.dart` (flutter_gen) и `NoxIcons`

Единственный канал доступа к путям ассетов — **`flutter_gen`**. `flutter_gen_runner` генерирует `lib/design/gen/assets.gen.dart` — type-safe аксессоры `Assets.png`/`Assets.svg`/`Assets.animation` из реальных файлов под `assets/`. Файл **gitignored** (`.gitignore` → `lib/design/gen/`), исключён из анализатора и регенерится `build_runner`. Конфиг — блок `flutter_gen:` в `pubspec.yaml` (`output: lib/design/gen/`, `flutter_svg: true`, `fonts.enabled: false`, `line_length: 140`). PNG рендерится `Image.asset`/`AssetGenImage`; SVG — через `flutter_svg` (`.svg()`). Рукописного `AppImagesTokens` больше нет — сырые строки путей в коде фич запрещены.

**Забандленные наборы (`assets/`, перечислены в `pubspec.yaml::flutter.assets`):**

- `assets/svg/icons/` — 37 SVG Material Symbols Rounded (`currentColor`); семантический доступ — `NoxIcons` (§7.1).
- `assets/svg/illustrations/` — 3 плейсхолдера пустых состояний (`Assets.svg.illustrations.emptyChats` / `.emptyMessages` / `.emptyFiles`).
- `assets/png/logo.png` — бренд-логотип (растровый плейсхолдер, splash) — `Assets.png.logo`.
- `assets/fonts/*.ttf` — `Roboto` 400/500/700 + `Roboto Mono` 400 (объявлены в `fonts:`, см. §1/§5).

### 7.1 Семантический icon-реестр — `NoxIcons`

**Файл (рукописный):** `lib/design/nox_icons.dart`. `abstract final class NoxIcons` с именованными геттерами, **ссылающимися** на flutter_gen-аксессоры `Assets.svg.icons.*` (без сырых строк путей). Несёт семантику и ось FILL из `nox-assets/icons/icons.json`: outlined/filled — это `name.svg` / `name-fill.svg` (`forum`/`forumFill`, `settings`/`settingsFill`, `sendFill`, `flashlightOnFill`/`flashlightOff`, …). Покрывает 35 используемых глифов; 2 забандленных-но-неиспользуемых outlined-варианта (`flashlight_on.svg`, `send.svg` — их единственная используемая форма — filled) доступны через `Assets.svg.icons.*`, но в реестр не входят. Иконки перекрашиваются цветом темы на месте вызова (`currentColor`, цвет не зашит):

```dart
NoxIcons.forum.svg(colorFilter: ColorFilter.mode(cs.onSurfaceVariant, BlendMode.srcIn));
```

> **Pending-ассеты (вне scope сейчас).** По `nox-assets/manifest.json` ещё не произведены: финальный вектор логотипа (SVG, full-color на тёмном), launcher app-icon, финальные иллюстрации пустых состояний. Заведены существующие плейсхолдеры; финалы заменяются точечно при поступлении ордеров.

---

## 8. Поддерживающий слой `lib/general/`

Вспомогательные синглтоны и утилиты, не относящиеся ни к одному конкретному экрану. Все классы-токены и утилиты здесь имеют **явный приватный конструктор `._()`** — они никогда не инстанцируются, доступ только статический (кроме `@lazySingleton ValueFormatter`, который резолвится через `getIt`).

### 8.1 Constants

`final class` с приватным конструктором: конфиг приложения, UI-дефолты и regex-валидаторы как `static const` / `static final`.

**Файл:** `lib/general/constants.dart`

```dart
import 'dart:ui';

/// App-wide constants. Never instantiated — access members statically.
final class Constants {
  Constants._();

  /// General config
  static const databaseName = 'nox_app_db';
  static const defaultLocale = 'en_US';

  /// UI
  static const defaultNavTransitionTimeMilliseconds = 300;
  static const preventDoubleNavDelayMilliseconds = 300;
  static const designSize = Size(360, 779); // flutter_screenutil reference
  static const double railBreakpoint = 840; // M3 medium->expanded; bottom-bar <-> NavigationRail

  /// Validation patterns (compile once as static final RegExp)
  static final emailRegex = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@"
    r"[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?"
    r"(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$",
  );
  static final phoneRegex = RegExp(r'^\+?[0-9]{7,15}$');
}
```

> **`railBreakpoint` — единственный источник истины для брейкпоинта оболочки.** `Constants.railBreakpoint = 840` (M3-граница medium→expanded) — единственная точка, по которой оболочка переключается между нижним баром (`bottom-bar`) и боковым `NavigationRail`. Значение совпадает с desktop-классом окна expanded (любое десктоп-окно `≥ 840dp` попадает в expanded; FUTURE-канвас `1440×900` — тоже expanded), так что один и тот же порог обслуживает и адаптивную мобильную раскладку, и десктоп.

### 8.2 PlatformUtils

Оборачивает проверки `dart:io` `Platform` за маленьким статическим хелпером — платформенное ветвление централизовано и легко грепается. На мобильных таргетах основной путь — `isMobile`; десктоп-геттеры (`isDesktop` / `isMacOS` / …) используются на десктопных таргетах (Windows/Linux/macOS), которые входят в scope (конституция v1.1.0).

**Файл:** `lib/general/platform_utils.dart`

```dart
import 'dart:io';

/// Platform detection helpers. Centralizes dart:io Platform checks.
class PlatformUtils {
  PlatformUtils._();

  static bool get isMobile => Platform.isAndroid || Platform.isIOS;
  static bool get isDesktop => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  static bool get isAndroid => Platform.isAndroid;
  static bool get isIOS => Platform.isIOS;
  static bool get isMacOS => Platform.isMacOS;
}
```

> Для ветвления по конкретной desktop-ОС добавляйте `Platform.isWindows` / `Platform.isLinux` по месту (в скелете явные геттеры заведены под `isMacOS`; `isWindows`/`isLinux` добавляются с первым их потребителем).

### 8.3 UI-микрокопи и фиче-флаги

#### 8.3.0 TextConstants — единый источник UI-строк (English)

Вся пользовательская микрокопи держится в одном `abstract final class` — никаких строковых литералов копи в виджетах. Класс **migration-ready** под ARB + `flutter_localizations` (отдельная i18n-фича). По языковой дисциплине NOX UI-строки — **English** даже в этом русскоязычном документе (языки приложения — English + Ukrainian; русский UI-языком не бывает).

**Файл:** `lib/general/text_constants.dart`

```dart
/// All user-facing strings (English). No literal copy in widgets.
/// Migration-ready for ARB + flutter_localizations (separate i18n feature).
abstract final class TextConstants {
  const TextConstants._();

  static const String appName = 'NOX';

  // App shell destinations (FR-004)
  static const String chats = 'Chats';
  static const String settings = 'Settings';

  // Generic states
  static const String errorGeneralTitle = 'Something went wrong';
  static const String actionTryAgain = 'Try again';
  static const String noData = 'Nothing here yet';
  static const String comingSoon = 'Coming soon';
}
```

`chats`/`settings` — лейблы двух destination'ов оболочки NOX (нижний бар / `NavigationRail`), профиля-экрана нет (см. NOX product model).

#### 8.3.1 FeatureFlags — compile-time тогглы

Короткоживущие compile-/config-time флаги; держать аддитивными и не накапливать.

**Файл:** `lib/general/feature_flags.dart`

```dart
/// Compile-time / config-time feature toggles. Keep flags additive and short-lived.
abstract final class FeatureFlags {
  const FeatureFlags._();

  static const bool enableSearch = true;

  static const bool enablePullToRefresh = true;
}
```

### 8.4 Форматтеры

Два вида:

- **Stateful, DI-зарегистрированный** (`@lazySingleton`): форматирует числа с учётом локали. Резолвится через `getIt<ValueFormatter>()`.
- **Stateless static utility**: чистые функции (даты), без DI.

#### 8.4.1 ValueFormatter (locale-aware, `@lazySingleton`)

Форматирует `num`/`double` через `intl` `NumberFormat` (локаль-зависимые разделители тысяч/дробной части). Регистрируется в DI (см. `02-dependency-injection.md`); явная per-call `locale` всегда имеет приоритет, иначе — дефолт `Constants.defaultLocale`.

**Файл (текущий скелет):** `lib/general/formatters/value_formatter.dart`

```dart
import 'package:injectable/injectable.dart';
import 'package:intl/intl.dart';
import 'package:nox_app/general/constants.dart';

/// Formats numeric values with locale-aware separators using intl's NumberFormat.
/// Skeleton: fixed default locale. The settings-coupled variant (watching a
/// SettingsRepository for the active locale) arrives with the settings feature.
@lazySingleton
class ValueFormatter {
  ValueFormatter();

  /// Format a number with fixed fraction digits and locale-aware separators.
  /// Locale resolution: explicit per-call locale → Constants.defaultLocale.
  String format({required num value, int precision = 2, String? locale}) {
    final formatter = NumberFormat.decimalPatternDigits(locale: locale ?? Constants.defaultLocale, decimalDigits: precision);
    return formatter.format(value);
  }

  String formatDouble({required double value, int precision = 2, String? locale}) =>
      format(value: value, precision: precision, locale: locale);
}
```

**Будущий вариант (settings-coupled) — целевая форма** (комментарий в коде прямо это указывает): когда появится фича настроек, `ValueFormatter` начнёт инжектить `SettingsRepository`, подписываться на `watchFormatting()` и держать актуальную локаль приложения. Порядок резолва тогда: явная per-call `locale` → локаль из настроек → дефолт.

```dart
@lazySingleton
class ValueFormatter {
  final SettingsRepository _settingsRepository;

  ValueFormatter(this._settingsRepository) {
    _settingsRepository.watchFormatting().listen((result) {
      result.match(
        onData: (data) => _formatting = data,
        onError: (_) {},
      );
    });
  }

  SettingsFormattingModel _formatting = SettingsFormattingModel.initial();
  // format(...) использует _formatting.locale как дефолт
}
```

> **`result.match(...)`.** Поток настроек отдаёт `RepositoryResult<SettingsFormattingModel>` — `@freezed` data-XOR-exception envelope с расширением `match<R>({required onData, required onError})` (именованные параметры; см. `04-data-layer.md` и `08-conventions-and-constitution.md`). Это согласовано с локированным решением: `RepositoryResult` — `@freezed` с публичными вариантами `RepositoryResultSuccess<T>` / `RepositoryResultError<T>`, без permissive both-nullable варианта.

#### 8.4.2 DateFormatter (статическая утилита)

Предсобранные `DateFormat`-инстансы + статические хелперы. Без DI.

**Файл:** `lib/general/formatters/date_formatter.dart`

```dart
import 'package:intl/intl.dart';

/// Static date-formatting helpers for consistent display app-wide.
class DateFormatter {
  DateFormatter._();

  static final _short = DateFormat('MMM dd, yyyy', 'en_US');
  static final _time = DateFormat('HH:mm', 'en_US');

  static String short(DateTime date) => _short.format(date);

  static String time(DateTime date) => _time.format(date);
}
```

> Текущий набор узкий (`short` `MMM dd, yyyy` + `time` `HH:mm`). Более богатый набор (`formatLong`/`formatIso`/`formatRelative`) — план; добавляется с реальной потребностью. **Не путайте имена:** метод называется `short(...)`, а не `formatShort(...)`.

#### 8.4.3 Расширение `NumFormatterExt` на числовых типах (план — пока не в коде)

Выставляет форматирование прямо на любом `num` через `getIt<ValueFormatter>()`. Должно жить в presentation-расширениях, потому что тянет `getIt` из DI. **Сейчас файла нет** (`lib/presentation/extension/` отсутствует) — это запланированная форма; в сквозном примере §10 показана как иллюстрация целевого состояния.

**Файл (план):** `lib/presentation/extension/value_formatter_ext.dart`

```dart
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/general/formatters/value_formatter.dart';

extension NumFormatterExt on num {
  String toFormattedString({int precision = 2, String? unit}) {
    final formatted = getIt<ValueFormatter>().format(value: this, precision: precision);
    return unit != null ? '$formatted $unit' : formatted;
  }
}
```

#### 8.4.4 Тест форматтера

Локаль-форматирование проверяется напрямую передачей явного `locale` — текущий скелет `ValueFormatter` самодостаточен (no-arg ctor), внешних зависимостей нет.

**Файл:** `test/general/formatters/value_formatter_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/formatters/value_formatter.dart';

void main() {
  late ValueFormatter formatter;

  setUp(() {
    formatter = ValueFormatter();
  });

  group('ValueFormatter locale formatting', () {
    test('formats with grouping + fixed precision (en_US)', () {
      expect(formatter.format(value: 1234.5, precision: 2, locale: 'en_US'), equals('1,234.50'));
    });

    test('formats integers with grouping', () {
      expect(formatter.format(value: 1000000, precision: 0, locale: 'en_US'), equals('1,000,000'));
    });

    test('respects locale-specific separators (de_DE)', () {
      expect(formatter.format(value: 1234.5, precision: 2, locale: 'de_DE'), equals('1.234,50'));
    });
  });
}
```

> Когда `ValueFormatter` станет settings-coupled (§8.4.1), его ctor получит `SettingsRepository`, и в `setUp` подставляется фейк (`FakeSettingsRepository()`).

---

## 9. Дисциплина: «только токены» (несущее правило)

В коде фич (`lib/presentation/`) **запрещены** сырые конструкции внешнего вида:

- сырой `Color(...)` / `Colors.xxx` → только `Theme.of(context).colorScheme.xxx` (роли M3) или `context.appColors.xxx` (семантические доп-роли) — единственные каналы цвета;
- сырой `EdgeInsets`/`SizedBox` с числовым литералом → только `AppSpacingTokens.sN` (или фиксированные `NoxSpacing.*`, где скейл нежелателен);
- сырой `TextStyle(...)` → только `Theme.of(context).textTheme.*` (`noxTextTheme`) или фабрики `AppTextStyleTokens.xxx(...)`;
- сырой `SystemUiOverlayStyle(...)` → только `AppOverlayStyleTokens.xxx` (по канону §6.1);
- строковый путь ассета прямо в `Image.asset('...')` → только сгенерированный `Assets.*` (flutter_gen, канонический) либо `AppImagesTokens.xxx` (переходный, §7);
- `.sp`/`.w`/`.h`/`.r`-extension'ы `flutter_screenutil` напрямую в коде фич — **нет**; только внутри классов-токенов.

Единственные легитимные места объявления сырых значений цвета — сгенерированные файлы темы (`lib/design/theme/nox_*.dart`), файл доп-ролей (`app_colors.dart` — skeleton-литералы) и файлы токенов (`lib/design/app_*_tokens.dart`, например `AppOverlayStyleTokens` с его `const Color`-литералами). Это правило закреплено в `08-conventions-and-constitution.md` и проверяется на ревью.

---

## 10. Сквозной пример

Виджет, потребляющий цвета, отступы, текстовые стили и форматтеры вместе. Цвет берётся из темы (`context.appColors` / `colorScheme`), всё остальное — из токенов. (`NumFormatterExt` здесь иллюстрирует целевое состояние §8.4.3 — пока оно не в коде; до него используйте `getIt<ValueFormatter>().format(...)` напрямую.)

```dart
import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/app_text_style_tokens.dart';
import 'package:nox_app/design/theme/app_colors.dart';
import 'package:nox_app/general/formatters/date_formatter.dart';
import 'package:nox_app/general/formatters/value_formatter.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/item/item_model.dart';

Widget buildItemRow(BuildContext context, ItemModel item) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    padding: EdgeInsets.all(AppSpacingTokens.s12),
    decoration: BoxDecoration(
      color: context.appColors.surfaceMuted,
      border: Border(bottom: BorderSide(color: context.appColors.dividerSubtle)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.displayName, style: AppTextStyleTokens.title(color: scheme.onSurface)),
        SizedBox(height: AppSpacingTokens.s8),
        Text(
          getIt<ValueFormatter>().format(value: 1234.5, precision: 2),
          style: AppTextStyleTokens.body(color: scheme.onSurface),
        ),
        SizedBox(height: AppSpacingTokens.s4),
        Text(
          DateFormatter.short(item.createdAt),
          style: AppTextStyleTokens.caption(color: scheme.onSurfaceVariant),
        ),
      ],
    ),
  );
}
```

(`item.displayName` — extension-getter `ItemModelExt` поверх `@freezed ItemModel`; см. `03-domain-layer.md`.)

---

## Чеклист

После применения этого документа должно существовать и проходить (планируемое-но-не-в-коде отмечено явно):

- [ ] `lib/design/theme/nox_color_scheme.dart` (GENERATED): `const ColorScheme noxLightScheme` / `noxDarkScheme` с явно заданными ролями M3 (НЕ `ColorScheme.fromSeed`); seed-teal `0xFF12B4B4` задокументирован в шапке; генерируется из `docs/design/system/nox-handoff/tokens` — не редактируется руками.
- [ ] `lib/design/theme/nox_text_theme.dart` (GENERATED): `const TextTheme noxTextTheme` на `Roboto` + `noxMonoFamily = 'Roboto Mono'`, `height = lineHeightPx / fontSize`.
- [ ] `lib/design/theme/nox_tokens.dart` (GENERATED): `NoxSpacing` (4dp + `screenPadding`/`minTapTarget`), `NoxRadius` (none..full + `bubble({required bool isOwn})`), `NoxElevation` (level0..level5), `NoxDuration`, `NoxEasing`.
- [ ] `lib/design/theme/nox_brand.dart` (GENERATED): `NoxBrand` (brand-fixed: teal/canvasDark/qrSurface/qrInk/…), `noxAvatarPalette` (8), `noxAvatarColor`/`noxInitials`; продуктовые исключения — splash всегда тёмный (`canvasDark`), QR всегда светлый (`qrSurface`/`qrInk`).
- [ ] `lib/design/theme/app_colors.dart`: `AppColors extends ThemeExtension<AppColors>` (skeleton `{surfaceMuted, dividerSubtle}`, полный набор — US4), `copyWith` + `lerp` (пролерплено КАЖДОЕ поле), `LightAppColors`/`DarkAppColors`, `extension AppColorsExtension on BuildContext` с намеренным `!`; НЕТ публичного `AppColorsTokens`.
- [ ] `lib/design/theme/app_theme.dart`: `const AppTheme._()` + `static ThemeData light()/dark()` через `_build(ColorScheme scheme, AppColors appColors)` (`useMaterial3: true`, `colorScheme: scheme`, `textTheme: noxTextTheme`, `scaffoldBackgroundColor: scheme.surface`, `extensions: [appColors]`); НЕТ `colorSchemeSeed`/`_PaletteColors`.
- [ ] Инвариант: единая M3 тема из одного teal-seed на всех 5 платформах (iOS/Android/Windows/Linux/macOS); `yaru`/desktop-темы не используются. Desktop `NavigationRail` берёт цвета из стокового `secondaryContainer`/`onSecondaryContainer`.
- [ ] `MaterialApp` подключён: `theme: AppTheme.light()`, `darkTheme: AppTheme.dark()`, `themeMode: state.themeMode` из `AppRootBloc` (одновариантный `@freezed AppRootState` с полем `themeMode`, см. `05-presentation-layer.md`).
- [ ] `lib/design/app_spacing_tokens.dart`: `abstract final class` с приватным `const`-ctor, геттеры `s4`..`s32` = `N * _scale`, `_scale => (1.w + 1.h) / 2`.
- [ ] `lib/design/app_text_style_tokens.dart`: `abstract final class` с приватным `const`-ctor, фабрики `body`/`title`/`caption({required Color color})` через `.sp`; канонический type scale — `noxTextTheme` из темы.
- [ ] UI-скейл (§3.2): `AppRoot` оборачивает `MaterialApp` в `ScreenUtilInit(designSize: Constants.designSize` = `Size(360, 779)`, `minTextAdapt: true)` + двойной `MediaQuery` (`TextScaler.noScaling` снаружи + `TextScaler.linear(1.0)` внутри `builder`); `.sp`/`.w`/`.h`/`.r` — только внутри токен-классов, не в коде фич; `flutter_screenutil: 5.9.3`.
- [ ] `lib/design/app_overlay_style_tokens.dart`: `abstract final class`, `static const SystemUiOverlayStyle light`/`dark` — **только** поля статус-бара (нав-бар Android-specific, опущен); применяются по канону §6.1 (глобально в `AppRoot` по `Brightness`, `AnnotatedRegion` — задокументированное исключение).
- [ ] Картиночные ассеты: `lib/design/gen/assets.gen.dart` (flutter_gen, gitignored, `Assets.png/.svg/.animation`) — канонический канал, подключён в `pubspec.yaml::flutter_gen` + CI; рукописный `AppImagesTokens` (`_base = 'assets/png'`, `logo`/`emptyState`) сосуществует как переходный (дрейф к сведению, §7); директории — в `pubspec.yaml::flutter.assets`.
- [ ] `lib/general/constants.dart`: `final class Constants` с приватным ctor — `databaseName = 'nox_app_db'`, `defaultLocale`, `designSize`, `railBreakpoint = 840` (единственный источник брейкпоинта оболочки), regex.
- [ ] `lib/general/platform_utils.dart`: `PlatformUtils` с `isMobile`/`isDesktop` (desktop в scope, конституция v1.1.0) и per-OS геттерами, приватный ctor.
- [ ] `lib/general/text_constants.dart`: `abstract final TextConstants` — вся UI-микрокопи (English, ARB-ready), destination'ы оболочки `Chats`/`Settings`.
- [ ] `lib/general/feature_flags.dart`: `abstract final FeatureFlags` — compile-time тогглы (`enableSearch`, `enablePullToRefresh`).
- [ ] `lib/general/formatters/value_formatter.dart`: `@lazySingleton`, текущий скелет (no-arg ctor, дефолт `Constants.defaultLocale`), `intl` `NumberFormat`; settings-coupled вариант (`SettingsRepository` + `RepositoryResult.match`) — задокументированный план.
- [ ] `lib/general/formatters/date_formatter.dart`: статические `short(...)` (`MMM dd, yyyy`) / `time(...)` (`HH:mm`), приватный ctor; богатый набор — план.
- [ ] (План — пока не в коде) `lib/presentation/extension/value_formatter_ext.dart`: `extension NumFormatterExt on num` через `getIt<ValueFormatter>()`.
- [ ] `context.appColors` резолвится в светлом И тёмном режиме (нет throw из-за отсутствующего расширения) — проверено переключением `themeMode`.
- [ ] У каждого класса-токена и утилиты явный приватный конструктор `._()`.
- [ ] `flutter analyze` чист для `lib/design/` и `lib/general/`; тест форматтера проходит.
- [ ] Дисциплина «только токены» соблюдена: нет сырого `Color`/`EdgeInsets`/`TextStyle`/`SystemUiOverlayStyle`/строкового пути ассета/`.sp`-`.w`-`.h`-`.r` в `lib/presentation/` вне файлов токенов и темы (§9).
```
