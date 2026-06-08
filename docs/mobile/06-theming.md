# 06 — Темизация и дизайн-токены

> **Назначение:** канонический контракт темизации Speech AI Mobile — светлая и тёмная темы через `ThemeExtension<AppColors>`, сборка `AppTheme.light()/dark()`, четыре класса дизайн-токенов (отзывчивые отступы на `flutter_screenutil`, цвето-инъецирующие текстовые стили, overlay-стили, пути ассетов) и поддерживающий слой `lib/general/` (Constants, PlatformUtils, форматтеры). Цвет приходит только из `AppColors`-расширения темы (`context.appColors`); все прочие токены — статические классы. Сырые `Color`/`EdgeInsets`/`TextStyle`/`SystemUiOverlayStyle` в коде фич запрещены.
> **Когда читать:** при настройке внешнего вида приложения — сборка темы для `MaterialApp`, подключение токенов вместо «магических» значений, форматирование чисел и дат; перед реализацией любого экрана (первый реальный экран — список записей `records`).
> **Связанные документы:** `05-presentation-layer.md` (где `AppTheme.light()/dark()` потребляются `MaterialApp` под управлением `AppRootBloc`, и где живёт `AppRootBloc` с `themeMode`), `00-architecture-overview.md` (раскладка single-package), `01-stack-and-tooling.md` (зависимости `flutter_screenutil`, `intl`, опциональный `flutter_svg`), `02-dependency-injection.md` (регистрация `@lazySingleton ValueFormatter`), `08-conventions-and-constitution.md` (дисциплина именования и правило «только токены»).

---

## 0. Где всё лежит

Темизация и дизайн-токены живут в `lib/design/`, поддерживающие утилиты — в `lib/general/`. Обе папки — части единого пакета `speech_ai_mobile`; никаких отдельных пакетов или path-зависимостей (см. `00-architecture-overview.md`).

```
lib/
├── design/
│   ├── app_spacing_tokens.dart         # ОТЗЫВЧИВЫЙ sN-масштаб на flutter_screenutil
│   ├── app_text_style_tokens.dart      # цвето-инъецирующие фабрики h1/body/body2/label + extension on TextStyle
│   ├── app_overlay_style_tokens.dart   # static const SystemUiOverlayStyle
│   ├── app_images_tokens.dart          # static const пути ассетов
│   ├── gen/                            # генерируемые ассет-классы (flutter_gen_runner) — НЕ редактировать руками
│   └── theme/
│       ├── app_colors.dart            # ThemeExtension<AppColors> + Light/DarkAppColors + сырая палитра + context.appColors
│       └── app_theme.dart             # AppTheme.light()/dark() — сборка ThemeData + регистрация расширений
└── general/
    ├── constants.dart                  # final class Constants (приватный ctor): конфиг, regex, размеры
    ├── platform_utils.dart             # PlatformUtils.isDesktop / isMobile
    └── formatters/
        ├── value_formatter.dart        # @lazySingleton: настройко-зависимое форматирование чисел (intl)
        └── date_formatter.dart         # static DateFormat-хелперы
```

Архитектурное решение по темизации в этом блюпринте — **гибрид**: механизм светлой/тёмной темы взят из варианта `migration_v1` (`ThemeExtension<AppColors>` + `AppTheme.light()/dark()` + `context.appColors` + `themeMode` из app-level BLoC), а конкретные **значения палитры** и **отзывчивые токены отступов/типографики на `flutter_screenutil`** + `AppOverlayStyleTokens` взяты из BASE-подхода (`migration`). Ниже это явно отмечено в каждом разделе.

> **Где живёт цвет.** Никакого отдельного публичного класса-палитры цветов нет — единственный канал доступа к цвету в коде фич это `context.appColors.xxx` (`AppColors`-расширение темы). Сырые значения цвета объявляются **только** внутри файла темы `lib/design/theme/app_colors.dart` (раздел 1 — приватная палитра внутри этого файла), откуда `LightAppColors`/`DarkAppColors` мапят их в семантические роли. Статические классы-токены (`AppSpacingTokens`/`AppTextStyleTokens`/`AppOverlayStyleTokens`/`AppImagesTokens`) — для не-цветовых измерений.

> **Замечание по `lib/design/gen/`.** В стек подключён `flutter_gen_runner` (см. `01-stack-and-tooling.md`), генерируемые им классы складываются в `lib/design/gen/` и исключены из анализатора (`analysis_options.yaml`). Однако пути к ассетам в этом блюпринте ведутся **вручную** через `AppImagesTokens` (статические строковые константы) — настоящий codegen `flutter_gen` для ассетов опционален и не является несущей частью контракта. Это сознательный компромисс: ручные константы проще читать в диффах и не требуют прогона `build_runner` при добавлении одной иконки.

---

## 1. Палитра-источник — приватные значения внутри файла темы

