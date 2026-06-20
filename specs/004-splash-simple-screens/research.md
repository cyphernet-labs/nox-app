# Research — Этап M1 (Splash + простые автономные экраны)

Phase 0 плана. Технический контекст известен (стек запинен блюпринтом), открытых вопросов спеки нет (разрешены в `## Clarifications`). Ниже — зафиксированные технические решения по реализации. Формат: **Решение / Обоснование / Альтернативы**.

## R1. Анимация Splash

- **Решение**: `AnimationController` (vsync, `NoxDuration.splashIn` = 400 мс) + `FadeTransition` (opacity 0→1) + `ScaleTransition` (0.85→1.0), кривая `NoxEasing.emphasizedDecelerate`, общий `Animation` на группу «логотип + wordmark» от геометрического центра. Один проход, затем статика.
- **Обоснование**: Точно по `splash.md` (Q3) и `design-system.md`; токены длительности/кривой уже есть в `nox_tokens.dart`. Контроллер запускается в `initState`, освобождается в `dispose`.
- **Альтернативы**: Lottie/Rive — отклонено (избыточно для двух одновременных эффектов; новая зависимость).

## R2. Splash: логотип, бренд-фон, edge-to-edge

- **Решение**: Лого — `Assets.png.logo` (`assets/png/logo.png`, подтверждённая цветная маска). Фон — `NoxBrand.canvasDark` (#0C2424), фиксированный (вне `ColorScheme`). Wordmark — `AppWordmarkWidget(color: NoxBrand.white)`. Edge-to-edge — `AnnotatedRegion<SystemUiOverlayStyle>` с прозрачными системными барами (документированное исключение из глобального overlay-стиля).
- **Обоснование**: Одно из двух санкционированных brand-fixed исключений темизации; raw-литералы остаются в `NoxBrand`/`lib/design/theme/`.
- **Альтернативы**: SVG-лого — отклонено (готового цветного SVG нет; PNG-маска присутствует и соответствует референсу).

## R3. Splash: маршрутизация в standalone-превью (Clarifications)

- **Решение**: Локальный `StatefulWidget` координирует «переход не раньше, чем `animationDone && outcomeResolved`». Исход выбирается dev-переключателем `SplashOutcome { hasId, noId, error }` (маленький overlay-контрол, виден только в превью). По завершении: `error` → `AppErrorPage` в режиме `blocking`; `hasId`/`noId` → `RoutePlaceholderPage` с подписью назначения (реальные 4.1/2.1 — позже).
- **Обоснование**: FR-013 + Clarifications. Реальный 3.1 строится в этом же M1 — демонстрирует ветку error по-настоящему. Заглушка резолвера — фейковый `Future` с настраиваемым исходом.
- **Альтернативы**: pop в Галерею / статичная подпись — отклонены как менее наглядные (логика ветвления не видна).

## R4. Универсальный экран ошибки (3.1)

- **Решение**: Новая страница `AppErrorPage` (params-driven), НЕ переиспользует `AppErrorWidget` напрямую (тот — body-only: `message` + `onTryAgain`, без title/режима/loading). Композиция: иконка `AppIconWidget(NoxIcons.*)` (мобайл 48 / десктоп 96) + заголовок (`titleLarge`) + сообщение (`bodyMedium onSurfaceVariant`) + `Try again` (FilledButton; при повторе — `AppSpinnerWidget(size:18,color:onPrimary)` внутри). Режим `ErrorPageMode { blocking, embedded }`: `embedded` → `AppBar` со стрелкой back; `blocking` → без `AppBar`, системный back сворачивает приложение (`PopScope`). Десктоп — обёртка `AppWindowTitlebarWidget` (faux TitleBar) над body.
- **Обоснование**: FR-020…025. `AppErrorWidget` остаётся для inline-состояний (`state.when(error:)`), `AppErrorPage` — для полноэкранного 3.1; дублирования нет (разные роли).
- **Альтернативы**: расширять `AppErrorWidget` режимами — отклонено (раздувает inline-виджет несвойственной ему ответственностью полноэкранной страницы).

## R5. Иконки экрана ошибки (Clarifications / FR-025)

- **Решение**: Только SVG `NoxIcons`. Базовый пресет — `NoxIcons.error` (есть в наборе). Если пресету нужен семантический глиф, отсутствующий в наборе (например `wifi_off`/`cloud_off`), он добавляется как **новый SVG** в `docs/design/system/nox-assets/icons/svg/` → `assets/svg/icons/` → регенерация `flutter_gen` + запись в `NoxIcons`. Material icon-шрифт не подключается.
- **Обоснование**: Icon-дисциплина kit (Принцип IV); спека пишет `Icons.error_outline` — это устаревшее указание, верить коду (SVG-only).
- **Альтернативы**: `material_symbols_icons` для экрана ошибки — отклонено (нарушает SVG-only и единообразие goldens).
- **Заметка для tasks**: M1-пресеты экрана ошибки выбрать так, чтобы укладываться в существующие глифы; добавление новых SVG — только если конкретный пресет действительно требует (минимизировать новые ассеты).

## R6. Десктоп-раскладка экранов без выделенного корпуса (Clarifications / FR-002)

- **Решение**: Новый виджет `AppDetailScaffoldWidget` — мобайл: обычный `Scaffold` + `AppBar`(title, back) на всю ширину; десктоп (≥840 по `LayoutBuilder`): тот же `AppBar` + body в `Center`→`ConstrainedBox(maxWidth ~640)` (одна полнооконная панель с ограниченной колонкой). Используют Appearance, Language, Notifications, Terms, About.
- **Обоснование**: Clarifications; честно для standalone-превью; реальный settings master-detail — этап M3 (7.1), не пред-строим.
- **Альтернативы**: имитация master-detail сейчас — отклонено (выбросной код, предвосхищает M3); full-bleed — отклонено (длинные строки на широком мониторе).

## R7. Десктоп-чром Splash / TitleBar

- **Решение**: Splash на десктопе — просто полнооконный контент (без TitleBar; у splash нет хрома). Для Error desktop — faux `AppWindowTitlebarWidget` (внутренняя текстовая полоса заголовка), НЕ нативное окно. Реальное скрытие нативного оконного чрома (`window_manager`/`chrome=false`) — вне scope (отложено в конституции, TODO(blueprint-desktop)).
- **Обоснование**: FR-014/FR-024; UI-only; нативные оконные плагины — backend/desktop-инфра фаза.
- **Альтернативы**: `window_manager` сейчас — отклонено (нативная инфраструктура вне UI-scope).

## R8. Внешний вид (тема) — реальное переключение

- **Решение**: `AppearancePage` — `StatelessWidget`, читает текущий `ThemeMode` из `AppRootBloc` (`context.watch`) и диспатчит `AppRootEvent.setTheme(...)` по тапу. Опции — карточки `AppThemeOptionWidget` (мини-превью + label + индикатор выбора), single-select.
- **Обоснование**: `AppRootBloc` уже владеет `ThemeMode` и проброшен в `MaterialApp.themeMode` — переключение работает по-настоящему (FR-031, единственная «живая» функция M1). Карточки — по мобайл-корпусу (Clarifications/FR-030).
- **Альтернативы**: новый BLoC темы — отклонено (дублирует `AppRootBloc`); `RadioListTile` — отклонено по Clarifications (корпус показывает карточки).

## R9. Язык — выбор без l10n

- **Решение**: `enum AppLanguage { system, english, ukrainian }` (`lib/general/app_language.dart`). `LanguagePage` — локальный `StatefulWidget`, держит выбор в пределах сессии; опции — стоковые `RadioListTile` (без флагов). Живая перерисовка интерфейса не делается (нет l10n-слоя).
- **Обоснование**: FR-040…042 + Clarifications; l10n — backend/инфра-фаза (нет `l10n.yaml`/`.arb`). Метка `// TODO(backend): wire LocaleController + l10n`.
- **Альтернативы**: подключать `flutter_localizations`+ARB сейчас — отклонено (отдельная крупная фича, вне M1).

## R10. Уведомления — переключатель + denied-баннер

- **Решение**: `NotificationsPage` — локальный `StatefulWidget` (`enabled` + mock `PermissionStatus { granted, denied }`). Новые виджеты: `AppSettingsSwitchRowWidget` (`SwitchListTile` + supporting text) и `AppInfoBannerWidget` (`MaterialBanner`-стиль: иконка + текст + одно действие). При `denied` — баннер с действием «open system settings» (no-op заглушка). Демо-переключение `granted/denied` — локальным контролом.
- **Обоснование**: FR-050…052; реальные разрешения/deeplink/persist — вне scope. Виджеты переиспользуются в 7.1 (M3).
- **Альтернативы**: `permission_handler`/`app_settings` сейчас — отклонено (плагины и реальные разрешения вне UI-scope).

## R11. Terms и About — версия приложения

- **Решение**: Версия/билд — `package_info_plus` (`PackageInfo.fromPlatform()`), уже в `pubspec.yaml`. `AboutPage` — одна строка `version (build N)`. `TermsPage` — `TermsBody` (озаглавленные секции из bundled placeholder-текста как `Text`/`RichText`) + version-footer; внешние ссылки — `url_launcher` (есть в pubspec) либо заглушка. Markdown-рендер не используется (`flutter_markdown` нет в pubspec).
- **Обоснование**: FR-060…062, FR-070…071; реальные данные локальные (в scope). Плоские секции избегают новой зависимости.
- **Альтернативы**: `flutter_markdown`/`webview_flutter` — отклонено (новые зависимости; для placeholder-текста избыточно).

## R12. Управление состоянием по экранам (заметка к Принципу III)

- **Решение**: M1-экраны без реального async → без Freezed-BLoC: `SplashPage`/`ErrorPage`/`LanguagePage`/`NotificationsPage` — локальный `StatefulWidget`; `AppearancePage` — `StatelessWidget` поверх существующего `AppRootBloc`; `AboutPage`/`TermsPage` — `StatelessWidget` (+`FutureBuilder` для версии).
- **Обоснование**: Фазовый carve-out 5.1, **кодифицирован в блюпринте `05` §5.1** (амендмент 2026-06-20) — чисто презентационные UI-first экраны без репозитория/async допускаются без BLoC (как shipped `HomePage`/`UiKitPage`); BLoC появляется с реальным репозиторием/async (backend-фаза). Без преждевременных пустых BLoC.
- **Альтернативы**: минимальный logic-less BLoC на каждый экран — отклонено для M1 (нет async; добавит пустой boilerplate без ценности).

## R13. Тестирование

- **Решение**: На каждый экран — `*_test.dart` (widget, через `pumpApp`, оборачивая в `BlocProvider<AppRootBloc>` где нужен theme-toggle/тема) + `*_golden_test.dart` (`@Tags(['golden'])`, light+dark, бейзлайны через `make golden-update`). На новые виджеты — widget+golden. Splash golden — `settle: false` (анимация). Активацию строк Галереи покрыть в gallery-тесте (строки стали enabled / навигация). Перед сдачей — `make gate`.
- **Обоснование**: Конвенции `test/` + DoD roadmap; goldens локальные (macOS), вне CI.
- **Альтернативы**: только widget-тесты — отклонено (DoD требует golden light/dark).
