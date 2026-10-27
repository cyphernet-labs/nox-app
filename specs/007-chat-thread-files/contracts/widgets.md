# Contract — Публичные API виджетов + BLoC/форматтер/enum контракты (M4)

Новые виджеты — токен-дисциплина, `NoxIcons` SVG, копирайт через `TextConstants`, `const`-конструкторы где возможно, имена `App*Widget`. Все резолвятся под `pumpApp`. `ChatThreadPage`/`ChatCardPage` владеют BLoC; `FileViewPage` — без BLoC.

## widgets/chat/ — лента

### `AppComposerWidget` (UPGRADE — было display-only)
Редактируемый composer (5.2 §9.8).
```
AppComposerWidget({
  super.key,
  required TextEditingController controller,
  FocusNode? focusNode,
  Widget? attachment,                 // AppFileChipWidget(removable: true) над строкой
  required bool sendActive,
  ValueChanged<String>? onChanged,
  VoidCallback? onAttach,
  VoidCallback? onSend,
  VoidCallback? onSubmitted,
})
```
- Растущий `TextField` (`maxLines: 4–6`, далее внутренний скролл, placeholder `composerHint`='Message'), attach (`NoxIcons.attachFile`, tooltip `tooltipAttachFile`) слева, send (`NoxIcons.sendFill`, tooltip `tooltipSend`) справа — `primary` когда `sendActive`, иначе `onSurface`@38%. `surfaceContainer` + top-divider. **NB**: старый API (`value: String`) удаляется — обновить `ui_kit_page` + 3 теста.

### `AppThreadViewWidget` (общий body ленты)
Переиспользуют мобайл-страница (5.2) и десктоп thread-pane (5.1). **Единственный владелец `ChatThreadBloc`** (создаёт в `initState` по `chat.id`, `close()` в `dispose`) — `ChatThreadPage`/5.1 thread-pane его лишь хостят, своего BLoC не создают (устраняет двойное владение).
```
AppThreadViewWidget({ super.key, required ChatModel chat, bool demo = false, bool showHeader = false })
```
- `BlocProvider`(ChatThreadBloc..initialize(chat.id)); обратный (`reverse:true`) `PagedListView<String, MessageModel>` (bubbles + `AppDateSeparatorWidget` + `AppAuthorHeaderWidget` + `AppSystemLineWidget` + Loading-older сверху) над composer. `showHeader:true` (десктоп) → `AppThreadHeaderWidget` сверху. Состояния `state.when(initializing/initialized/error)`; offline → `MaterialBanner`.

### `AppThreadHeaderWidget` (десктоп persistent header)
```
AppThreadHeaderWidget({ super.key, required ChatModel chat, required VoidCallback onInfo })
```
- `AppAvatarWidget(chat.name)` + имя (`titleMedium`, tap→`onInfo`) + info-кнопка (`NoxIcons.folderOpen`, tooltip `Chat info`, →`onInfo`). **Реконсилирован под NOX** — без members/search/folder (корпус-дрейф). `surface` + bottom-divider.

### `AppDateSeparatorWidget`
```
AppDateSeparatorWidget({ super.key, required String label })   // Today / Yesterday / 12 May
```
- Центрированная капсула (`surfaceContainerHigh`, `labelSmall`/`onSurfaceVariant`). label считает `DateFormatter` (date-separator: Today/Yesterday/`d MMM`).

### `AppAuthorHeaderWidget`
```
AppAuthorHeaderWidget({ super.key, required String label })   // текущий label автора над группой чужих
```
- Левый `labelMedium`/`primary`; рендерится один раз над группой (group-by `authorId`).

### `AppSystemLineWidget`
```
AppSystemLineWidget({ super.key, required String text })   // 'Chat created by {username}'
```
- Центрированный `bodySmall`/`onSurfaceVariant`; не считается сообщением.

### Reuse (без изменений)
- `AppMessageBubbleWidget({required isOwn, text?, required time, status=none, file?, isLast})` — статусы `schedule`/`check`/`error` уже есть. (EDIT только импорт `MessageStatus` из domain.)
- `AppFileChipWidget({required type, required name, required size, inBubble, onColor, removable, onRemove})` — chip в bubble / draft в composer (`size` = `FileSizeFormatter.format`).

## widgets/shell/