Это **сырая** палитра (значения из BASE): плоские `static const Color` внутри файла темы `lib/design/theme/app_colors.dart`. Это **не** публичный класс-токен — это приватный набор констант (`_PaletteColors`) в одном файле с `AppColors`, из которого `LightAppColors` / `DarkAppColors` (раздел 2) собирают семантические темы. Держите здесь нейтральный ramp `tint1..tint10` (от светлого к тёмному) и семантические цвета (`error`/`green`/`link`), плюс `white`/`black`/`transparent`.

**Файл:** `lib/design/theme/app_colors.dart` (та же библиотека, что и `AppColors` ниже)

```dart
/// Raw palette — flat static const Color constants, PRIVATE to this file.
/// This is the SOURCE of truth for color VALUES; semantic light/dark mapping
/// lives in LightAppColors / DarkAppColors below.
/// There is NO public AppColorsTokens class — feature code reads colors only
/// through context.appColors. Raw Color literals are allowed ONLY here, inside
/// the theme file (see the "only-tokens" rule in §9).
class _PaletteColors {
  _PaletteColors._();

  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color transparent = Color(0x00000000);

  // Neutral ramp (tint1 lightest → tint10 darkest)
  static const Color tint1 = Color(0xFFE9E9E9);
  static const Color tint2 = Color(0xFFD3D3D3);
  static const Color tint3 = Color(0xFFA8A8A8);
  static const Color tint4 = Color(0xFF8A8A8A);
  static const Color tint5 = Color(0xFF6D6D6D);
  static const Color tint6 = Color(0xFF3A3A3A);
  static const Color tint7 = Color(0xFF252424);
  static const Color tint8 = Color(0xFF1A1A1A);
  static const Color tint9 = Color(0xFF141414);
  static const Color tint10 = Color(0xFF0E0E0E);

  // Semantic
  static const Color error = Color(0xFFC12B40);
  static const Color green = Color(0xFF22C55E);
  static const Color link = Color(0xFF7879F1);
}
```

> **Почему приватная палитра, а не сразу `ThemeExtension`?** Значения цвета — это палитра дизайн-системы (они не зависят от темы). Тёмная/светлая темы — это **отображение** палитры на семантические роли. Разделение позволяет одной строке палитры участвовать и в светлой, и в тёмной теме (например, `error` одинаков в обеих), и убирает дублирование hex-литералов. Но это **внутренняя** деталь файла темы: наружу торчит только семантический `AppColors` через `context.appColors`, а не плоские tint-значения.

---

## 2. Паттерн `ThemeExtension` — механизм светлой/тёмной темы

Flutter `ThemeExtension<T>` навешивает типизированные, зависящие от режима темы свойства на `ThemeData`. Это **механизм из `migration_v1`**, который заменяет одно-темовый подход BASE: вместо единственного `getAppTheme()` мы строим две `ThemeData` (`light`/`dark`) и переключаемся через `themeMode`.

Паттерн состоит из пяти частей в одном файле:

1. `@immutable AppColors extends ThemeExtension<AppColors>` со всеми семантическими `Color`-полями и `const`-конструктором.
2. `copyWith()` — переопределяет отдельные цвета (требуется контрактом `ThemeExtension`).
3. `lerp()` — интерполирует между светлой/тёмной при анимации смены темы (требуется контрактом). **Каждое поле должно быть пролерплено**, иначе анимация смены темы выглядит сломанной.
4. Подклассы `LightAppColors` / `DarkAppColors`, которые мапят значения приватной палитры (`_PaletteColors`) в светлый и тёмный варианты через `super(...)`.
5. Расширение `BuildContext`, чтобы виджеты читали цвета как `context.appColors.xxx`.

**Файл:** `lib/design/theme/app_colors.dart`

```dart
import 'package:flutter/material.dart';

/// Semantic colors layered onto the base Material theme via [ThemeExtension].
/// One field per semantic role (surface, divider, status accent, …).
/// Names are SEMANTIC, not literal ("surface", not "tint7").
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color statusError;
  final Color statusSuccess;
  final Color link;

  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.statusError,
    required this.statusSuccess,
    required this.link,
  });

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? divider,
    Color? textPrimary,
    Color? textSecondary,
    Color? statusError,
    Color? statusSuccess,
    Color? link,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      divider: divider ?? this.divider,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      statusError: statusError ?? this.statusError,
      statusSuccess: statusSuccess ?? this.statusSuccess,
      link: link ?? this.link,
    );
  }

  /// Linear interpolation between two color sets (theme transitions).
  /// IMPORTANT: lerp EVERY field, or animated theme changes will look wrong.
  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      statusError: Color.lerp(statusError, other.statusError, t)!,
      statusSuccess: Color.lerp(statusSuccess, other.statusSuccess, t)!,
      link: Color.lerp(link, other.link, t)!,
    );
  }
}

/// Light-mode palette — maps the private _PaletteColors into semantic roles.
class LightAppColors extends AppColors {
  const LightAppColors()
      : super(
          background: _PaletteColors.white,
          surface: _PaletteColors.tint1,
          surfaceVariant: _PaletteColors.tint2,
          divider: _PaletteColors.tint3,
          textPrimary: _PaletteColors.tint10,
          textSecondary: _PaletteColors.tint5,
          statusError: _PaletteColors.error,
          statusSuccess: _PaletteColors.green,
          link: _PaletteColors.link,
        );
}

/// Dark-mode palette — maps the private _PaletteColors into semantic roles.
class DarkAppColors extends AppColors {
  const DarkAppColors()
      : super(
          background: _PaletteColors.black,
          surface: _PaletteColors.tint7,
          surfaceVariant: _PaletteColors.tint6,
          divider: _PaletteColors.tint6,
          textPrimary: _PaletteColors.white,
          textSecondary: _PaletteColors.tint3,
          statusError: _PaletteColors.error,
          statusSuccess: _PaletteColors.green,
          link: _PaletteColors.link,
        );
}

/// Read semantic colors anywhere: `context.appColors.surface`.
/// The `!` is INTENTIONAL: if the extension is missing, that is a wiring bug
/// (you forgot to register it in AppTheme) and must fail loudly, not silently.
extension AppColorsExtension on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}
```

