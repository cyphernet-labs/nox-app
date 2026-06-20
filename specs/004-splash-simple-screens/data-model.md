# Data Model — Этап M1

UI-only фаза: «модель» — это presentation-уровневые энумы, маленькие value-объекты параметров и наборы визуальных состояний по экранам. Нет персистентности и сетевых сущностей. Существующие энумы (`FileType`/`MessageStatus`/`AppTab`) не затрагиваются.

## Энумы и value-объекты (новые)

| Тип | Файл | Значения / поля | Назначение |
|---|---|---|---|
| `SplashOutcome` | `pages/splash_page/splash_page.dart` (private) | `hasId`, `noId`, `error` | Заглушечный исход резолвера авторизации; в превью выбирается dev-контролом. |
| `ErrorPageMode` | `pages/error_page/error_page_params.dart` | `blocking`, `embedded` | Режим экрана 3.1: без back (последний в стеке) / со стрелкой back. |
| `ErrorPageParams` | `pages/error_page/error_page_params.dart` | `icon: SvgGenImage` (NoxIcons), `title: String`, `message: String`, `mode: ErrorPageMode`, `onRetry: Future<void> Function()?` | Иммутабельные параметры экрана ошибки; задаются вызывающей стороной. Набор именованных пресетов (fatal / network) — статические конструкторы. |
| `AppLanguage` | `lib/general/app_language.dart` | `system`, `english`, `ukrainian` | Выбор языка UI (в пределах сессии; l10n-перерисовка вне scope). |
| `PermissionStatus` (mock) | `pages/notifications_page/notifications_page.dart` (private) | `granted`, `denied` | Заглушка состояния системного разрешения на push. |
| `AppVersionInfo` | (не нужен — берём `PackageInfo` напрямую) | `version: String`, `buildNumber: String` | Версия/билд из `package_info_plus`. |
| `TermsSection` | `pages/terms_page/terms_page.dart` (private) | `title: String`, `body: String` | Озаглавленная секция bundled-текста Terms. |

> Иконки `ErrorPageParams.icon` — тип генератора ассетов `SvgGenImage` (как у `NoxIcons.*`), не `IconData`.

## Состояния по экранам (визуальный вокабуляр)

Все состояния воспроизводимы на заглушках; где полезно — локальный debug-переключатель состояний.

### 1.1 Splash (`SplashPage`)
- `Routing` (по умолчанию): лого + wordmark, во время и после reveal-анимации.
- Координация: переход при `animationDone && outcomeResolved`.
- Исходы (dev-контрол): `hasId`→placeholder(shell) · `noId`→placeholder(login) · `error`→`AppErrorPage(blocking)`.

### 3.1 Error (`AppErrorPage`)
- `Embedded` (back-стрелка) / `Blocking` (без back).
- `Idle` (кнопка `Try again` активна) / `Retrying` (спиннер в кнопке).
- Десктоп: тот же контент в `AppWindowTitlebarWidget`, иконка 96.

### 7.3 Appearance (`AppearancePage`)
- `Loaded`: три карточки System/Light/Dark, отмечена текущая (из `AppRootBloc`).
- Тап → немедленная смена темы приложения (живо).

### 7.4 Language (`LanguagePage`)
- `Loaded`: три radio-строки System/English/Українська, по умолчанию System.
- Тап → отметка выбора (сессионно); опционально error-SnackBar (демо).

### 7.2 Notifications (`NotificationsPage`)
- `Loaded`: переключатель push on/off + supporting text.
- `Denied`: показан `AppInfoBannerWidget` с действием «open system settings».
- Демо-контрол переключает `granted/denied`.

### 7.6 Terms (`TermsPage`)
- `Loaded`: прокручиваемые озаглавленные секции (`TermsSection[]`) + version-footer.
- (краткий `Loading` при чтении версии — `FutureBuilder`.)

### 7.7 About (`AboutPage`)
- `Loaded`: одна строка `version (build N)` (из `package_info_plus`).
- (краткий `Loading` версии — `FutureBuilder`.)

## Связи и инварианты

- `ErrorPageParams.mode = blocking` ⇒ нет `AppBar`/back; системный back сворачивает приложение (`PopScope(canPop:false)` + no-op).
- `Appearance` не хранит собственного состояния темы — единственный источник истины `AppRootBloc.themeMode`.
- `Language`/`Notifications` держат локальное состояние только на время жизни страницы (нет персистентности).
- `SplashOutcome.error` ⇒ навигация на реально существующий `AppErrorPage(blocking)`; остальные исходы ⇒ `RoutePlaceholderPage(destinationLabel)`.
- Все экраны без выделенного desktop-корпуса используют `AppDetailScaffoldWidget` (десктоп = одна width-capped панель).
