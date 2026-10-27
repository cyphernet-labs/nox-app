# Contract — публичная Dart-поверхность UI-кита

UI-контракт фичи: набор публичных символов, который кит предоставляет страницам/экранам NOX. Это «интерфейс» приложения-библиотеки (виджеты вместо REST). Все символы импортируются полными путями `package:nox_app/presentation/widgets/...`. Сигнатуры — нормативные (props, дефолты, типы коллбэков); реализация — в `tasks`/implement.

> Конвенции: классы виджетов — `App*Widget`; enum'ы виджет-API — без `Nox`-префикса; иконки — `SvgGenImage` из `NoxIcons`; цвета/типографика/shape/spacing — токены (виджеты не принимают сырые `Color`/`TextStyle`, кроме явных brand-overrides вроде `AppWordmarkWidget.color`).

## Примитивы — `widgets/primitives/`

```dart
class AppIconWidget extends StatelessWidget {
  const AppIconWidget(this.icon, {super.key, this.size = 24, this.color, this.fill = 0});
  final SvgGenImage icon;   // NoxIcons.*
  final double size;
  final Color? color;       // default cs.onSurfaceVariant
  final double fill;        // 0 outlined · 1 filled
}

class AppSpinnerWidget extends StatelessWidget {
  const AppSpinnerWidget({super.key, this.size = 24, this.color, this.strokeWidth = 3});
}

class AppAvatarWidget extends StatelessWidget {
  const AppAvatarWidget({super.key, required this.name, this.size = 40});
}

class AppFileGlyphWidget extends StatelessWidget {
  const AppFileGlyphWidget({super.key, required this.type, this.iconSize = 24, this.box = 44});
  final FileType type;
}

enum FileType { image, video, audio, pdf, doc, sheet, text, archive, other }
SvgGenImage noxFileIcon(FileType type);
Color noxFileColor(FileType type);
```

## Composite (чат/сообщения) — `widgets/chat/`

```dart
class AppSearchBarWidget extends StatelessWidget {
  const AppSearchBarWidget({super.key, this.value, this.hint = TextConstants.searchHint, this.onTap});
  final String? value; final String hint; final VoidCallback? onTap;
}

class AppChatItemWidget extends StatelessWidget {
  const AppChatItemWidget({super.key, required this.name, required this.preview,
      required this.time, this.unread = 0, this.onTap});
}

class AppFileChipWidget extends StatelessWidget {
  const AppFileChipWidget({super.key, required this.type, required this.name, required this.size,
      this.inBubble = false, this.onColor, this.removable = false, this.onRemove});
  final FileType type;
}

enum MessageStatus { none, pending, sent, error }

class AppMessageBubbleWidget extends StatelessWidget {
  const AppMessageBubbleWidget({super.key, required this.isOwn, this.text, required this.time,
      this.status = MessageStatus.none, this.file, this.isLast = false});
  final Widget? file; // обычно AppFileChipWidget
}

class AppComposerWidget extends StatelessWidget {
  const AppComposerWidget({super.key, this.value, this.attachment, this.sendActive = false,
      this.onAttach, this.onSend});
  final Widget? attachment; // обычно AppFileChipWidget(removable: true)
}

class AppSegmentedWidget<T> extends StatelessWidget {
  const AppSegmentedWidget({super.key, required this.options, required this.selected, required this.onChanged});
  final Map<T, String> options; final T selected; final ValueChanged<T> onChanged;
}
```

## Оболочка — `widgets/shell/`

```dart
class AppSplashHairlineWidget extends StatelessWidget implements PreferredSizeWidget {
  const AppSplashHairlineWidget({super.key});
}

class AppWordmarkWidget extends StatelessWidget {
  const AppWordmarkWidget({super.key, this.color});
}

enum AppTab { chats, settings }

class AppBottomBarWidget extends StatelessWidget {
  const AppBottomBarWidget({super.key, required this.active, required this.onSelect});
  final AppTab active; final ValueChanged<AppTab> onSelect;
}

class AppCreateFabWidget extends StatelessWidget {
  const AppCreateFabWidget({super.key, this.onPressed});
}
```

## Generic state-виджеты — `widgets/state/`

```dart
class AppProgressWidget extends StatelessWidget {
  const AppProgressWidget({super.key, this.size = 24});
}

class AppErrorWidget extends StatelessWidget {
  const AppErrorWidget({super.key, this.message, this.onTryAgain});
}

class AppEmptyContentWidget extends StatelessWidget {
  const AppEmptyContentWidget({super.key, required this.illustration, required this.title, required this.message});
  final SvgGenImage illustration; // Assets.svg.illustrations.*
}
```

## Каналы обратной связи — `presentation/helpers/app_feedback_helper.dart`

```dart
void showAppSnackBar(BuildContext context, {required String text, String? actionLabel,
    VoidCallback? onAction, bool error = false});

void showAppBanner(BuildContext context, {required String text, SvgGenImage? icon,
    String? actionLabel, VoidCallback? onAction});
```

## Тема stock-виджетов — `design/theme/`

```dart
// nox_component_themes.dart — функции от ColorScheme:
InputDecorationTheme noxInputDecorationTheme(ColorScheme cs);
FilledButtonThemeData noxFilledButtonTheme(ColorScheme cs);
// ... textButton, iconButton, segmentedButton, switch, radio, listTile, progressIndicator, dialog, bottomSheet, card, snackBar, appBar

// app_theme.dart — AppTheme._build подключает их в ThemeData(...).
```

## Контракт-инварианты (проверяемые)

1. Ни один публичный виджет не принимает `Color`/`EdgeInsets`/`TextStyle` для тематических значений (исключение — явные brand-overrides `AppWordmarkWidget.color`, `AppFileChipWidget.onColor`).
2. Ни один виджет не зависит от `getIt`/репозиториев/`BuildContext`-навигации и не держит BLoC.
3. Все интерактивные элементы экспонируют коллбэк (`onTap`/`onSend`/`onChanged`/`onRemove`/`onSelect`/`onPressed`/`onTryAgain`) — поведение задаёт страница-владелец.
4. Иконочные параметры — `SvgGenImage` (`NoxIcons.*`), не `IconData`.
5. Каждый публичный `App*Widget` имеет файл golden-теста и widget-теста в зеркальном пути под `test/`.
