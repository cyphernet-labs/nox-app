# Contract — Навигация и активация Галереи (M2)

Роутера нет: каждая страница экспортирует статический `route()` (+ `routeDemo()` для Галереи) → `MaterialPageRoute` с уникальным `RouteSettings(name)`. Открытие — `Navigator.of(context).push(<Page>.route(...))`. Активация в Галерее — выставление `route:` тер-оффа в существующей строке `_sections` (`screens_gallery_page.dart`); id/title/section не меняются.

## Route-фабрики экранов M2

| Экран | Класс | `route()` сигнатуры | `RouteSettings(name)` |
|---|---|---|---|
| 2.1 Login | `LoginPage` | `static Route<void> route()` + `static Route<void> routeDemo()` | `/onboarding/login` |
| 2.2 QR scan | `QrScanPage` | `static Route<void> route()` + `static Route<void> routeDemo()` | `/onboarding/qr-scan` |
| 2.3 Set username | `SetUsernamePage` | `static Route<void> route()` + `static Route<void> routeDemo()` | `/onboarding/set-username` |
| 6.1 Create chat | `CreateChatPage` | `static Route<void> route()` + `static Route<void> routeDemo()` | `/create/chat` |

> `routeDemo()` ставит `demo: true` (показывает debug-`SegmentedButton` исходов/состояний за `kDebugMode && demo`). Галерея активируется **через `routeDemo`** (чтобы контролы были доступны), как `AppErrorPage.routeDemo` в M1. Конвенция страницы: `const <Page>Page({super.key, this.demo = false}); static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const <Page>Page(), settings: const RouteSettings(name: '<path>')); static Route<void> routeDemo() => MaterialPageRoute<void>(builder: (_) => const <Page>Page(demo: true), settings: const RouteSettings(name: '<path>'));`

## Активация строк Галереи

В `screens_gallery_page.dart`: добавить `import` каждой страницы (верх файла) и заменить `route: null` → тер-офф в существующих строках. Без новых строк, без смены id/title/section.

```
'2.1' (section 'Onboarding') → route: LoginPage.routeDemo
'2.2' (section 'Onboarding') → route: QrScanPage.routeDemo
'2.3' (section 'Onboarding') → route: SetUsernamePage.routeDemo
'6.1' (section 'Create')     → route: CreateChatPage.routeDemo
```

Остальные строки (1.x реализованы M1; 4.1 / 5.x / 7.1 — позже) не трогаются. Раздел 6.1 — `Create` (не `Chats`).

## Заглушки переходов (standalone, FR-008)

Все переходы ведут на переиспользуемый M1 `RoutePlaceholderPage(destinationLabel: ...)` либо реальный `AppErrorPage`; меж-экранной навигации M2 не строится.

| Источник | Действие/исход | Назначение в превью |
|---|---|---|
| 2.1 `Sign in` | новый ID | `RoutePlaceholderPage('Set username (2.3)')` |
| 2.1 `Sign in` | зарегистрированный | `RoutePlaceholderPage('Chats shell (4.1)')` |
| 2.1 `Sign in` | format/network error | inline `errorText` (без перехода) |
| 2.1 `Sign in` | fatal | `AppErrorPage.route(ErrorPageParams.fatal(mode: blocking))` |
| 2.1 `Scan QR` | — | заглушка/no-op `// TODO(backend):` (связка с 2.2 не строится) |
| 2.2 успех скана | single-shot | `RoutePlaceholderPage('Login auto-submit (2.1)')` `// TODO(backend):` |
| 2.2 `Enter manually` / back | — | заглушка/возврат `// TODO(backend):` |
| 2.3 `Done` | success | `RoutePlaceholderPage('Chats shell (4.1)')` |
| 2.3 `Done` | race-taken / fatal | inline-error+фокус / `AppErrorPage(blocking)` |
| 2.3 `Skip` / back | — | `RoutePlaceholderPage('Chats shell (4.1)')` |
| 6.1 `Create` | success | `RoutePlaceholderPage('Chat thread (5.2)')` |
| 6.1 `Create` | network / fatal | inline-error (`Create` enabled) / `AppErrorPage` |
| 6.1 `Cancel`/back/scrim | — | возврат без подтверждения |

> `RoutePlaceholderPage.route({required String destinationLabel})` и `AppErrorPage.route({required ErrorPageParams params})` / `ErrorPageParams.fatal(...)` — из M1 (feature 004), переиспользуются без изменений.

## Десктоп-нюанс 6.1

`CreateChatPage` — width-adaptive внутри pushed-route: `<840` полноэкранный `Scaffold`; `≥840` scrim + центр. `Dialog(maxWidth≈460)` с `Cancel`/`Create`. Реальный вызов `showDialog` из окна чатов (шелл 4.1) — `// TODO(M3):` (шелла ещё нет).

## Тестовый контракт навигации

- Gallery-тест: тап по активированным строкам 2.1/2.2/2.3/6.1 пушит соответствующую страницу (`find.byType(<Page>)` после `pumpAndSettle`); строки больше не `Coming soon`.
- Per-screen widget-тест: исход debug-переключателя пушит ожидаемый `RoutePlaceholderPage`/`AppErrorPage` (проверка по `find.byType` / `RouteSettings.name`).
