# Data Model — каталог виджетов UI-кита (Phase 1)

«Сущности» этой фичи — виджеты, enum'ы и хелперы. Для каждого: API (props/коллбэки), варианты/состояния, token-bindings (по `nox-handoff-2/spec/components.md` + `primitives.md`), кураторские golden-сценарии (2–4 × light/dark) и ключевые widget-assert'ы. Все цвета — роли `colorScheme`/`context.appColors`/`NoxBrand`; текст — роли `textTheme`/`AppTextStyleTokens`; иконки — `NoxIcons` (SVG); shape/elevation — `NoxRadius`/`NoxElevation`; spacing — `AppSpacingTokens` (+ компонент-собственные именованные const).

Легенда колонок: **API** — конструктор; **Варианты** — что покрываем; **Bindings** — токен-привязки; **Golden** — снапшот-сценарии; **Widget-test** — наблюдаемые проверки.

---

## 1. Примитивы (`lib/presentation/widgets/primitives/`)

### AppIconWidget
- **API:** `AppIconWidget(SvgGenImage icon, {double size = 24, Color? color, double fill = 0})` — `icon` из `NoxIcons.*`; `fill` 0/1 (вызывающий передаёт filled-вариант, либо widget выбирает по соглашению).
- **Варианты:** outlined (fill 0) / filled (fill 1); кастомный цвет vs дефолт `onSurfaceVariant`; размеры 24/48.
- **Bindings:** рекраска `ColorFilter.mode(color ?? cs.onSurfaceVariant, srcIn)`; SVG ship `currentColor`.
- **Golden:** outlined + filled (light/dark).
- **Widget-test:** рендер `SvgPicture`; применённый цвет/размер; filled-вариант ≠ outlined.

### AppSpinnerWidget
- **API:** `AppSpinnerWidget({double size = 24, Color? color, double strokeWidth = 3})`.
- **Варианты:** standalone (`primary`) / on-primary (передан `cs.onPrimary`).
- **Bindings:** `CircularProgressIndicator(color: color ?? cs.primary)`; размер через `SizedBox`.
- **Golden:** standalone (light/dark).
- **Widget-test:** наличие `CircularProgressIndicator`; размер.

### AppAvatarWidget
- **API:** `AppAvatarWidget({required String name, double size = 40})`.
- **Варианты:** валидные инициалы; нет инициалов → `forum`-глиф; длинное имя; детерминизм цвета.
- **Bindings:** фон `noxAvatarColor(name)`; инициалы белые `Colors.white` (brand-fixed) размер `size*0.4` w500 (через `AppTextStyleTokens`/`TextStyle` от роли); fallback `NoxIcons.forumFill` белый.
- **Golden:** инициалы + fallback-глиф (light/dark).
- **Widget-test:** инициалы из `noxInitials`; fallback-глиф при отсутствии; одинаковый цвет для одного имени.

### AppFileGlyphWidget
- **API:** `AppFileGlyphWidget({required FileType type, double iconSize = 24, double box = 44})`.
- **Варианты:** разные `FileType` (цвет/иконка).
- **Bindings:** фон `noxFileColor(type)`@14%; радиус `box*0.27`; иконка `noxFileIcon(type)` цветом `noxFileColor(type)`.
- **Golden:** 2–3 типа (light/dark).
- **Widget-test:** иконка по типу; тинт.

### `FileType` (enum) + maps — `primitives/file_type.dart`
- `enum FileType { image, video, audio, pdf, doc, sheet, text, archive, other }`.
- `SvgGenImage noxFileIcon(FileType)` → `NoxIcons.{image,videocam,musicNote,pictureAsPdf,description,tableChart,article,folderZip,draft}`.
- `Color noxFileColor(FileType)` → `NoxBrand.{blue,coral,amber,red,tealDeep,lime,teal,gold,tealDeep}`.

---

## 2. Composite — чат/сообщения (`lib/presentation/widgets/chat/`)

