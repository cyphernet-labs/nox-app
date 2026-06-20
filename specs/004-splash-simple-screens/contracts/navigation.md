# Contract — Навигация и активация Галереи

Роутера нет: каждая страница экспортирует статический `route()` → `MaterialPageRoute` с уникальным `RouteSettings(name)`. Открытие — `Navigator.of(context).push(<Page>.route(...))`. Активация в Галерее — выставление `route:` тер-оффа в `_sections` (`screens_gallery_page.dart`).

## Route-фабрики экранов M1

| Экран | Класс | `route()` сигнатура | `RouteSettings(name)` |
|---|---|---|---|
| 1.1 Splash | `SplashPage` | `static Route<void> route()` | `/splash` |
| 3.1 Error | `AppErrorPage` | `static Route<void> route({required ErrorPageParams params})` + `static Route<void> routeDemo()` (пресет для Галереи) | `/error` |
| 7.3 Appearance | `AppearancePage` | `static Route<void> route()` | `/settings/appearance` |
| 7.4 Language | `LanguagePage` | `static Route<void> route()` | `/settings/language` |
| 7.2 Notifications | `NotificationsPage` | `static Route<void> route()` | `/settings/notifications` |
| 7.6 Terms | `TermsPage` | `static Route<void> route()` | `/settings/terms` |
| 7.7 About | `AboutPage` | `static Route<void> route()` | `/settings/about` |
| — Placeholder | `RoutePlaceholderPage` | `static Route<void> route({required String destinationLabel})` | `/placeholder` |

> `AppErrorPage` требует `ErrorPageParams`, поэтому для строки Галереи нужен бес-параметровый вход — `routeDemo()` (демо-пресет, переключатель blocking/embedded внутри страницы). Тер-офф в Галерее = `AppErrorPage.routeDemo`.

## Активация строк Галереи

В `screens_gallery_page.dart` для каждой реализованной строки выставить `route:` (см. M0-контракт `_ScreenEntry`):

```
'1.1' → route: SplashPage.route
'3.1' → route: AppErrorPage.routeDemo
'7.3' → route: AppearancePage.route
'7.4' → route: LanguagePage.route
'7.2' → route: NotificationsPage.route
'7.6' → route: TermsPage.route
'7.7' → route: AboutPage.route
```

Строки 2.x / 4.1 / 5.x / 6.1 остаются `route: null` (`Coming soon`) до своих этапов.

## Поведение Splash-навигации (превью)

- `SplashOutcome.error` → `Navigator.push(AppErrorPage.route(params: ErrorPageParams.fatal(mode: blocking)))`.
- `SplashOutcome.hasId` → `Navigator.push(RoutePlaceholderPage.route(destinationLabel: 'Chats shell (4.1)'))`.
- `SplashOutcome.noId` → `Navigator.push(RoutePlaceholderPage.route(destinationLabel: 'Login (2.1)'))`.
- Переход — `pushReplacement` (со splash не возвращаются) — но в превью из Галереи допустим обычный `push` (чтобы вернуться к списку back-ом). **Решение для tasks**: в превью использовать `push` (возврат в Галерею), пометив `// TODO(backend): pushReplacement in real cold-start flow`.

## Тестовый контракт навигации

- `HomePage`/`ScreensGalleryPage`-тесты: тап по активированной строке пушит соответствующую страницу (`find.byType(<Page>)` после `pumpAndSettle`).
- Splash-тест: по завершении анимации (`tester.pump(NoxDuration.splashIn)`) при заданном `SplashOutcome` пушится ожидаемая цель.
