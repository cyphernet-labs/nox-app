# Quickstart — проверка экранов M3 (шелл, настройки, список чатов)

Гайд по запуску и валидации фичи `006-shell-settings-chats`. Реализация — `tasks.md` (создаётся `/speckit-tasks`).

## Предпосылки

- FVM Flutter `3.44.1` (`fvm`), зависимости установлены: `make deps`.
- **Новые зависимости не требуются** (`qr_flutter` — Фаза 2; QR — fake-stub на brand-fixed светлой поверхности; относительное время — на уже доступном `intl`; debounce — `debounceRestartable()`/rxdart).
- Кодоген обязателен (новые `*.freezed.dart` для 2 BLoC + `ChatModel`/`GetChatsConfig`; возможен `*.g.dart` для `ChatModel` JSON; DI `*.config.dart` для `ChatRepository`): `make generate`.

## Запуск приложения

```bash
fvm flutter run --dart-define-from-file=config/stage.json            # мобайл (эмулятор/устройство)
fvm flutter run --dart-define-from-file=config/stage.json -d macos   # десктоп (или -d windows|linux)
```

Точка входа — `lib/main.dart` → `HomePage` (лаунчер). Шелл/экраны открываются из `Open Screens` → `ScreensGalleryPage` (M3 **не** меняет `home`).

## Ручная валидация (по user stories)

1. На `HomePage` → **Open Screens** → `ScreensGalleryPage`.
2. Строки **4.1 Tab bar shell** (раздел `Shell`), **5.1 Chats list** (раздел `Chats`), **7.1 Settings** (раздел `Settings`) активны (не `Coming soon`).
3. **4.1 открывает ЖИВОЙ шелл** (реальные 5.1+7.1 как табы). **5.1/7.1** дополнительно открываются standalone (тело таба) — изолированная проверка.
4. Проверить **обе темы** (тогл темы в AppBar) и **обе раскладки** (узкое/широкое окно — на десктопе менять ширину вокруг 840dp).
5. Состояния — через debug-контролы (видны только в `kDebugMode`, строки 5.1/7.1 открыты через `routeDemo`).

| Story | Экран | Что проверить |
|---|---|---|
| US1 | **Tab bar shell (4.1)** | Узкое окно — `BottomAppBar` с вырезом + center-docked `+` FAB, 2 таба (selected `primary`+filled); широкое (≥840) — `NavigationRail` + leading `+`. Переключение Chats↔Settings сохраняет состояние (скролл/ввод). `+` → реальный 6.1 (мобайл fullscreen / десктоп `Dialog`), возврат на исходный таб. Системный back: Settings→Chats; Chats→сворачивание (в превью заглушено). Re-tap Chats→scroll-to-top. |
| US2 | **Settings root (7.1)** | Identity `Card` (avatar + `Name` + `Your ID`). Name-edit: charset-ошибка / «занятое» имя (мок, после debounce) `This name is taken` / валидное → save. `Your ID`: мобайл маска `••••••••` + `Show/Hide` (raw monospace) + `Copy` (snackbar `Copied to clipboard`) + `Show QR` (bottom sheet, **светлая** QR-поверхность); **десктоп — без `Show/Hide`** (всегда маска) + inline-QR + `Show QR` (`Dialog`). Строки → реальные 7.2–7.7 (мобайл push / десктоп swap detail-pane). `Log out` → `AlertDialog` → loading → реальный **1.1 Splash**. Десктоп — list-detail (menu 340 + detail ≤680). |
| US3 | **Chats list (5.1)** | Мобайл — AppBar `NOX` + поле поиска + список (`AppChatItemWidget`: avatar + name + preview + **относительное время** + unread-бейдж `primary`, cap `99+`). Debug: Initial-loading / Empty (`No chats yet`) / Filled / Searching / Search-empty (`No chats found`) / Offline (`No connection` баннер) / Inline-error (`Could not load chats. Pull to refresh.`) / Fatal. Pull-to-refresh; re-tap Chats→scroll-top. Тап по чату → плейсхолдер `Chat thread (5.2)`. Десктоп — rail + list-pane 360 + thread-pane (выбор → highlight без push; no-selection `Select a chat`; thread = M4-плейсхолдер). |

Соответствие критериям — `spec.md` (Acceptance Scenarios, SC-001…008).

## Автоматическая проверка

```bash
# Гейт (codegen → format → analyze → widget+bloc-тесты, goldens исключены):
make gate

# Один экран / один BLoC:
make test FILE=test/presentation/pages/chats_list_page/chats_list_page_test.dart
make test FILE=test/presentation/pages/chats_list_page/bloc/chats_list_bloc_test.dart
make test FILE=test/presentation/pages/settings_root_page/bloc/settings_root_bloc_test.dart

# Golden-бейзлайны (локально, macOS/Apple Silicon):
make golden-update FILE=test/presentation/widgets/shell/tab_bar_shell_golden_test.dart
make golden-verify FILE=test/presentation/widgets/shell/tab_bar_shell_golden_test.dart
```

## Definition of Done (на каждый экран)

- [ ] Обе раскладки (мобайл <840 / десктоп ≥840) по спеке + десктоп-корпусу (`01-chats`/`02-settings`).
- [ ] Все состояния (data-model.md) демонстрируемы на заглушках (network-only мок-репозиторий + debug-контролы).
- [ ] Токены/`NoxIcons`/`TextConstants` (EN); нет сырых литералов (кроме brand-fixed светлой QR-поверхности §9.10).
- [ ] Реальная композиция: `+`→6.1, строки 7.1→7.2–7.7, Logout→1.1 — реальные; только 5.2 — плейсхолдер.
- [ ] Строка активирована в Галерее; light/dark; 4.1 — живой шелл, 5.1/7.1 — также standalone.
- [ ] BLoC: `ChatsListBloc` (sealed, `executeLogic(onError:)`, `sequential()`, `PagingState`); `SettingsRootBloc` (value-state, name-edit reuse 2.3); `TabBarShell` — без BLoC.
- [ ] Тесты: widget + golden (light/dark) на экран и новые виджеты; `bloc_test` на 2 BLoC; gallery-тест; relative-time unit-тест.
- [ ] `make gate` зелёный.

## Reconciliation-задачи M3 (Принцип II/III — тот же change-set)

- [ ] Блюпринт `docs/blueprints/mobile/05-presentation-layer.md` §6.5/§6 — обновить под реальный `TabBarShell` (kit `AppBottomBarWidget`, локальный `AppTab`-state) + **desktop list-detail** (сейчас доки говорят «desktop = rail + единый body»).
- [ ] Desktop-секции locked per-screen спек (`tab-bar-shell.md`/`chats-list.md`/`settings-root.md`) — дополнить десктоп-раскладкой из авторитетного корпуса (`01-chats`/`02-settings`): list-detail, no-reveal на десктопе, Logout→Splash (оба корпуса дрейфят на Login — пометить).

## После сдачи M3

- Отметить экраны в `docs/roadmap.md` (таблица M3 `[x]`, счётчик прогресса 11→14 / 17).
- Добавить новые блоки в реестр §6 (адаптивный шелл `TabBarShell`/list-detail; identity-card; relative-time форматтер; chats-вертикаль).
- Зачеркнуть закрытые открытые вопросы (Q4 Logout — решён → Splash).