Для новой семантической роли добавляйте поле в `AppColors`, соответствующий параметр `copyWith`, строку в `lerp` и значения в `super(...)` обоих подклассов — **все четыре места в едином шаге**. Пропуск любого ломает либо компиляцию, либо анимацию темы.

---

## 3. Сборка темы — `AppTheme`

Один класс с приватным конструктором строит `light()` и `dark()` `ThemeData`. Каждый стартует от Material 3 базы (`useMaterial3: true`), задаёт `brightness` + `colorSchemeSeed`, переопределяет встроенные слоты темы и **регистрирует** оба наших расширения через `extensions: [...]` (Light-вариант в `light()`, Dark — в `dark()`). На **обеих** темах задаётся `pageTransitionsTheme` с Cupertino-переходами и для iOS, и для Android (из BASE-темы) — единый платформенно-нативный жест перехода.

Сырые значения цвета, нужные для встроенных слотов `ThemeData` (`scaffoldBackgroundColor`, `appBarTheme.*`), берутся напрямую из `context.appColors`-варианта через инстансы `LightAppColors()` / `DarkAppColors()` — единый источник, без дублирования hex-литералов в `app_theme.dart`.

**Файл:** `lib/design/theme/app_theme.dart`

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:speech_ai_mobile/design/app_text_style_tokens.dart';
import 'package:speech_ai_mobile/design/theme/app_colors.dart';

/// Centralized theme assembly. Composes a Material 3 base with the custom
/// AppColors ThemeExtension and built-in theme-slot overrides.
class AppTheme {
  AppTheme._();

  static const _light = LightAppColors();
  static const _dark = DarkAppColors();