### `AppSideSheetWidget` / `showRightSideSheet` (десктоп 5.4 drawer)
```
Future<T?> showRightSideSheet<T>(BuildContext context, { required Widget child, double width = 380 })
```
- `showGeneralDialog` — slide-in справа (`NoxDuration`/`NoxEasing`), scrim (`barrierColor`), панель `width` (`surface`). Содержимое 5.4 = `ChatCardBody(scope: drawer)`.

## pages/file_view_page/ (БЕЗ BLoC)

### `FileViewPage` / `showFileView`
```
FileViewPage({ super.key, required MessageAttachment file, bool demo = false });
Future<void> showFileView(BuildContext context, MessageAttachment file)   // мобайл push / десктоп showDialog lightbox(520)
```
- Локальный state: `_progress`, `_cached`. Мобайл `Scaffold(AppBar back + name(ellipsis) + Save)` + центр column (`AppFileGlyphWidget(box: большой)` + name + size + `LinearProgressIndicator` при Loading). Десктоп lightbox-`Dialog`(520): header(глиф+name+download+close) + глиф + name + size + `Download`/`Downloading… {n}%`. `Save`/`Download` → no-op + snackbar `savedToDownloads`.

## Контракты BLoC

Конвенция (по `ChatsListBloc`/`ItemListBloc`): `class <X>Bloc extends BaseBloc<<X>Event, <X>State>`; ctor регистрирует `on<…>` (transformer где нужно); `executeLogic(…, onError:)` обязателен для async; страница/виджет владеет BLoC.

```
// ChatThreadBloc (sealed, зеркалит ItemListBloc; + optimistic outgoing)
ChatThreadBloc() : super(const ChatThreadState.initializing()) {
  on<Initialize>(_onInitialize);                                   // currentId = IdentityMockData.currentUserId; add(LoadOlder reset)
  on<LoadOlder>(_onLoadOlder, transformer: sequential());          // getIt<MessageRepository>().getMessages → applyPage
  on<MessageSent>(_onSend);                                        // optimistic: outgoing += pending → sendMessage → sent/error
  on<SendRetried>(_onRetry);
  on<AttachmentPicked>(_onAttach);    on<AttachmentRemoved>(_onRemoveAttach);
  on<SetScenario>(_onSetScenario);    // debug: offline/inline-error/fatal/empty/send-error
}

// ChatCardBloc (sealed)
ChatCardBloc() : super(const ChatCardState.initializing()) {
  on<Initialize>(_onInitialize);                                   // getIt<ChatRepository>().getChatFiles(chatId)
  on<ViewModeChanged>(_onViewMode);                               // list ↔ grid
  on<SetScenario>(_onSetScenario);    // debug: offline/inline-error/fatal/empty
}
```

| BLoC | Тип состояния | Events | Заметки |
|---|---|---|---|
| `ChatThreadBloc` | sealed `Initializing/Initialized/Error` + `PagingState` + `outgoing` | `initialize(chatId)`, `loadOlder` (`sequential()`), `messageSent`, `sendRetried`, `attachmentPicked/Removed`, `setScenario` (debug) | network-only carve-out #2; `getIt<MessageRepository>`; optimistic send; `onError` обязателен |
| `ChatCardBloc` | sealed `Initializing/Initialized/Error` | `initialize(chatId)`, `viewModeChanged`, `setScenario` (debug) | `getIt<ChatRepository>().getChatFiles`; без пагинации |

## Форматтер

### `FileSizeFormatter` (`lib/general/formatters/file_size_formatter.dart`)
```
static String format(int bytes)   // 'B' / 'KB' / 'MB' / 'GB', 1 дробный для KB+, intl NumberFormat
```
- Используют 5.3 (размер), 5.4 (строки/ячейки), `AppFileChipWidget.size` (из `MessageAttachment.sizeBytes`). Unit-тест границ (0 B / <1KB / KB / MB / GB).

## Продвижение enum'ов (Принцип III — `domain` import-free)

| Enum | Новое место | Затронуто (EDIT import) |
|---|---|---|
| `MessageStatus {none,pending,sent,error}` | `lib/domain/model/chat/message_status.dart` | `app_message_bubble_widget.dart`, `ui_kit_page.dart`, тесты bubble |
| `FileType {image…other}` | `lib/domain/model/file/file_type.dart` | `primitives/file_type.dart` (мапперы остаются), `app_file_chip_widget.dart`, `app_file_glyph_widget.dart`, `ui_kit_page.dart`, тесты |