| Widget | API | Варианты | Bindings | Golden | Widget-test |
|---|---|---|---|---|---|
| **AppSearchBarWidget** | `({String? value, String hint = TextConstants.searchHint, VoidCallback? onTap})` | пусто (hint) / со значением | `surfaceContainerHigh`, `NoxRadius.full`, `NoxElevation.level2`; иконка `NoxBrand.teal` (brand); текст `bodyLarge` `onSurface`/hint `onSurfaceVariant`; height 56 (const) | hint + value (l/d) | hint vs value текст; `onTap`; brand-teal иконка |
| **AppChatItemWidget** | `({required String name, required String preview, required String time, int unread = 0, VoidCallback? onTap})` | unread=0 / 1..99 / >99; min-height 72 | name `titleMedium` (w600 при unread) `onSurface`; preview `bodyMedium` (`onSurface`/`onSurfaceVariant`); time `labelSmall` (`primary` при unread); badge bg `primary`/`onPrimary` `labelSmall`, cap `99+`, скрыт при 0; avatar 40 + ring | unread=0, unread=5, unread=120 (l/d) | badge скрыт при 0; `99+` при >99; `onTap`; unread-акцент |
| **AppFileChipWidget** | `({required FileType type, required String name, required String size, bool inBubble = false, Color? onColor, bool removable = false, VoidCallback? onRemove})` | standalone / inBubble; removable; длинное имя | standalone `surfaceContainerHighest`/`onSurface`; inBubble тинт от `onColor`@12/.7; `NoxRadius.xs`; иконка `noxFileIcon`; remove `NoxIcons.close` tap-target 48 | standalone, inBubble, removable (l/d) | имя ellipsis; `onRemove`; тинт inBubble |
| **AppMessageBubbleWidget** | `({required bool isOwn, String? text, required String time, MessageStatus status = MessageStatus.none, Widget? file, bool isLast = false})` | own/other; status pending/sent/error; text/file/both; long text; isLast | own `primaryContainer`/`onPrimaryContainer`, other `surfaceContainerHigh`/`onSurface`; `NoxRadius.bubble(isOwn:)`; meta `onPrimaryContainer`@70 / `onSurfaceVariant`; status иконка `NoxIcons.schedule/check/error` (error→`cs.error`); max-width 80% | own+sent, other, own+file, error (l/d) | заливка/clip по isOwn; статус-иконка; max-width; file-чип внутри |
| **AppComposerWidget** | `({String? value, Widget? attachment, bool sendActive = false, VoidCallback? onAttach, VoidCallback? onSend})` | пусто (send disabled) / value (active); с attachment | `surfaceContainer` + top `outlineVariant`; attach `NoxIcons.attachFile` `onSurfaceVariant`; send `NoxIcons.sendFill` active `primary`/disabled `onSurface`@38% | empty, with-text, with-attachment (l/d) | send disabled при пусто; `onSend` только при active; `onAttach`; attachment рендерится |
| **AppSegmentedWidget`<T>`** | `({required Map<T,String> options, required T selected, required ValueChanged<T> onChanged})` | 2–3 сегмента; смена выбора | стоковый `SegmentedButton` (тема: selected `secondaryContainer`, shape) | 2 segments selected A / B (l/d) | `onChanged` при тапе; выбранный сегмент |

---

## 3. Оболочка (`lib/presentation/widgets/shell/`)

| Widget | API | Варианты | Bindings | Golden | Widget-test |
|---|---|---|---|---|---|
| **AppSplashHairlineWidget** (`PreferredSizeWidget`) | `()` | — | 3dp градиент `NoxBrand.teal→lime→gold→coral→red`, radius 2; `preferredSize` height 3+14 | дефолт (l/d) | `preferredSize`; рендер градиента |
| **AppWordmarkWidget** | `({Color? color})` | дефолт/кастом цвет | `'NOX'`, Roboto Bold 700, letterSpacing +0.12em (через `textTheme`/`AppTextStyleTokens`), `onSurface` | дефолт (l/d) | текст `NOX`; вес/спейсинг |
| **AppBottomBarWidget** + `AppTab` | `({required AppTab active, required ValueChanged<AppTab> onSelect})` | active chats / settings | `BottomAppBar` `surfaceContainer` `NoxElevation.level2`, `CircularNotchedRectangle`, notchMargin 8, height 64; tabs selected `primary`+filled (`forumFill`/`settingsFill`) / unselected `onSurfaceVariant` (`forum`/`settings`); labels `labelMedium` | active=chats, active=settings (l/d) | `onSelect`; filled-иконка у активной; notch-gap |
| **AppCreateFabWidget** | `({VoidCallback? onPressed})` | — | `FloatingActionButton` `primaryContainer`/`onPrimaryContainer`, `NoxElevation.level3`, `CircleBorder`, иконка `NoxIcons.add` | дефолт (l/d) | `onPressed`; иконка add |

`enum AppTab { chats, settings }` — в `app_bottom_bar_widget.dart`.

---

## 4. Generic state-виджеты (`lib/presentation/widgets/state/`)

