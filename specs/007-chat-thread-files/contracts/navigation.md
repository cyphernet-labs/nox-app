# Contract — Навигация, снятие M3-плейсхолдеров и активация Галереи (M4)

Роутера нет: каждая страница экспортирует `route(...)` (+ `routeDemo()` где нужны debug-контролы) → `MaterialPageRoute` с уникальным `RouteSettings(name)`. Адаптивные оверлеи (5.3 lightbox, 5.4 side-sheet) на десктопе открываются через адаптивные хелперы (`showFileView`/`showChatCard`), которые сами выбирают форму по ширине. **M4 снимает последнюю заглушку M3** (плейсхолдер ленты) — стек чата становится полностью реальным.

## Route-фабрики / адаптивные входы M4

| Экран | Класс / хелпер | Сигнатуры | `RouteSettings(name)` |
|---|---|---|---|
| 5.2 Chat thread | `ChatThreadPage` | `static Route<void> route(ChatModel chat)` + `static Route<void> routeDemo()` | `/chat-thread` |
| 5.3 File view | `FileViewPage` + `Future<void> showFileView(BuildContext, MessageAttachment)` | `static Route<void> route(MessageAttachment file)` + `routeDemo()`; `showFileView` = мобайл push / десктоп `showDialog` lightbox | `/file` |
| 5.4 Chat card | `ChatCardPage` + `Future<void> showChatCard(BuildContext, ChatModel)` | `static Route<void> route(ChatModel chat)` + `routeDemo()`; `showChatCard` = мобайл push / десктоп `showGeneralDialog` right side-sheet | `/chat-card` |

> **Десктоп standalone 5.2 из Галереи:** `ChatThreadPage` при `wide` (≥840) рендерит `AppThreadViewWidget(showHeader: true)` внутри `Scaffold` (persistent ThreadHeader, без list-pane); при узком — `AppBar(back + name)`. Реальная десктоп-композиция ленты — в thread-pane 5.1.
>
> `routeDemo()` ставит `demo: true` (debug-контролы за `kDebugMode && demo` — `ChatThreadScenario` / `ChatCardScenario` / 5.3 download-исход) на **образцовых** данных (sample `ChatModel`/`MessageAttachment`). Конвенция страницы — как `ChatsListPage`/`CreateChatPage`: `late final _bloc` в `initState`, `close()` в `dispose`, `BlocProvider.value`. 5.3 — `StatefulWidget` без BLoC. `_ScreenEntry.route` — zero-arg `Route<void> Function()?` (тер-офф `routeDemo` подходит; `route(chat)` требует аргумент — Галерея использует `routeDemo`).

## Снятие M3-плейсхолдеров (FR-008) — правки `chats_list_page.dart`

| Точка | Было (M3) | Стало (M4) |
|---|---|---|
| `_onTapChat` (мобайл, `wide:false`) | `Navigator.push(RoutePlaceholderPage.route(destinationLabel: chatThreadPlaceholder))` | `Navigator.push(ChatThreadPage.route(chat))` — реальная лента поверх шелла |
| `_threadPane` (десктоп, выбран чат) | `AppDetailEmptyWidget(title: selected.name, message: comingSoon)` | `AppThreadViewWidget(chat: selected, …)` — реальная лента в thread-pane (своя `ChatThreadBloc` per выбранному chatId) |
| `_threadPane` (no-selection / отфильтрован) | `AppDetailEmptyWidget(Select a chat / …)` | **без изменений** (no-selection placeholder сохраняется) |

> Десктоп thread-pane создаёт/пересоздаёт `ChatThreadBloc` при смене `selectedChatId` (ключ по chatId). `RoutePlaceholderPage` остаётся в репозитории для прочих будущих заглушек.

## Активация строк Галереи

В `screens_gallery_page.dart`: добавить `import` каждой страницы и заменить `route: null` → тер-офф в существующих строках 5.2/5.3/5.4 (сейчас все `route: null`, `Coming soon`). Без новых строк, без смены id/title/section.

```
'5.2' (section 'Chats') → route: ChatThreadPage.routeDemo   // sample chat thread (мобайл push; десктоп — thread-pane превью)
'5.3' (section 'Chats') → route: FileViewPage.routeDemo     // sample file (мобайл push; десктоп lightbox через showFileView в demo)
'5.4' (section 'Chats') → route: ChatCardPage.routeDemo     // sample chat card (мобайл push; десктоп right side-sheet)
```

> После активации прогресс фазы 1 — **17/17** (все строки Галереи активны). Реальная композиция стека (5.1→5.2→5.3/5.4) проверяется из строки 5.1.

## Реальная композиция стека чата (FR-008)

| Источник | Действие | Назначение (РЕАЛЬНОЕ) |
|---|---|---|
| 5.1 тап по чату (мобайл) | tap | `ChatThreadPage.route(chat)` (5.2) поверх шелла |
| 5.1 выбор строки (десктоп) | select | реальная лента 5.2 в thread-pane (highlight без push) |
| 5.2 имя чата (мобайл AppBar) | tap | `showChatCard(context, chat)` → 5.4 (мобайл push) |
| 5.2 info-действие (десктоп ThreadHeader) | tap | `showChatCard(context, chat)` → 5.4 (десктоп right side-sheet 380) |
| 5.2 file-chip в сообщении | tap | `showFileView(context, attachment)` → 5.3 (мобайл push / десктоп lightbox) |
| 5.2 send (`error`) | tap | retry отправки (`SendRetried`) — не навигация |
| 5.2 attach | tap | no-op picker → draft `MessageAttachment` (не навигация) |
| 5.4 файл (List/Grid) | tap | `showFileView(context, attachment)` → 5.3 |
| 5.2 / 5.3 / 5.4 fatal | — | `ErrorPage` (3.1, embedded) |

## Pushed / overlay поверх шелла

- **Мобайл**: 5.2/5.3/5.4 — fullscreen push поверх `TabBarShell` (root `Navigator.push`) — нижняя панель скрыта.
- **Десктоп**: 5.2 — thread-pane (не push); 5.3 — `showDialog` lightbox (scrim); 5.4 — `showGeneralDialog` right side-sheet (scrim). Все — поверх list-detail 5.1.

## Тестовый контракт навигации

- Gallery-тест: строки 5.2/5.3/5.4 больше не `Coming soon`; тап пушит соответствующую страницу (`find.byType(ChatThreadPage/FileViewPage/ChatCardPage)` после `pumpAndSettle`).
- 5.1-тест (обновить M3-ожидания): мобайл тап → `ChatThreadPage` (не `RoutePlaceholderPage`); десктоп выбор → `AppThreadViewWidget` в thread-pane (не `comingSoon`).
- 5.2-тест: имя/info → `showChatCard` (5.4); file-chip → `showFileView` (5.3); адаптив мобайл push / десктоп overlay по ширине.
- 5.4-тест: файл → `showFileView` (5.3).
