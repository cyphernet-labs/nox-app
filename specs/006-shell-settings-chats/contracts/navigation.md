# Contract — Навигация, композиция и активация Галереи (M3)

Роутера нет: каждая страница экспортирует `route()` (+ `routeDemo()` где нужны debug-контролы) → `MaterialPageRoute` с уникальным `RouteSettings(name)`. Открытие — `Navigator.of(context).push(<Page>.route(...))`. Активация в Галерее — выставление `route:` тер-оффа в существующих строках `_sections` (`screens_gallery_page.dart`); id/title/section не меняются. **M3 — первый этап с реальной композицией** (не standalone-заглушками M1/M2).

## Route-фабрики экранов M3

| Экран | Класс | `route()` сигнатуры | `RouteSettings(name)` |
|---|---|---|---|
| 4.1 Tab-bar shell | `TabBarShell` | `static Route<void> route()` | `/shell` |
| 5.1 Chats list | `ChatsListPage` | `static Route<void> route()` + `static Route<void> routeDemo()` | `/chats` |
| 7.1 Settings root | `SettingsRootPage` | `static Route<void> route()` + `static Route<void> routeDemo()` | `/settings` |

> `routeDemo()` ставит `demo: true` (показывает debug-контролы за `kDebugMode && demo` — offline для 5.1; save/logout-исход для 7.1). `TabBarShell` — без demo (презентационный; debug-контролы живут в хостящихся 5.1/7.1). Конвенция страницы — как `CreateChatPage`: `const <Page>Page({super.key, this.demo = false}); static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const <Page>Page(), settings: const RouteSettings(name: '<path>')); static Route<void> routeDemo() => MaterialPageRoute<void>(builder: (_) => const <Page>Page(demo: true), settings: const RouteSettings(name: '<path>'));`. `_ScreenEntry.route` — zero-arg `Route<void> Function()?` (тер-офф `route`/`routeDemo` подходит).

## Активация строк Галереи

В `screens_gallery_page.dart`: добавить `import` каждой страницы и заменить `route: null` → тер-офф в существующих строках (4.1/5.1/7.1 сейчас `route: null`). Без новых строк, без смены id/title/section.

```
'4.1' (section 'Shell')    → route: TabBarShell.route       // открывает ЖИВОЙ композированный шелл (реальные 5.1+7.1 как табы)
'5.1' (section 'Chats')    → route: ChatsListPage.routeDemo  // standalone (тело таба без шелл-хрома) — изолированная проверка
'7.1' (section 'Settings') → route: SettingsRootPage.routeDemo
```

> 4.1 открывает **живой шелл** (реальная композиция). 5.1/7.1 дополнительно открываются standalone из Галереи (`routeDemo`) — тело таба для изолированной проверки в light/dark/обеих раскладках (паттерн root-экранов M2). Остальные строки (1.x/2.x/3.1/6.1 готовы; **5.2/5.3/5.4 — M4**) не трогаются.

## Реальная композиция (FR-008) — что вживляется

| Источник | Действие | Назначение (РЕАЛЬНОЕ, не заглушка) |
|---|---|---|
| `TabBarShell` таб Chats | — | реальный `ChatsListPage` (5.1) в `IndexedStack` |
| `TabBarShell` таб Settings | — | реальный `SettingsRootPage` (7.1) в `IndexedStack` |
| `TabBarShell` `+` (обе раскладки) | tap | `Navigator.push(CreateChatPage.route())` — page self-adapts (мобайл fullscreen / десктоп модальный `Dialog`); возврат на исходный таб |
| 7.1 строка `Notifications` | tap | мобайл `Navigator.push(NotificationsPage.route())` поверх шелла; десктоп — swap detail-pane (`NotificationsBody`) |
| 7.1 строка `Appearance` | tap | `AppearancePage.route()` / `AppearanceBody` |
| 7.1 строка `Language` | tap | `LanguagePage.route()` / `LanguageBody` |
| 7.1 строка `Terms` | tap | `TermsPage.route()` / `TermsBody` (public) |
| 7.1 строка `About` | tap | `AboutPage.route()` / `AboutBody` |
| 7.1 `Log out` (confirm) | confirm | (заглушенная очистка) → `Navigator.…(SplashPage.route())` — **реальный 1.1 Splash** |

## Заглушки-назначения (единственная — 5.2)

| Источник | Действие | Назначение в M3 |
|---|---|---|
| 5.1 тап по чату (мобайл) | tap | `RoutePlaceholderPage.route(destinationLabel: 'Chat thread (5.2)')` `// TODO(M4):` |
| 5.1 выбор строки (десктоп) | select | thread-pane = M4-плейсхолдер (highlight без push; лента 5.2 — M4) `// TODO(M4):` |
| 4.1 системный back на Chats | back | `SystemNavigator.pop` (в standalone-превью заглушено `// TODO(backend):`) |

> `RoutePlaceholderPage.route({required String destinationLabel})` — из M1, переиспользуется. Лента 5.2 — этап M4 (строка Галереи 5.2 остаётся `Coming soon`). Все прочие назначения M3 — **реальные** экраны.

## Pushed поверх шелла

Pushed-экраны (6.1; 7.2–7.7 мобайл; 5.2-плейсхолдер) открываются на весь экран поверх `TabBarShell` (root `Navigator.push`) — нижняя панель/rail-контекст скрыты (root push накрывает весь шелл). **Исключение**: 6.1 на десктопе — модальный `Dialog` со scrim (page self-adapts через внутренний `LayoutBuilder`; `// TODO(M3)` в `create_chat_page.dart` о реальном `showDialog` — **остаёмся на self-adapt pushed-route**, не переключаем сейчас). Десктоп 7.1 строки — **не** push, а swap detail-pane (list-detail).

## Mounting

`AppRoot.home` остаётся `HomePage` (лаунчер) — M3 **не** меняет точку входа. Шелл достигается из Галереи (pushed route `/shell`), консистентно со всеми экранами фазы 1. Продуктовый флоу (`1.1 → 2.1 → 2.3 → 4.1` как `home`) — backend-фаза.

## Тестовый контракт навигации

- Gallery-тест: тап по активированным строкам 4.1/5.1/7.1 пушит соответствующую страницу (`find.byType(TabBarShell/ChatsListPage/SettingsRootPage)` после `pumpAndSettle`); строки больше не `Coming soon`.
- Shell-тест: таб-свитч (Chats↔Settings) сохраняет состояние (`IndexedStack`); `+` пушит `CreateChatPage`; ширина <840 → `AppBottomBarWidget`, ≥840 → `AppNavigationRailWidget`.
- 7.1-тест: строка раздела пушит реальный подэкран (мобайл) / меняет detail-pane (десктоп); `Log out` confirm → пушит `SplashPage`.
- 5.1-тест: тап по чату → `RoutePlaceholderPage('Chat thread (5.2)')`; десктоп выбор → highlight без push (thread-pane = placeholder).