  static const _pageTransitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
    },
  );

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: _light.link,
    );
    return base.copyWith(
      scaffoldBackgroundColor: _light.background,
      pageTransitionsTheme: _pageTransitions,
      appBarTheme: AppBarTheme(
        backgroundColor: _light.background,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: AppTextStyleTokens.body2(color: _light.textPrimary),
        iconTheme: IconThemeData(color: _light.textPrimary),
      ),
      // Register the LIGHT variant of every custom ThemeExtension.
      extensions: const <ThemeExtension<dynamic>>[
        _light,
      ],
    );
  }

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: _dark.link,
    );
    return base.copyWith(
      scaffoldBackgroundColor: _dark.background,
      pageTransitionsTheme: _pageTransitions,
      appBarTheme: AppBarTheme(
        backgroundColor: _dark.background,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: AppTextStyleTokens.body2(color: _dark.textPrimary),
        iconTheme: IconThemeData(color: _dark.textPrimary),
      ),
      // Register the DARK variant of every custom ThemeExtension.
      extensions: const <ThemeExtension<dynamic>>[
        _dark,
      ],
    );
  }
}
```

Два правила синхронности светлой и тёмной темы:

- Каждое кастомное `ThemeExtension` регистрируется в **обоих** методах (`Light*` в `light()`, `Dark*` в `dark()`). Забыть один вариант — значит получить рантайм-исключение `context.appColors` в этом режиме (из-за `!`).
- `colorSchemeSeed` выводится из одного и того же семантического `link` обеих тем — Material 3 сам выводит из seed согласованные светлый и тёмный `ColorScheme`. Наши семантические цвета поверх него идут через `AppColors`.

### 3.1 Потребление в `MaterialApp`

Полная сборка root-виджета — в `05-presentation-layer.md`. `AppRootBloc` (он же app-level BLoC) держит `themeMode` в своём состоянии; `MaterialApp` читает обе темы статически и переключается реактивно:

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

> **Перекрёстная ссылка.** `AppRootState` — это **одновариантный** `@freezed abstract`-value-объект с единственным полем `themeMode` (НЕ трио `Initializing`/`Initialized`/`Error` — те подсостояния относятся к фичевым BLoC, не к app-level; см. `05-presentation-layer.md`). `MaterialApp` читает `state.themeMode` напрямую (никогда `state.theme`). Само переключение темы инициируется событием (`AppRootEvent.setTheme(...)` / эквивалент), персистится через настройки и эмиттится в новое состояние через `copyWith`.

---

### 3.2 UI-скейл — `ScreenUtilInit` в корне (дизайн-канва + нейтрализация OS-шрифта)

**Цель.** Приложение должно выглядеть **плюс-минус одинаково** на всём парке устройств с разным физическим размером и разрешением экрана. Решение: единый **дизайн-скейл** (`flutter_screenutil`), от которого выводятся **все** размеры — отступы (`AppSpacingTokens`, §4) и шрифты (`AppTextStyleTokens`, §5). Никаких «магических» числовых литералов размеров в коде фич.

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
| `AppSpacingTokens.sN` (§4) | `(ScreenUtil().scaleWidth + ScreenUtil().scaleHeight) / 2` — **среднее** факторов width и height | отступы/размеры контейнеров масштабируются сбалансированно по обеим осям |
| `AppTextStyleTokens` (§5) | `ScreenUtil().scaleText` (учитывает `minTextAdapt`) | типографика масштабируется консервативнее, по меньшему фактору |

Оба класса кэшируют `_scale` лениво в `static double? _scaleValue` — он вычисляется один раз при первом обращении (`flutter_screenutil` дёргается единожды). **Важно:** `_scale` валиден только **после** того, как `ScreenUtilInit` отработал в дереве, поэтому к `AppSpacingTokens.sN` / `AppTextStyleTokens.xxx()` обращаются только внутри `build`-методов под `AppRoot` — никогда в top-level `static`-инициализаторах или до `runApp`.

> **Версия и границы.** `flutter_screenutil: 5.9.3` (пин в `01-stack-and-tooling.md`). `splitScreenMode` не используется (дефолт `false`). `.sp` / `.w` / `.h` / `.r`-extension'ы пакета в коде фич **не применяются** — единственный канал размеров — токены `App*Tokens`, которые сами умножают на `_scale` (правило «только токены», §9).

---

## 4. Дизайн-токены — отзывчивые отступы (`AppSpacingTokens`)

Токены отступов — **отзывчивый `sN`-масштаб из BASE**: каждое значение умножается на кэшированный `_scale`, выведенный из `flutter_screenutil` (среднее `scaleWidth` и `scaleHeight`; полный механизм скейла — §3.2). Это даёт пропорциональные отступы на разных размерах экранов при дизайн-размере `360x779`. Именование: `sN`, где `N` — базовое пиксельное значение. Все `EdgeInsets`/`SizedBox`/`gap` в коде фич ссылаются на токен, а не на литерал.

**Файл:** `lib/design/app_spacing_tokens.dart`

```dart
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// App-wide spacing scale. Naming: sN where N is the BASE pixel value;
/// the actual value is N * _scale, where _scale is the cached mean of
/// ScreenUtil width/height scale factors (responsive across screen sizes).
/// Design size is 360x779 (configured in the ScreenUtilInit at app root).
class AppSpacingTokens {
  AppSpacingTokens._();

  static double? _scaleValue;

  static double get _scale {
    _scaleValue ??= (ScreenUtil().scaleWidth + ScreenUtil().scaleHeight) / 2;
    return _scaleValue!;
  }

  static final double s0 = 0 * _scale;
  static final double s1 = 1 * _scale;
  static final double s2 = 2 * _scale;
  static final double s4 = 4 * _scale;
  static final double s6 = 6 * _scale;
  static final double s8 = 8 * _scale;
  static final double s10 = 10 * _scale;
  static final double s12 = 12 * _scale;
  static final double s14 = 14 * _scale;
  static final double s16 = 16 * _scale;
  static final double s20 = 20 * _scale;
  static final double s24 = 24 * _scale;
  static final double s28 = 28 * _scale;
  static final double s32 = 32 * _scale;
  static final double s36 = 36 * _scale;
  static final double s40 = 40 * _scale;
  static final double s48 = 48 * _scale;
  static final double s56 = 56 * _scale;
  static final double s64 = 64 * _scale;
  static final double s72 = 72 * _scale;
  static final double s80 = 80 * _scale;
  static final double s96 = 96 * _scale;
  static final double s128 = 128 * _scale;