## Темы стоковых компонентов

| Тема | Для | Статус |
|---|---|---|
| `ProgressIndicatorThemeData` | 5.3 `LinearProgressIndicator` | **опц.** — добавить в `nox_component_themes.dart` только при необходимости; default `ColorScheme` приемлем |

> `Dialog`/bottom-sheet/`Divider`/`SegmentedButton`/`MaterialBanner` уже тематизированы (M1–M3). Новых обязательных тем нет.

## Переиспользуемые сущности (без изменений)

| Сущность | Сигнатура | Роль в M4 |
|---|---|---|
| `AppFileGlyphWidget` | `const ({required FileType type, double iconSize=24, double box=44})` | 5.3 крупный глиф, 5.4 grid-ячейка |
| `AppAvatarWidget` | `const ({required String name, double size=40})` | 5.4 header (size:56), ThreadHeader |
| `AppSegmentedWidget<T>` | `const ({required Map<T,String> options, required T selected, required ValueChanged<T> onChanged})` | 5.4 List/Grid |
| `AppEmptyContentWidget` | `const ({required SvgGenImage illustration, required title, required message})` | 5.2 Empty / 5.4 Empty-files |
| `AppProgressWidget`/`AppErrorWidget` | `const ({…})` | Initial-loading / Error→3.1 |
| `AppListDetailWidget`/`AppDetailEmptyWidget` | M3 | десктоп 5.1 host для 5.2 thread-pane / no-selection |
| `showAppSnackBar`/`showAppBanner` | `(context, {…})` | 5.3 `Saved to Downloads`/retry, 5.2/5.4 offline-баннер |
| `DateFormatter` | `static time/relative + (date-sep helper)` | bubble `HH:mm` + date-separator |
| `ChatModel`/`ChatRepository` | M3 (+`getChatFiles`) | вход 5.2/5.4 |

## Микрокопия (`TextConstants`, ≈22 EN-строк)

5.2: `tooltipRetry`='Tap to retry', `threadEmptyTitle`='No messages yet', `threadEmptyMessage`='Send the first one.', `systemChatCreated`='Chat created by {username}', `dateToday`='Today', `dateYesterday`='Yesterday', `tooltipChatInfo`='Chat info'. (`Today`/`Yesterday` живут в `TextConstants`; `DateFormatter` date-sep-хелпер их возвращает, дату — `d MMM`.) (reuse `composerHint`/`tooltipSend`/`tooltipAttachFile`/`tooltipRemove`/`tooltipBack`/`noConnection`.)
5.3: `tooltipSave`='Save', `savedToDownloads`='Saved to Downloads', `fileDownloadError`='Could not download file. Check your connection and try again.', `actionDownload`='Download', `downloadingProgress`='Downloading… {n}%'.
5.4: `filesSectionTitle`='Files', `filesViewList`='List', `filesViewGrid`='Grid', `filesEmptyTitle`='No files yet', `filesEmptyMessage`='Files sent in this chat will appear here.', `chatInfoTitle`='Details', `chatInfoLoadError`='Could not load chat info. Check your connection and try again.'.

## Контракт тестов

- Каждый новый `App*Widget`/`*Page`/`*Body`: widget-тест + golden (light/dark) под `test/presentation/{widgets/chat,pages/...}`. Прогресс-голдены (`LinearProgressIndicator`, Loading-older) — `settle: false`.
- `ChatThreadBloc`: `bloc_test` (bare `Initializing`/`Initialized`/`Error`; paging старых; optimistic `pending→sent`; `error`+retry; offline) против test-env DI (`MessageRepository` env `test`); `Error` только при `onError`.
- `ChatCardBloc`: `bloc_test` (loaded list/grid; empty; viewMode; offline/error).
- `FileViewPage`: widget+golden (loading %/loaded; мобайл/десктоп) — **без** bloc_test.
- `FileSizeFormatter.format`: unit-тест границ.
- 5.1-тесты M3: обновить (тап → `ChatThreadPage`; thread-pane → `AppThreadViewWidget`).
- Микрокопия — только из `TextConstants`; в тестах ассертить по константам.
