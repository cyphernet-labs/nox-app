# Contract — Публичные API новых виджетов M1

Новые переиспользуемые виджеты — без BLoC, токен-дисциплина, `NoxIcons` SVG, копирайт через `TextConstants`. Конструкторы `const` где возможно. Имена — `App*Widget` (как в kit). Все должны корректно резолвиться под `pumpApp`.

## shell/

### `AppDetailScaffoldWidget`
Адаптивная обёртка leaf-экрана (мобайл fullscreen ↔ десктоп width-capped панель).
```
AppDetailScaffoldWidget({
  required String title,        // из TextConstants
  required Widget body,
  List<Widget>? actions,        // в AppBar (опц.)
  double maxContentWidth = 640, // десктоп cap
})
```
- Мобайл (<840): `Scaffold(appBar: AppBar(title, leading: back, actions), body: body)`.
- Десктоп (≥840): тот же `AppBar`; `body` в `Center`→`ConstrainedBox(maxWidth: maxContentWidth)`.
- Брейкпоинт — `Constants.railBreakpoint` (`LayoutBuilder`).

### `AppWindowTitlebarWidget`
Faux desktop TitleBar (НЕ нативный оконный чром) — текстовая полоса заголовка для десктопной раскладки Error.
```
AppWindowTitlebarWidget({ required String title })  // PreferredSizeWidget или обычная полоса
```
- Фон `surfaceContainer`, текст `titleSmall onSurfaceVariant`, тонкая нижняя граница (`context.appColors.dividerSubtle`/`outlineVariant`).

## settings/

### `AppThemeOptionWidget`
Карточка выбора темы (Appearance): мини-превью + label + индикатор выбора.
```
AppThemeOptionWidget({
  required String label,        // 'System' | 'Light' | 'Dark'
  required Widget preview,      // мини-превью (маленький токенизированный thumbnail)
  required bool selected,
  required VoidCallback onTap,
})
```
- `selected` → рамка `primary` + галочка (`NoxIcons.check`); single-select обеспечивает родитель.
- Tap-target ≥48; `Semantics(button:true, selected:)`.

### `AppSettingsSwitchRowWidget`
Строка-переключатель настройки (Notifications).
```
AppSettingsSwitchRowWidget({
  required String title,
  String? supportingText,
  required bool value,
  required ValueChanged<bool> onChanged,
})
```
- Базируется на `SwitchListTile` (тема стоковая); supporting text — `bodySmall onSurfaceVariant`.

### `AppInfoBannerWidget`
Информационный баннер (denied-разрешение) — стиль `MaterialBanner`.
```
AppInfoBannerWidget({
  required SvgGenImage icon,      // NoxIcons.* (напр. NoxIcons.error)
  required String message,
  required String actionLabel,    // напр. 'Open settings'
  required VoidCallback onAction,
})
```
- Иконка — `AppIconWidget(icon)`; фон `surfaceContainer`/`secondaryContainer`; одно текстовое действие.

## pages/error_page/

### `AppErrorPage` + `ErrorPageParams`
См. [navigation.md](./navigation.md) (route) и [data-model.md](../data-model.md) (`ErrorPageParams`, `ErrorPageMode`).
```
ErrorPageParams({
  required SvgGenImage icon,      // NoxIcons.*
  required String title,
  required String message,
  ErrorPageMode mode = ErrorPageMode.embedded,
  Future<void> Function()? onRetry,
})
// пресеты:
ErrorPageParams.fatal({ ErrorPageMode mode })    // 'Something went wrong'
ErrorPageParams.network({ ErrorPageMode mode })  // 'Could not ... Check your connection and try again.'
```
- `embedded` → `AppBar`(back); `blocking` → нет `AppBar`, `PopScope(canPop:false)`.
- `Try again` → состояние `Retrying` (спиннер) на время `onRetry()`; в превью `onRetry` — фейковый `Future.delayed`.
- Десктоп — `AppWindowTitlebarWidget` + иконка 96.

## Контракт тестов виджетов

- Каждый новый `App*Widget`: widget-тест (рендер + интеракция) + golden (light/dark) под `test/presentation/widgets/{shell,settings}/`.
- Микрокопия — только из `TextConstants`; в тестах ассертить по константам.