  // Extended scale for large containers / screens.
  static final double s200 = 200 * _scale;
  static final double s300 = 300 * _scale;
  static final double s400 = 400 * _scale;
  static final double s420 = 420 * _scale;
}
```

> **Почему `static final`, а не `static const`?** `_scale` доступен только после инициализации `ScreenUtilInit` (в root-виджете, см. `05-presentation-layer.md`), поэтому значения вычисляются лениво в рантайме при первом обращении. `_scaleValue` кэшируется — `flutter_screenutil` дёргается ровно один раз. Никогда не обращайтесь к `AppSpacingTokens.sN` до того, как `ScreenUtilInit` отработал в дереве (то есть только внутри `build`-методов под root-виджетом).

Использование:

```dart
Padding(
  padding: EdgeInsets.all(AppSpacingTokens.s16),
  child: SizedBox(height: AppSpacingTokens.s200),
);
```

---

## 5. Дизайн-токены — текстовые стили (`AppTextStyleTokens`)

Текстовые стили — **цвето-инъецирующие фабрики из BASE** (НЕ `const`-поля): каждый метод принимает обязательный `Color color`, использует фиксированное семейство `_fontFamily = 'AppFont'` и масштабирует `fontSize`/`height` через `ScreenUtil().scaleText` (берёт меньший из факторов width/height благодаря `minTextAdapt: true`, см. §3.2). Цвет не зашит в стиль — он передаётся на месте вызова (обычно из `context.appColors.xxx`), что делает стиль независимым от темы. Поверх фабрик добавлено **аддитивное расширение из `migration_v1`** (`extension on TextStyle`) с мутациями `withPrimaryColor` / `withSecondaryColor` / `withMonospace` для сокращения `copyWith`-бойлерплейта.

**Файл:** `lib/design/app_text_style_tokens.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:speech_ai_mobile/design/theme/app_colors.dart';

/// Color-injecting text-style factories. Color is a REQUIRED parameter
/// (pass context.appColors.xxx at the call site) so styles stay theme-agnostic.
/// Font family is fixed; size/height are scaled by ScreenUtil().scaleText.
class AppTextStyleTokens {
  AppTextStyleTokens._();

  static double? _scaleValue;
  static double get _scale => _scaleValue ??= ScreenUtil().scaleText;

  static const _fontFamily = 'AppFont';

  static TextStyle h1({required Color color, List<FontFeature>? fontFeatures}) => TextStyle(
        color: color,
        fontFamily: _fontFamily,
        fontWeight: FontWeight.w500,
        fontSize: 40.0 * _scale,
        height: 1.1 * _scale,
        fontFeatures: fontFeatures,
        leadingDistribution: TextLeadingDistribution.even,
      );

  static TextStyle body({required Color color}) => TextStyle(
        color: color,
        fontFamily: _fontFamily,
        fontWeight: FontWeight.w500,
        fontSize: 16.0 * _scale,
        height: 1.4 * _scale,
      );

  static TextStyle body2({required Color color}) => TextStyle(
        color: color,
        fontFamily: _fontFamily,
        fontWeight: FontWeight.w500,
        fontSize: 12.0 * _scale,
        height: 1.4 * _scale,
      );

  static TextStyle label({required Color color}) => TextStyle(
        color: color,
        fontFamily: _fontFamily,
        fontWeight: FontWeight.w500,
        fontSize: 14.0 * _scale,
        height: 1.1 * _scale,
      );
}

/// Additive TextStyle mutations to cut copyWith boilerplate at the call site.
/// Colors are read from the AppColors ThemeExtension (theme-aware).
extension AppTextStyleTokensExtension on TextStyle {
  TextStyle withPrimaryColor(BuildContext context) {
    return copyWith(color: context.appColors.textPrimary);
  }

  TextStyle withSecondaryColor(BuildContext context) {
    return copyWith(color: context.appColors.textSecondary);
  }

  TextStyle withMonospace() {
    return copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      fontFamily: 'monospace',
    );
  }
}
```

Использование:

```dart
Text(item.title, style: AppTextStyleTokens.body(color: context.appColors.textPrimary));

// Эквивалент через аддитивное расширение (цвет берётся из темы):
Text(item.title, style: AppTextStyleTokens.body(color: context.appColors.textPrimary).withSecondaryColor(context));

// Моноширинные цифры для числовых колонок:
Text('123.45', style: AppTextStyleTokens.body2(color: context.appColors.textPrimary).withMonospace());
```

> **Шрифт `AppFont`.** Семейство `'AppFont'` объявляется в секции `fonts:` файла `pubspec.yaml` (см. `01-stack-and-tooling.md`) и кладётся в `assets/fonts/`. Пока кастомный шрифт не подключён, можно временно указать системный, но имя `'AppFont'` в коде менять не нужно — меняется только привязка в `pubspec.yaml`.

---

## 6. Дизайн-токены — overlay-стили (`AppOverlayStyleTokens`)

Четвёртый класс токенов (из BASE) — `static const SystemUiOverlayStyle` для статус-бара и системного навбара. Сырой `SystemUiOverlayStyle` в коде фич запрещён — задавайте overlay только через эти константы (обычно в `AnnotatedRegion` или `SystemChrome.setSystemUIOverlayStyle`). Сами значения цвета (системный навбар, прозрачный статус-бар) — `const Color`-литералы внутри этого файла токенов, что разрешено правилом §9 для файлов токенов.

**Файл:** `lib/design/app_overlay_style_tokens.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// System UI overlay styles (status bar / system navigation bar).
/// Use these instead of constructing SystemUiOverlayStyle in feature code.
class AppOverlayStyleTokens {
  AppOverlayStyleTokens._();

