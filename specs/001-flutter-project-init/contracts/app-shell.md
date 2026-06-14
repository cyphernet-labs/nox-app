# Контракт: адаптивная оболочка (`AppShell`)

> **Источник:** блюпринт `docs/blueprints/mobile/05-presentation-layer.md` §6.5; требование FR-004. Референсы дизайна: десктопная раскладка — `docs/design/system/nox-desktop-screens/`; мобильный нижний бар — locked-спека `docs/design/spec/screens/tab-bar-shell.md`.

## 1. Переключение — width-driven, не Platform

`AppShell` (`lib/presentation/app/widgets/app_shell.dart`) — `LayoutBuilder`-обёртка между `AppRoot` и страницей. Раскладка выбирается по **ширине окна**, а **не** по `Platform`:

- порог — `constraints.maxWidth >= Constants.railBreakpoint`, где `Constants.railBreakpoint = 840` (dp; граница M3 medium→expanded), задан в `lib/general/constants.dart`;
- большое окно на десктопе и большой планшет получают одинаковую (desktop) раскладку; узкое окно на десктопе остаётся на мобильной;
- один и тот же size-driven код корректен на всех пяти таргетах (iOS, Android, Windows, Linux, macOS).

`flutter_adaptive_scaffold` / `custom_adaptive_scaffold` **не используются** — брейкпоинт кастомный.

## 2. Две ветки раскладки

**Mobile** (`maxWidth < railBreakpoint`): `Scaffold` с нижним баром из трёх слотов — `Chats` / центральный docked `+` FAB / `Settings`. Бар — **кастомный** `BottomAppBar` (`CircularNotchedRectangle`) + `FloatingActionButton` в `floatingActionButtonLocation: centerDocked` (стоковый `NavigationBar` не умеет docked-FAB с вырезом).

**Desktop** (`maxWidth >= railBreakpoint`): `Row[ NavigationRail(width: 80, extended: false, labelType: NavigationRailLabelType.all, leading: FloatingActionButton(child: Icon(Icons.add))), VerticalDivider(width: 1), Expanded(body) ]` — `leading`-FAB рейла и есть «доковый» `+`.

## 3. Общее для обеих веток

- **Ровно две destination'ы:** `Chats` = `Icons.forum`, `Settings` = `Icons.settings`.
- **`+`** — третий навигационный элемент (создание чата), docked FAB на мобиле / leading FAB рейла на десктопе.
- Индикатор выбранной destination — стоковый M3 `secondaryContainer`.
- **`body` — `IndexedStack`** (сохраняет состояние вкладок при переключении).
- **Аватар аккаунта из десктопного корпуса опущен** — в NOX нет profile-экрана (карта экранов).
- **Single-window** — оболочка не вводит multi-window; маршрутизация остаётся в единственном `Navigator`/`AppRootBloc` (`desktop_multi_window` / `window_manager` не используются).

## 4. Скелет Feature-001 (FR-013 — без реальных фич)

- Обе destination'ы ведут на **одну** страницу-плейсхолдер `Item` (та же, что в `05` §3–§5) — плейсхолдер full-screen, **без** list-detail и двухпанельной раскладки.
- **`+`** — no-op со snackbar'ом через `AlertDialogHelper`; никакого create-flow.
- Нативный OS window chrome; **без** кастомного title bar. Кастомный унифицированный title bar, `window_manager`, начальный размер 1440×900 / min 640×600 — **FUTURE** (см. `09` §11a, `05` §1).
- Two-pane list-detail и диалоги-вместо-push приходят **с реальными фичами**, не в скелете.

## Чеклист

- [ ] `AppShell` — `LayoutBuilder`, порог `Constants.railBreakpoint = 840`, width-driven (не `Platform`).
- [ ] Mobile — кастомный `BottomAppBar` + `centerDocked` FAB; desktop — `NavigationRail(80, labelType.all, leading FAB)` + `VerticalDivider` + `Expanded(body)`.
- [ ] Две destination'ы (`Chats`=forum, `Settings`=settings); `+` = docked/leading FAB; `body` = `IndexedStack`; нет аккаунт-аватара.
- [ ] Single-window; нет `desktop_multi_window`/`window_manager`/`flutter_adaptive_scaffold`; нет list-detail.
- [ ] Скелет: обе вкладки → `Item`-плейсхолдер; `+` = no-op snackbar; нативный title bar.