| Widget | API | Варианты | Bindings | Golden | Widget-test |
|---|---|---|---|---|---|
| **AppProgressWidget** | `({double size = 24})` | — | центрированный `AppSpinnerWidget` (`primary`) | дефолт (l/d) | наличие `AppSpinnerWidget`, центрирование |
| **AppErrorWidget** | `({String? message, VoidCallback? onTryAgain})` | с/без message; с/без retry | `NoxIcons.error` 48–96 `onSurfaceVariant`; message `bodyMedium`; retry `FilledButton`(`TextConstants.actionTryAgain`) | with-message+retry, icon-only (l/d) | message текст; `onTryAgain` по тапу; CTA скрыт без коллбэка |
| **AppEmptyContentWidget** | `({required SvgGenImage illustration, required String title, required String message})` | разные иллюстрации; длинный текст | `Assets.svg.illustrations.*` (flutter_svg); title `headlineSmall` `onSurface`; message `bodyMedium` `onSurfaceVariant` (maxWidth 260) | empty-chats, empty-messages (l/d) | рендер `SvgPicture`; title/message |

---

## 5. Каналы обратной связи (`lib/presentation/helpers/app_feedback_helper.dart`)

- **`void showAppSnackBar(BuildContext, {required String text, String? actionLabel, VoidCallback? onAction, bool error = false})`** — neutral `inverseSurface`/`onInverseSurface`, action `inversePrimary`; error `errorContainer`/`onErrorContainer`; floating, `NoxRadius.xs`. Текст предпереведён вызывающим.
- **`void showAppBanner(BuildContext, {required String text, SvgGenImage? icon, String? actionLabel, VoidCallback? onAction})`** — `MaterialBanner` `surfaceContainer` `NoxElevation.level3`, leading icon (default `NoxIcons` wifi-off-эквивалент) `onSurfaceVariant`, action `primary`.
- **Widget-test:** в тест-Scaffold вызвать хелпер → `find.byType(SnackBar)` / `find.byType(MaterialBanner)`; цвет фона по `error`; `onAction`. (Golden — не обязателен; покрывается showcase/widget-тестом.)

---

## 6. Тема stock-виджетов (`lib/design/theme/`)

- **`nox_component_themes.dart`** — функции, возвращающие sub-themes от `ColorScheme`: `inputDecorationTheme`, `filledButtonTheme`, `textButtonTheme`, `iconButtonTheme`, `segmentedButtonTheme`, `switchTheme`, `radioTheme`, `listTileTheme`, `progressIndicatorTheme`, `dialogTheme`, `bottomSheetTheme`, `cardTheme`, `snackBarTheme`, `appBarTheme` — биндинги из `components.md`/референс `nox_theme.dart`. `Switch`/`Radio` — M3-дефолт с NOX-ролями (on `primary`, label `onSurface`); `LinearProgressIndicator` — indicator `primary` / track `surfaceVariant` (5.3).
- **`app_theme.dart`** — `AppTheme._build` подключает их в `ThemeData(...)`.
- **`theme_showcase_golden_test.dart`** — один сводный golden: `FilledButton`, `TextButton`, `IconButton`, `TextField` (focus/error), `SegmentedButton`, `SwitchListTile`, `RadioListTile`, `LinearProgressIndicator`, `AlertDialog`, `SnackBar`, bottom sheet, `Card` под темой (light+dark).

---

## 7. Лаунчер + галерея (`lib/presentation/pages/`)

- **`HomePage`** (`pages/home_page/`) — стартовый экран `AppRoot` (вместо `Item`-харнесса): brand-hero + кнопка «Open UI Kit» → `Navigator.push(UiKitPage.route())`. AppBar: wordmark + splash-hairline + `AppThemeToggle`.
- **`UiKitPage`** (`pages/ui_kit_page/`) — каталог секций (Primitives / Chat & messaging / State / Feedback & stock) со всеми виджетами; `static Route<void> route()`.
- **`AppThemeToggle`** (`app/widgets/`) — общий app-bar-переключатель light/dark (диспатчит `AppRootBloc.SetTheme`; требует `AppRootBloc`-предка, предоставляется `AppRoot`).

---

## Зависимости / порядок

`primitives` (incl. `FileType`/maps) → используются `chat`/`state`/`shell`; `nox_component_themes` независим (тема); `helpers` независимы; `gallery` зависит от всех виджетов (последний). `test/utils/pump_app.dart` — предпосылка всех golden/widget-тестов. Полная привязка к `FR-*`/`SC-*` и проверка экранов — в `quickstart.md`.