  static const SystemUiOverlayStyle dark = SystemUiOverlayStyle(
    systemNavigationBarColor: Color(0xFF000000),
    systemNavigationBarIconBrightness: Brightness.light,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    statusBarColor: Color(0x00000000),
  );

  static const SystemUiOverlayStyle light = SystemUiOverlayStyle(
    systemNavigationBarColor: Color(0xFFFFFFFF),
    systemNavigationBarIconBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    statusBarColor: Color(0x00000000),
  );
}
```

---

## 7. Дизайн-токены — пути ассетов (`AppImagesTokens`)

Пятый класс токенов (из `migration_v1`) — статические строковые константы путей к ассетам, сгруппированные по категориям. Единый источник истины для каждой ссылки на ассет — никаких строковых литералов путей, разбросанных по виджетам. PNG рендерится встроенным `Image.asset` (без доп. зависимостей); для SVG — опциональный `flutter_svg` (см. `01-stack-and-tooling.md`) и `SvgPicture.asset(...)`.

**Файл:** `lib/design/app_images_tokens.dart`

```dart
/// App-wide asset paths, grouped by category.
/// Add the matching directories to the `assets:` section of pubspec.yaml.
/// Hand-written constants (NOT flutter_gen codegen) — see note in §0.
class AppImagesTokens {
  AppImagesTokens._();

  // Category icons (raster PNG — no extra dependency required)
  static const iconHome = 'assets/icons/home.png';
  static const iconSettings = 'assets/icons/settings.png';
  static const iconSearch = 'assets/icons/search.png';

  // Illustrations
  static const illustrationEmpty = 'assets/illustrations/empty.png';
  static const illustrationError = 'assets/illustrations/error.png';
  static const illustrationSuccess = 'assets/illustrations/success.png';
}
```

Использование:

```dart
Image.asset(AppImagesTokens.iconHome);
// Опционально SVG:
// SvgPicture.asset(AppImagesTokens.iconHome);
```

---

## 8. Поддерживающий слой `lib/general/`

Вспомогательные синглтоны и утилиты, не относящиеся ни к одному конкретному экрану. Все классы-токены и утилиты здесь имеют **явный приватный конструктор `._()`** (дисциплина из `migration_v1`) — они никогда не инстанцируются, доступ только статический (кроме `@lazySingleton ValueFormatter`, который резолвится через `getIt`).

### 8.1 Constants

`final class` с приватным конструктором: конфиг приложения, UI-дефолты и regex-валидаторы как `static const` / `static final`.

**Файл:** `lib/general/constants.dart`

```dart
import 'dart:ui';

/// App-wide constants. Never instantiated — access members statically.
final class Constants {
  Constants._();

  /// General config
  static const databaseName = 'speech_ai_mobile_db';
  static const defaultLocale = 'en_US';

  /// UI
  static const defaultNavTransitionTimeMilliseconds = 300;
  static const preventDoubleNavDelayMilliseconds = 300;
  static const designSize = Size(360, 779); // flutter_screenutil reference

  /// Validation patterns (compile once as static final RegExp)
  static final emailRegex = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@"
    r"[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?"
    r"(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$",
  );
  static final phoneRegex = RegExp(r'^\+?[0-9]{7,15}$');
}
```

Использование:

```dart
if (!Constants.emailRegex.hasMatch(email)) {
  // reject
}
```

### 8.2 PlatformUtils

Оборачивает проверки `dart:io` `Platform` за маленьким статическим хелпером — платформенное ветвление централизовано и легко грепается. Для мобильного приложения практически всё пойдёт через `isMobile`, но десктоп-геттеры оставлены для совместимости (например, отладочные сборки на macOS).

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

### 8.3 Форматтеры

Два вида:

- **Stateful, DI-зарегистрированный** (`@lazySingleton`): зависит от репозитория настроек, чтобы вывод уважал выбранную пользователем локаль. Резолвится через `getIt<ValueFormatter>()`.
- **Stateless static utility**: чистые функции (даты), без DI.

#### 8.3.1 ValueFormatter (настройко-зависимый, `@lazySingleton`)

Подписывается на поток настроек, держит актуальную локаль и форматирует `num`/`double` через `intl` `NumberFormat` (локаль-зависимые разделители тысяч/дробной части). Регистрируется в DI (см. `02-dependency-injection.md`).

**Файл:** `lib/general/formatters/value_formatter.dart`

```dart
import 'package:injectable/injectable.dart';
import 'package:intl/intl.dart';
import 'package:speech_ai_mobile/domain/repository/settings/settings_repository.dart';
import 'package:speech_ai_mobile/domain/model/settings/settings_formatting_model.dart';

