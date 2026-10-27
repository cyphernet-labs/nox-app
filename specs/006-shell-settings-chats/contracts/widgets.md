# Contract — Публичные API новых виджетов + BLoC/тема контракты (M3)

Новые виджеты — токен-дисциплина, `NoxIcons` SVG, копирайт через `TextConstants`, `const`-конструкторы где возможно, имена `App*Widget`. Все резолвятся под `pumpApp`. `TabBarShell` — без BLoC; `ChatsListPage`/`SettingsRootPage` владеют BLoC.

## widgets/shell/

### `TabBarShell` (4.1) — без BLoC
Адаптивный шелл; хостит реальные 5.1+7.1 как табы.
```
TabBarShell({ super.key })   // StatefulWidget; static Route<void> route()
```
- `AppTab _active` (reuse enum из `app_bottom_bar_widget.dart`) + `setState`; body `IndexedStack(index: _active.index, children: [ChatsListPage, SettingsRootPage])`; cross-fade `NoxDuration.tabFade` (150мс) + `NoxEasing.standard`.
- `LayoutBuilder` по `Constants.railBreakpoint` (840): мобайл `Scaffold(bottomNavigationBar: AppBottomBarWidget(active:_active, onSelect:…), floatingActionButton: AppCreateFabWidget(onPressed:_onCreate), floatingActionButtonLocation: centerDocked)`; десктоп `Scaffold(body: Row[AppNavigationRailWidget(active, onSelect, onCreate), VerticalDivider(1), Expanded(body)])`.
- `_onCreate` → `Navigator.push(CreateChatPage.route())`. Системный back (`PopScope`): не-Chats→`chats`; Chats→`SystemNavigator.pop` (`// TODO(backend):` в превью). Re-tap Chats→scroll-to-top (callback к 5.1).

### `AppNavigationRailWidget` (десктоп rail)
```
AppNavigationRailWidget({ super.key, required AppTab active, required ValueChanged<AppTab> onSelect, required VoidCallback onCreate })
```
- `NavigationRail` (две цели: `NoxIcons.forum/forumFill` `Chats`, `settings/settingsFill` `Settings`; selected `primary`) + **leading** `AppCreateFabWidget(onPressed: onCreate)` (как `AppShell._buildRail`). Тема — `NavigationRailThemeData` (добавляется).

### `AppListDetailWidget` (двухпанельный контейнер)
```
AppListDetailWidget({
  super.key,
  required Widget listPane,
  required Widget detailPane,     // detail или no-selection слот
  double listPaneWidth = 360,     // 5.1=360, 7.1=340
})
```
- `Row[ConstrainedBox(width: listPaneWidth, child: listPane), VerticalDivider(1), Expanded(child: detailPane)]`. Highlight выбранной строки — `secondaryContainer` (на стороне list-pane item). Без push. Используется десктоп 5.1 (list 360 + thread-pane) и 7.1 (menu 340 + detail ≤680).

## widgets/settings/

### `AppIdentityCardWidget` (7.1)
Карта идентичности; параметризуется по раскладке (Принцип I — десктоп без raw-reveal).
```
AppIdentityCardWidget({
  super.key,
  required String name,
  required String maskedId,        // '••••••••' (8 точек)
  required String rawId,           // для Copy / reveal (мобайл)
  required bool revealable,        // мобайл true (Show/Hide), десктоп false
  required bool showInlineQr,      // десктоп true (inline account-QR)
  Widget? nameEditField,           // inline AppLabeledFieldWidget когда editing
  required VoidCallback onEditName,
  required VoidCallback onCopy,
  required VoidCallback onShowQr,
  bool idRevealed = false,         // мобайл toggle
  VoidCallback? onToggleReveal,
})
```
- filled `Card` (`noxCardTheme`); generated avatar (`AppAvatarWidget(name)` → `noxInitials`/`noxAvatarColor`). Name-блок: label `usernameLabel` + name + edit-pencil (`NoxIcons.edit`, tooltip `Edit`); editing → `nameEditField`. `Your ID`-блок: label `loginIdLabel` + (`idRevealed && revealable` ? rawId `AppTextStyleTokens.monoBody` wrap : `maskedId`) + action-row: `revealable` ? `Show/Hide`(`NoxIcons.visibility`/`visibilityOff`) · `Copy`(`contentCopy`) · `Show QR`(`qrCode`) : `Copy` · `Show QR` + inline `AppQrSurfaceWidget` (если `showInlineQr`).

### `AppSettingsNavRowWidget` (7.1)
```
AppSettingsNavRowWidget({ super.key, required String title, required VoidCallback onTap, Color? color })
```
- `ListTile(title, onTap)` (`noxListTileTheme`); `color` — для `Log out` (`ColorScheme.error`). Без leading/trailing glyph (спека icon-less; `chevron`/`logout` SVG отсутствуют и не требуются).