/// Formats numeric values with locale-aware separators using intl's NumberFormat.
/// Stateful: watches the settings repository so the active locale stays current.
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
  SettingsFormattingModel get formatting => _formatting;

  /// Format a number with fixed fraction digits and locale-aware separators.
  String format({required num value, int precision = 2, String? locale}) {
    final effectiveLocale = locale ?? _formatting.locale;
    final formatter = NumberFormat.decimalPatternDigits(
      locale: effectiveLocale,
      decimalDigits: precision,
    );
    return formatter.format(value);
  }

  String formatDouble({required double value, int precision = 2, String? locale}) {
    return format(value: value, precision: precision, locale: locale);
  }
}
```

> **`result.match(...)`.** Поток настроек отдаёт `RepositoryResult<SettingsFormattingModel>` — `@freezed sealed` data-XOR-exception envelope с расширением `match<R>({required onData, required onError})` (именованные параметры; см. `04-data-layer.md` и `08-conventions-and-constitution.md`). Это согласовано с локированным решением: `RepositoryResult` — `@freezed sealed` с публичными вариантами `RepositoryResultSuccess<T>` / `RepositoryResultError<T>`, без permissive both-nullable варианта.

#### 8.3.2 DateFormatter (статическая утилита)

Предсобранные `DateFormat`-инстансы + статические хелперы. Без DI.

**Файл:** `lib/general/formatters/date_formatter.dart`

```dart
import 'package:intl/intl.dart';

/// Static date-formatting helpers for consistent display app-wide.
class DateFormatter {
  DateFormatter._();

  static final _short = DateFormat('MMM dd, yyyy', 'en_US');
  static final _long = DateFormat("MMM d, y 'at' HH:mm:ss", 'en_US');
  static final _iso = DateFormat('yyyy-MM-dd', 'en_US');

  static String formatShort(DateTime date) => _short.format(date).toUpperCase();
  static String formatLong(DateTime date) => _long.format(date);
  static String formatIso(DateTime date) => _iso.format(date);

  static String formatRelative(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return formatShort(date);
  }
}
```

#### 8.3.3 Расширение `NumFormatterExt` на числовых типах

Выставляет форматирование прямо на любом `num` через `getIt<ValueFormatter>()`. Живёт в presentation-расширениях, потому что тянет `getIt` из DI.

**Файл:** `lib/presentation/extension/value_formatter_ext.dart`

```dart
import 'package:speech_ai_mobile/di/configure_dependencies.dart';
import 'package:speech_ai_mobile/general/formatters/value_formatter.dart';

extension NumFormatterExt on num {
  String toFormattedString({int precision = 2, String? unit}) {
    final formatted = getIt<ValueFormatter>().format(value: this, precision: precision);
    return unit != null ? '$formatted $unit' : formatted;
  }
}
```

#### 8.3.4 Тест форматтера

Локаль-форматирование проверяется напрямую передачей явного `locale`, а зависимость на репозиторий настроек подменяется фейком.

**Файл:** `test/general/formatters/value_formatter_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_ai_mobile/general/formatters/value_formatter.dart';

void main() {
  late ValueFormatter formatter;

  setUp(() {
    formatter = ValueFormatter(FakeSettingsRepository());
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

---

## 9. Дисциплина: «только токены» (несущее правило)

В коде фич (`lib/presentation/`) **запрещены** сырые конструкции внешнего вида:

- сырой `Color(...)` / `Colors.xxx` → только `context.appColors.xxx` (семантика из `AppColors`-расширения темы — единственный канал цвета);
- сырой `EdgeInsets`/`SizedBox` с числовым литералом → только `AppSpacingTokens.sN`;
- сырой `TextStyle(...)` → только `AppTextStyleTokens.xxx(...)` (+ опционально `.withXxx`);
- сырой `SystemUiOverlayStyle(...)` → только `AppOverlayStyleTokens.xxx`;
- строковый путь ассета прямо в `Image.asset('...')` → только `AppImagesTokens.xxx`.

Единственные легитимные места объявления сырых значений цвета — файл темы (`lib/design/theme/app_colors.dart` — приватная палитра `_PaletteColors`) и файлы токенов (`lib/design/app_*_tokens.dart`, например `AppOverlayStyleTokens` с его `const Color`-литералами). Это правило закреплено в `08-conventions-and-constitution.md` и проверяется на ревью.

---

## 10. Сквозной пример

Виджет, потребляющий цвета, отступы, текстовые стили и форматтеры вместе. Цвет берётся из темы (`context.appColors`), всё остальное — из токенов:

```dart
import 'package:flutter/material.dart';
import 'package:speech_ai_mobile/design/app_spacing_tokens.dart';
import 'package:speech_ai_mobile/design/app_text_style_tokens.dart';
import 'package:speech_ai_mobile/design/theme/app_colors.dart';
import 'package:speech_ai_mobile/general/formatters/date_formatter.dart';
import 'package:speech_ai_mobile/presentation/extension/value_formatter_ext.dart';
import 'package:speech_ai_mobile/domain/model/item/item_model.dart';

Widget buildItemRow(BuildContext context, ItemModel item) {
  return Container(
    padding: EdgeInsets.all(AppSpacingTokens.s12),
    decoration: BoxDecoration(
      color: context.appColors.surface,
      border: Border(bottom: BorderSide(color: context.appColors.divider)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.title, style: AppTextStyleTokens.body(color: context.appColors.textPrimary)),
        SizedBox(height: AppSpacingTokens.s8),
        Text(
          1234.5.toFormattedString(precision: 2),
          style: AppTextStyleTokens.body2(color: context.appColors.textPrimary).withMonospace(),
        ),
        SizedBox(height: AppSpacingTokens.s4),
        Text(
          DateFormatter.formatShort(item.createdAt),
          style: AppTextStyleTokens.body2(color: context.appColors.textSecondary),
        ),
      ],
    ),
  );
}
```

---

## Чеклист

После применения этого документа должно существовать и проходить:

- [ ] `lib/design/theme/app_colors.dart`: приватная палитра `_PaletteColors` (`static const Color`: white/black/transparent, ramp `tint1..tint10`, semantic `error`/`green`/`link`), приватный ctor; НЕТ публичного класса `AppColorsTokens`.
- [ ] `lib/design/theme/app_colors.dart`: `AppColors extends ThemeExtension<AppColors>` с `copyWith` + `lerp` (пролерплено КАЖДОЕ поле), `LightAppColors`/`DarkAppColors` (мапят `_PaletteColors`), `extension AppColorsExtension on BuildContext` с намеренным `!`.
- [ ] `lib/design/theme/app_theme.dart`: `AppTheme._()` + `static ThemeData light()/dark()` (`useMaterial3: true`, `brightness`, `colorSchemeSeed`), каждая регистрирует свой вариант `AppColors` в `extensions:` и задаёт `pageTransitionsTheme` (Cupertino на iOS и Android).
- [ ] `MaterialApp` подключён: `theme: AppTheme.light()`, `darkTheme: AppTheme.dark()`, `themeMode: state.themeMode` из `AppRootBloc` (одновариантный `@freezed abstract AppRootState` с полем `themeMode`, см. `05-presentation-layer.md`).
- [ ] `lib/design/app_spacing_tokens.dart`: отзывчивый `sN`-масштаб (`N * _scale`, `_scale` = кэшированное среднее `ScreenUtil` width/height), приватный ctor.
- [ ] `lib/design/app_text_style_tokens.dart`: цвето-инъецирующие фабрики `h1/body/body2/label({required Color color})`, фиксированный `_fontFamily = 'AppFont'`, масштаб через `ScreenUtil().scaleText`, + `extension AppTextStyleTokensExtension on TextStyle` (`withPrimaryColor`/`withSecondaryColor`/`withMonospace`).
- [ ] UI-скейл (§3.2): `AppRoot` оборачивает `MaterialApp` в `ScreenUtilInit(designSize: Constants.designSize` = `Size(360, 779)`, `minTextAdapt: true)` + двойной `MediaQuery` (`TextScaler.noScaling` снаружи + `TextScaler.linear(1.0)` внутри `builder`) — OS-масштаб шрифта нейтрализован; размеры выводятся из дизайн-скейла (код — `05-presentation-layer.md` §6.2).
- [ ] `Constants.designSize = Size(360, 779)` (`lib/general/constants.dart`); `flutter_screenutil: 5.9.3`; `.sp`/`.w`/`.h`/`.r`-extension'ы пакета в коде фич не используются.
- [ ] `lib/design/app_overlay_style_tokens.dart`: `static const SystemUiOverlayStyle` (`dark`/`light`), приватный ctor.
- [ ] `lib/design/app_images_tokens.dart`: `static const` пути ассетов; соответствующие директории добавлены в `assets:` в `pubspec.yaml`.
- [ ] `lib/general/constants.dart`: `final class Constants` с приватным ctor — конфиг + regex + UI-дефолты.
- [ ] `lib/general/platform_utils.dart`: `PlatformUtils` с `isMobile`/`isDesktop` и пер-OS геттерами, приватный ctor.
- [ ] `lib/general/formatters/value_formatter.dart`: `@lazySingleton`, настройко-зависимый, локаль-зависимое форматирование `num`/`double` через `intl` `NumberFormat`, читает поток через `RepositoryResult.match(onData:, onError:)`.
- [ ] `lib/general/formatters/date_formatter.dart`: статические `DateFormat`-хелперы, приватный ctor.
- [ ] `lib/presentation/extension/value_formatter_ext.dart`: `extension NumFormatterExt on num` через `getIt<ValueFormatter>()`.
- [ ] `context.appColors` резолвится в светлом И тёмном режиме (нет throw из-за отсутствующего расширения) — проверено переключением `themeMode`.
- [ ] У каждого класса-токена и утилиты явный приватный конструктор `._()`.
- [ ] `flutter analyze` чист для `lib/design/` и `lib/general/`; тест форматтера проходит.
- [ ] Дисциплина «только токены» соблюдена: нет сырого `Color`/`EdgeInsets`/`TextStyle`/`SystemUiOverlayStyle`/строкового пути ассета в `lib/presentation/` вне файлов токенов и темы (§9).