### `AppLogoutDialogWidget` (7.1)
```
AppLogoutDialogWidget({ super.key, required bool loading, required VoidCallback onConfirm, required VoidCallback onCancel })
```
- `AlertDialog` (`noxDialogTheme`): title `Log out?`, content logout-message, actions `Cancel`(`TextButton`, `actionCancel`) + `Log out`(`FilledButton`, `ColorScheme.error`). `loading` → confirm-кнопка disabled + `AppSpinnerWidget`, диалог модален (не закрывается) до перехода на 1.1.

### `AppQrSurfaceWidget` (7.1) — brand-fixed (§9.10)
```
AppQrSurfaceWidget({ super.key, required String data, double size = 220 })
```
- **fake-QR** (нейтральный детерминированный паттерн из `data`) на brand-fixed светлой поверхности: bg `NoxBrand.qrSurface` (#FFFFFF), модули `NoxBrand.qrInk` (#0C0C0C), quiet-zone. **Вне `ColorScheme`** (одинаково light/dark) — второе brand-fixed исключение (design-system §9.10). raw-ID текстом НЕ показывается. Реальное QR-кодирование — `// TODO(backend):` (без `qr_flutter`). Показывается: мобайл `showModalBottomSheet` (`noxBottomSheetTheme`, drag-handle, `Your ID QR`, `Close`), десктоп `showDialog` (`noxDialogTheme`).

## widgets/chat/

### `AppSearchFieldWidget` (5.1) — РЕДАКТИРУЕМОЕ поле
```
AppSearchFieldWidget({
  super.key,
  required TextEditingController controller,
  ValueChanged<String>? onChanged,   // debounced снаружи (debounceRestartable в bloc)
  String hint = TextConstants.searchHint,
})
```
- Редактируемый `SearchBar`/`TextField` (`SearchBarThemeData`), suffix `NoxIcons.search`. **NB**: существующий `AppSearchBarWidget` — display-only (`onTap` only, нет `TextField`/`onChanged`) — не editable; 5.1 требует ввод → отдельный виджет.

## Извлечённые body-виджеты M1 (для desktop detail-pane 7.1)

Извлечь body каждого M1-подэкрана в ПУБЛИЧНЫЙ виджет (без `Scaffold`/`AppBar`/back); страница-мобайл = `AppDetailScaffoldWidget(body: …Body)`; desktop 7.1 detail-pane = тот же `…Body`.

| Виджет | Из | Заметка |
|---|---|---|
| `NotificationsBody` | `notifications_page.dart` | извлечь inline-body (banner + switch-row + debug) |
| `AppearanceBody` | `appearance_page.dart` | reads/writes `AppRootBloc` (живой свитч темы) |
| `LanguageBody` | `language_page.dart` | `RadioGroup<AppLanguage>` |
| `AboutBody` | `about_page.dart` | version ListTile + `AppVersionTextWidget` |
| `TermsBody` | `terms_page.dart` | приватный `_TermsBody` → **сделать public** |

## Темы стоковых компонентов (добавить в `nox_component_themes.dart` + `AppTheme._build`)

| Тема | Для | Ключевое |
|---|---|---|
| `SearchBarThemeData` | 5.1 `AppSearchFieldWidget` | `surfaceContainerHigh`, `level2`, `NoxRadius.full`/`s` |
| `MaterialBannerThemeData` | 5.1 офлайн/inline-error (`showAppBanner`) | `surfaceContainer`, `level3` |
| `BadgeThemeData` | 5.1 unread бейдж | `backgroundColor: cs.primary` (НЕ стоковый error-red); cap `99+` в логике виджета |
| `NavigationRailThemeData` | 4.1 десктоп rail | selected `primary`, label all |

> `BottomAppBar` тематизируется на уровне `AppBottomBarWidget` (отдельная тема не нужна). Logout-row `ColorScheme.error` — override на месте вызова.

## Переиспользуемые виджеты/страницы (без изменений)

| Сущность | Сигнатура | Роль в M3 |
|---|---|---|
| `AppBottomBarWidget` | `const ({required AppTab active, required ValueChanged<AppTab> onSelect})` | Мобайл-bar шелла. |
| `AppCreateFabWidget` | `const ({VoidCallback? onPressed})` | Center-docked `+`. |
| `AppWordmarkWidget` / `AppSplashHairlineWidget` | `const ({Color? color})` / `const () PreferredSize` | 5.1 AppBar (NOX + hairline). |
| `AppWindowTitlebarWidget` | `const ({required String title})` | (опц.) десктоп faux-titlebar. |
| `AppThemeToggle` | `const ()` | AppBar action (light/dark). |
| `AppChatItemWidget` | `const ({required name, required preview, required time, int unread=0, VoidCallback? onTap})` | 5.1 строка (`time` — готовая строка). |
| `AppAvatarWidget` | `const ({required String name, double size=40})` | Generated avatar (5.1 + identity-card). |
| `AppEmptyContentWidget` | `const ({required SvgGenImage illustration, required title, required message})` | 5.1 Empty (`Assets.svg.illustrations.emptyChats`). |
| `AppErrorWidget` / `AppProgressWidget` | `const ({String? message, VoidCallback? onTryAgain})` / `const ({double size=24})` | 5.1 error / initial-loading. |
| `AppLabeledFieldWidget` | `const (…maxLength, checking, errorText…)` | 7.1 inline name-edit (maxLength:32). |
| `showAppBanner` / `showAppSnackBar` | `(context, {required text, …})` | 5.1 офлайн-баннер / 7.1 `Copied to clipboard`. |
| `AppDetailScaffoldWidget` | `const ({required title, required body, actions, maxContentWidth=640})` | Мобайл M1-подэкраны (как сейчас) — НЕ для desktop detail-pane (владеет AppBar/back). |
| `RoutePlaceholderPage` | `static Route<void> route({required String destinationLabel})` | 5.1→5.2 / desktop thread-pane. |
| `CreateChatPage` | `static Route<void> route()` | `+` (self-adapts мобайл/десктоп). |
| `SplashPage` / `Notifications/Appearance/Language/Terms/About Page` | `static Route<void> route()` | Logout-таргет / 7.1 строки (мобайл push). |

## Контракты BLoC

Конвенция (по `CreateChatBloc`/`ItemListBloc`): `class <X>Bloc extends BaseBloc<<X>Event, <X>State>`; ctor регистрирует `on<…>` (transformer где нужно); `executeLogic(…, onError: …)` для async; страница владеет BLoC (`late final` в `initState`, `close()` в `dispose`, `BlocProvider.value` + `BlocBuilder`/`BlocConsumer`). `BaseStatePage` — `lib/presentation/pages/base/base_state_page.dart` (не владеет BLoC; hand-rolled).

```
// ChatsListBloc (sealed, зеркалит ItemListBloc)
ChatsListBloc() : super(const ChatsListState.initializing()) {
  on<Initialize>(_onInitialize);
  on<LoadChats>(_onLoadChats, transformer: sequential());          // bloc_concurrency
  on<SearchChanged>(_onSearchChanged, transformer: debounceRestartable());
  on<ChatSelected>(_onChatSelected);   // desktop view-state
  on<SetOffline>(_onSetOffline);       // debug
}
// _onLoadChats: getIt<ChatRepository>().getChats(config) внутри executeLogic(onError: emit(error));
//   result.match(onData: applyPage, onError: …); re-check state is Initialized после await.

// SettingsRootBloc (value-state, зеркалит SetUsernameBloc)
SettingsRootBloc() : super(const SettingsRootState()) {
  on<NameChanged>(_onNameChanged);                                  // immediate charset
  on<NameAvailabilityRequested>(_onAvailability, transformer: debounceRestartable());
  on<NameSubmitted>(_onSubmit);
  on<LogoutConfirmed>(_onLogout);   // executeLogic(onError:) → SplashPage
  // … nameEditStarted/Cancelled, idRevealToggled, copyRequested, setOutcome(debug), navigationHandled
}
```

| BLoC | Тип состояния | Events | Заметки |
|---|---|---|---|
| `ChatsListBloc` | sealed `Initializing/Initialized/Error` + `PagingState` | `initialize`, `loadChats(reset)`, `searchChanged` (debounced), `chatSelected` (desktop), `setOffline` (debug) | network-only carve-out; `getIt<ChatRepository>`; `sequential()`; `onError` обязателен. |
| `SettingsRootBloc` | value-state (`abstract` + `._()` + getters) | `initialize`, `nameEditStarted/Changed/AvailabilityRequested(debounced)/Submitted/EditCancelled`, `idRevealToggled`, `copyRequested`, `logoutRequested/Confirmed`, `setOutcome(debug)`, `navigationHandled` | name-edit reuse 2.3 (charset + case-sensitive `takenUsernames`); Logout→Splash. |

## Контракт тестов

- Каждый новый `App*Widget`/`*Body`: widget-тест + golden (light/dark) под `test/presentation/widgets/{shell,settings,chat}/`. Спиннер/QR-голдены — `settle: false` где анимация.
- `AppQrSurfaceWidget` golden фиксирует brand-fixed (#FFFFFF / #0C0C0C) одинаковыми в light и dark.
- `ChatsListBloc`: `bloc_test` (bare `Initializing`/`Initialized`/`Error`; paging; search reset; offline; `Error` только при `onError`) против test-env DI (`ChatRepository` env `test`).
- `SettingsRootBloc`: `bloc_test` (name-edit charset/checking/valid/taken; save; logout-phase).
- `TabBarShell`: widget+golden (мобайл bottom-bar / десктоп rail; tab-switch сохраняет состояние; `+` пушит).
- `DateFormatter.relative`: unit-тест границ лестницы (now/min/h/Yesterday/d MMM/d MMM y).
- Микрокопия — только из `TextConstants`; в тестах ассертить по константам.
