# Дорожная карта реализации NOX

> Живой документ для отслеживания прогресса реализации приложения. Обновляется по мере выполнения задач: статус-чекбоксы в таблицах этапов — основной трекер.
>
> **Фаза 1 — UI (текущая).** Реализуем экраны из спецификации `docs/design/spec/` по одному, мультиплатформенно (мобайл + десктоп), на заглушечных данных. **Интеграция с бэкендом — вне scope этой фазы.**
> **Фаза 2 — Backend.** Подключение реальных репозиториев, транспорта, плагинов (камера, файлы, QR), l10n, навигационного флоу. Зарезервирована в конце документа.
>
> Создан: 2026-06-20. Источники: `docs/design/spec/` (спека экранов, locked), `docs/design/system/nox-handoff-2/` (UI-kit), `docs/blueprints/mobile/` (архитектура), реальный код `lib/`.

---

## 1. Назначение и охват

Цель фазы 1 — **собрать весь визуальный слой** приложения: каждый из 17 экранов спецификации реализован как Flutter-страница, адаптивная под мобайл и десктоп, на дизайн-токенах, с полным набором визуальных состояний, демонстрируемых на мок-данных. Бизнес-логики, сети и навигационного флоу пока нет — экраны самодостаточны и открываются по одному.

**Что НЕ делаем в фазе 1:** реальная авторизация и хранение идентификатора, транспорт/сеть, серверные проверки уникальности, реальная камера/QR-декод, реальные загрузки файлов, l10n-перерисовка, персистентность настроек, связывание экранов в продуктовый флоу. Всё это — заглушки (фейковые `Future`, мок-репозитории, no-op), которые в фазе 2 заменяются точечно.

---

## 2. Текущее состояние

**Готово (можно опираться):**

- ✅ **Дизайн-система** — `lib/design/` (токены `AppSpacingTokens`/`AppTextStyleTokens`, `NoxRadius`/`NoxElevation`/`NoxDuration`/`NoxEasing`, `NoxBrand`, генерированные `ColorScheme` light/dark, `NoxIcons` SVG, тема M3 + темизация стоковых виджетов).
- ✅ **UI-kit** (Feature-003) — 15 переиспользуемых `App*Widget` в `lib/presentation/widgets/` (`chat/`, `primitives/`, `shell/`, `state/`) + энумы `FileType`/`MessageStatus`/`AppTab`.
- ✅ **Лаунчер** — `HomePage` → `UiKitPage` (галерея UI-kit). Навигация `Navigator.push(Page.route())`, роутера нет.
- ✅ **Каркас приложения** — `AppRoot` (`MaterialApp` + `ScreenUtilInit` + `AppRootBloc` для темы), DI (injectable+get_it), брейкпоинт `Constants.railBreakpoint = 840`.

**Не реализовано:** ни один продуктовый экран спецификации. Feature-001 `AppShell`/`ItemListPage` — верификационный скелет, **не смонтирован** и не считается реализацией экранов 4.1/5.1.

---

## 3. Принципы реализации UI-фазы (обязательны для каждого экрана)

Выжимка из `docs/design/spec/overview.md`, `design-system.md` и блюпринта. Это правила, не пожелания.

1. **Мультиплатформенность — width-driven, не Platform-driven.** Адаптив через `LayoutBuilder` по `constraints.maxWidth >= Constants.railBreakpoint` (840dp). Узкое окно десктопа = мобильный лейаут; широкое = десктопный. Мобайл: bottom bar + центральный docked `+` FAB. Десктоп: `NavigationRail`, диалоги вместо bottom sheet, master-detail (list-detail) вместо push. Один и тот же код корректен на всех пяти таргетах. `Platform`-проверки — только для настоящего поведения ОС (не для лейаута).
2. **Токен-дисциплина.** Никаких сырых `Color`/`EdgeInsets`/`TextStyle`/`SystemUiOverlayStyle` в коде экранов. Цвет — `Theme.of(context).colorScheme.<role>` и `context.appColors.<role>`; отступы — `AppSpacingTokens.sN`; фикс-размеры — `NoxSpacing`/`NoxRadius`/`NoxElevation`; типографика — `textTheme.<role>` / `AppTextStyleTokens.<role>(color:)`. Сырые литералы цвета — только внутри `lib/design/theme/`.
3. **Иконки — только SVG через `NoxIcons` + `AppIconWidget`.** Никаких `material_symbols_icons` / `Icons.*` (спека и handoff-доки про иконки **устарели** — верить коду).
4. **Микрокопирайт — английский, через `TextConstants`.** Никаких строковых литералов в виджетах. Языки приложения — EN + UK (UK — позже, через l10n); русского в UI нет никогда. Канон: `NOX`, `Your ID`, `Sign in` / `Log out`, термин «chat».
5. **Навигация.** Каждая страница — в своей папке `lib/presentation/pages/<page>_page/<page>_page.dart`, экспортирует `static Route<T> route(...)` → `MaterialPageRoute` с уникальным `RouteSettings(name: '/...')`. Открытие — `Navigator.of(context).push(Page.route())`. Роутер не добавляем.
6. **Состояние страницы.** Навигабельная страница с реальной асинхронной логикой — `StatefulWidget` + `State extends BaseStatePage<Page>` + минимальный Freezed-BLoC (`Initializing`/`Initialized`/`Error`); рендер через `state.when(...)`. **Важно:** `BaseBloc.executeLogic` глотает исключения без `onError` — всегда передавать `onError` и эмитить `Error`. Чисто статичный/локально-интерактивный экран — допустим `StatelessWidget`/локальный `StatefulWidget` без BLoC (как `HomePage`/`UiKitPage`). Переиспользуемые виджеты (`lib/presentation/widgets/`) BLoC **не** имеют.
7. **Вокабуляр состояний и обратной связи (4 уровня).** Ошибка поля → `TextField.errorText`; transient → `SnackBar` (снизу, над bottom bar/FAB, ~4с) через `showAppSnackBar`; persistent/офлайн → `MaterialBanner` «No connection» (сверху) через `showAppBanner`; fatal/5xx → универсальный экран ошибки 3.1. Состояния экрана из словаря: `Initial-loading`/`Loading`/`Empty`/`Loaded`/`<...>-error`/`Fatal` + screen-specific.
8. **Бренд-исключения из темизации (ровно два).** Фон splash всегда тёмный `NoxBrand.canvasDark` (#0C2424); поверхность QR всегда светлая `NoxBrand.qrSurface`/`qrInk`. Всё остальное (включая кастомные элементы) переключается light/dark.
9. **Продуктовая модель — следствия для UI.** Открытое общее пространство (все чаты видны всем, нет «join», чаты не удаляются). Статус сообщения локальный: `sent`/`pending`/`error` (нет delivered/read). Идентичность двухслойная: `Your ID` (маска `••••••••`, 8 точек) + label (≤32, charset `[A-Za-z0-9._-]`, уникален, case-sensitive). Имя чата ≤64, charset не ограничен, уникально. Профиля как экрана нет. Аватары чатов генерируются (инициалы + цвет по хэшу). Файлы — всегда chip (иконка типа + имя + размер), без превью содержимого.
10. **Тестирование и gate.** Тесты зеркалят `lib/` под `test/`. Виджет/юнит — `*_test.dart` (без тега); golden — `*_golden_test.dart` с `@Tags(['golden'])`. Харнес `pumpApp` (test/utils) обязателен. Мокаем только `mockito`. Перед сдачей экрана — `make gate` зелёный; формат `fvm dart format -l 140 <paths>`.

---

## 4. Механизм разработки: «Галерея экранов» (Screens gallery)

Аналогично галерее UI-kit, но для экранов. На `HomePage` — вторая кнопка (под «Open UI Kit»), открывающая **`ScreensGalleryPage`** (`/screens`): список всех экранов, сгруппированный по разделам карты (`Запуск` / `Онбординг` / `Ошибка` / `Шелл` / `Чаты` / `Настройки`). Каждая строка пушит соответствующий standalone-экран. Нереализованные строки показаны как `coming soon` (disabled) и «включаются» по мере реализации — то есть сама галерея служит наглядным индикатором прогресса.

Каждый экран открывается **изолированно** (с back-стрелкой), адаптивно (мобайл/десктоп — определяется шириной окна), и проверяется в обеих темах через существующий `AppThemeToggle` в `AppBar.actions`. Связывание экранов в реальный флоу — задача фазы 2.

---

## 5. Definition of Done экрана

Экран считается готовым, когда:

- [ ] Реализованы **оба** лейаута: мобайл (<840) и десктоп (≥840) по спеке + корпусу (`nox-mobile-screens` / `nox-desktop-screens`).
- [ ] Все визуальные **состояния** из спеки демонстрируемы на мок-данных (где полезно — локальный debug-переключатель состояний).
- [ ] Полная токен-дисциплина, иконки `NoxIcons`, копирайт в `TextConstants` (EN).
- [ ] Экран доступен и просматриваем из **Галереи экранов** в light/dark.
- [ ] Бэкенд-зависимости честно заглушены (фейк-`Future`/мок/no-op), точки замены отмечены `// TODO(backend):`.
- [ ] Тесты: **golden** (light+dark) + **widget**-тест, по правилам именования/тегов, через `pumpApp`.
- [ ] `make gate` зелёный.

---

## 6. Общие строительные блоки (shared building blocks)

Часть экранов опирается на ещё не существующие переиспользуемые элементы. Вводим их **по месту первой потребности** и затем переиспользуем (чтобы избежать дивергенции — research отметил риск для онбординг-хрома и settings-строк). Реестр:

| Блок | Что это | Вводится в | Переиспользуют |
|---|---|---|---|
| Feedback helpers | `showAppSnackBar` / `showAppBanner` (уже есть в `app_feedback_helper.dart`); добавить `MaterialBanner` офлайн-баннер | M1 (3.1) | 5.1, 5.2, 5.3, 5.4, 7.x |
| Адаптивная обёртка страницы | хелпер/паттерн «mobile-scaffold ↔ desktop-pane/dialog» по 840dp | M1 (3.1) | все экраны |
| Онбординг-хром | `OnboardCard` (центр. карточка 440) + десктоп-окно/`TitleBar` | M2 (2.1) | 2.3, частично 1.1/3.1 |
| Поле-ввода семейство | моно ID-поле; labeled `TextField` + счётчик + suffix-спиннер + errorText | M2 (2.1) | 2.3, 6.1, 7.1 |
| QR-сюрфейс / ретикл | бренд-белая QR-поверхность; рамка-ретикл сканера + маска | M2 (2.2) | 7.1 |
| Settings-строки | `AppSettingsNavRowWidget`, `AppSettingsSwitchRowWidget`, `AppInfoBannerWidget`, `AppSettingsGroupWidget` | M1 (7.2) | 7.1, 7.3, 7.4, 7.6, 7.7 |
| Identity card | `AppIdentityCardWidget` (маска/reveal/copy/QR) + `AppLogoutDialogWidget` | M3 (7.1) | — |
| Адаптивный шелл | `TabBarShell` (bottom bar ↔ `NavigationRail`), list-detail | M3 (4.1) | 5.1, 5.2, 7.1 |
| Лента-элементы | редактируемый composer (апгрейд `AppComposerWidget`), `AppDateSeparatorWidget`, `AppAuthorHeaderWidget`, `AppSystemLineWidget` | M4 (5.2) | — |
| Форматтеры | относительное время (список чатов), размер файла | M1/M3 | 5.1, 5.3, 5.4 |

---

## 7. Дорожная карта по этапам

Последовательность подобрана так, чтобы: (а) начать с простого и мотивирующего (splash), (б) общие блоки вводились раньше зависящих от них экранов, (в) самые сложные экраны (лента, список чатов) шли последними. Сложность: **S** — статичный/тривиальный, **M** — умеренный, **L** — сложный/много состояний.

Статус: `[ ]` не начат · `[~]` в работе · `[x]` готов (DoD выполнен).

### Этап M0 — Каркас галереи экранов  ✅ _готов_

- [x] **M0.1** Вторая кнопка на `HomePage` («Open Screens») + строки `TextConstants` (`screensGalleryTitle`, `actionOpenScreens`).
- [x] **M0.2** `ScreensGalleryPage` (`/screens`): список экранов по разделам; строка активируется выставлением `route:` (tear-off `Page.route`), пока все — `Coming soon` (disabled). Контент ограничен по ширине (640) для десктопа. Тесты: widget + golden (light/dark).
- [x] **M0.3** Паттерн standalone-экрана зафиксирован (AppBar + `AppSplashHairlineWidget` + `AppThemeToggle`; реализованные экраны открываются из галереи).

### Этап M1 — Splash + простые автономные экраны  ⟶ _без плагинов, низкий риск_

| # | ID | Экран | Сложн. | Вводит / переиспользует | Мультиплатформа (ключевое отличие) | Зависит |
|---|---|---|---|---|---|---|
| [x] | **1.1** | **Splash** | M | ✅ лого-композиция (`Assets.png.logo`) + Fade+Scale-обёртка; reuse `AppWordmarkWidget`; debug-исход → placeholder/Error | единая центр. композиция на обоих; десктоп — без OS-чрома, крупнее лого | (error-ветка → placeholder до US2/3.1) |
| [x] | 3.1 | Error (universal) | M | ✅ `AppErrorPage` + `ErrorPageMode{blocking,embedded}` + пресеты; `AppWindowTitlebarWidget`; loading-retry | мобайл AppBar(back)/blocking → десктоп `TitleBar`, иконка 96dp | — |
| [ ] | 7.7 | About | S | — (только `package_info_plus` для версии) | мобайл push → десктоп detail-pane | 7.1 |
| [ ] | 7.6 | Terms | S | `TermsBody` (shared) + version footer | мобайл push → десктоп detail-pane | 7.1 |
| [x] | 7.3 | Appearance | S | ✅ `AppThemeOptionWidget` + `AppDetailScaffoldWidget`; **reuse `AppRootBloc`** (живой свитч темы работает) | мобайл push → десктоп width-cap панель | 7.1 |
| [x] | 7.4 | Language | S | ✅ `AppLanguage` + `RadioGroup`/`RadioListTile`; сессионный выбор (l10n live re-render — заглушка) | мобайл push → десктоп width-cap панель | 7.1 |
| [x] | 7.2 | Notifications | M | ✅ `AppSettingsSwitchRowWidget` + `AppInfoBannerWidget`; mock-permission + denied-баннер | мобайл push → десктоп width-cap панель | 7.1 |

### Этап M2 — Онбординг-формы  ⟶ _вводит онбординг-хром и поля-ввода_

| # | ID | Экран | Сложн. | Вводит / переиспользует | Мультиплатформа (ключевое отличие) | Зависит |
|---|---|---|---|---|---|---|
| [ ] | 2.1 | Login (ID entry) | M | `OnboardCard` + моно ID-поле; минимальный `LoginBloc` | мобайл fullscreen + AppBar → десктоп центр. карточка 440 + `TitleBar` | 2.2, 2.3 |
| [ ] | 2.3 | Set username | M | валидируемое поле (счётчик 32 + спиннер доступности); `SetUsernameBloc` | reuse онбординг-хрома | 2.1 |
| [ ] | 6.1 | Create chat | L | labeled-поле + счётчик 64 + спиннер; `CreateChatBloc` | мобайл fullscreen push → десктоп модальный `Dialog` ~460 | 5.2 |
| [ ] | 2.2 | QR scan | L | ретикл + маска + permission-denied панель; **камера — заглушка** | мобайл full-bleed + торч/смена камеры → десктоп ~300dp вьюфайндер | 2.1 |

### Этап M3 — Шелл, корень настроек, список чатов  ⟶ _скелет приложения, адаптивный шелл + list-detail_

| # | ID | Экран | Сложн. | Вводит / переиспользует | Мультиплатформа (ключевое отличие) | Зависит |
|---|---|---|---|---|---|---|
| [ ] | 4.1 | Tab-bar shell | M | `TabBarShell` (reuse `AppBottomBarWidget`/`AppCreateFabWidget`; сверить с Feature-001 `AppShell`) | bottom bar+notch+FAB → `NavigationRail` + leading FAB (840dp) | 5.1, 7.1, 6.1 |
| [ ] | 7.1 | Settings root | L | `AppIdentityCardWidget` (маска/copy/QR), settings-nav-строки, logout-диалог; `SettingsRootBloc`; QR — `qr_flutter`/заглушка | мобайл fullscreen + QR-sheet → десктоп rail+menu+detail, QR/Logout = `Dialog` | 7.2–7.7, 2.3 |
| [ ] | 5.1 | Chats list | L | `ChatsListPage` + search-view + офлайн-`MaterialBanner`; форматтер времени; `ChatsListBloc` (in-memory mock-repo) | мобайл bottom bar + push → десктоп rail + 360 list-pane + thread-pane (master-detail, highlight без push) | 4.1, 5.2, 6.1 |

### Этап M4 — Лента чата и файлы  ⟶ _самые сложные, чат-детали_

| # | ID | Экран | Сложн. | Вводит / переиспользует | Мультиплатформа (ключевое отличие) | Зависит |
|---|---|---|---|---|---|---|
| [ ] | 5.2 | Chat thread | L | редактируемый composer, date-separator, author-header, system-line; `ChatThreadBloc` (PagingState-в-bloc, optimistic send) | мобайл fullscreen push → десктоп правый detail-pane + ThreadHeader, колонка ≤980px | 5.1, 5.3, 5.4 |
| [ ] | 5.3 | File view | M | `FileViewBody` (glyph+name+size); форматтер размера; фейк-прогресс загрузки | мобайл fullscreen push (Save) → десктоп lightbox-`Dialog` 520 (Download) | 5.2 |
| [ ] | 5.4 | Chat card | M | `ChatCardPage` + list/grid-плитки файлов (reuse `AppSegmentedWidget`) | мобайл fullscreen push → десктоп side-sheet/detail-pane (инференс) | 5.2, 5.3 |

**Прогресс фазы 1:** 5 / 17 экранов готовы (✅ 1.1 Splash, 3.1 Error, 7.3 Appearance, 7.4 Language, 7.2 Notifications) · M0 готов; M1 в работе (5 / 7).

---

## 8. Открытые вопросы / решения к принятию

Не блокируют старт (splash готов к реализации), но требуют решения по ходу:

| # | Вопрос | Где всплывает | Заметка |
|---|---|---|---|
| Q1 | ~~Цветной логотип splash существует?~~ | 1.1 | **Решено:** `assets/png/logo.png` — нужная цветная маска. |
| Q2 | Клиентская валидация формата ID: спека говорит «только сервер», корпус упоминает клиентскую проверку | 2.1 | принять до реализации 2.1 |
| Q3 | Источник иконок экрана ошибки: спека просит `Icons.error_outline`/wifi/cloud, но kit — только SVG `NoxIcons` (нет wifi/cloud/camera) | 3.1 | маппить на имеющиеся `NoxIcons` или добавить SVG |
| Q4 | Назначение Logout: Splash (1.1) vs Login (2.1) — доки расходятся | 7.1 | принять каноничный таргет |
| Q5 | Appearance: плоские `RadioListTile` (спека) vs карточки с превью-тамбнейлом (корпус) | 7.3 | вероятно карточки |
| Q6 | Десктоп-корпус отсутствует у 5.4, 7.2–7.7 — десктоп-трактовка выведена по аналогии | мн. | сверить с владельцем при реализации |

---

## 9. Фаза 2 — Backend (зарезервировано)

Подключается после готовности UI. Здесь будет свой блок задач; ключевые направления (из анализа заглушек фазы 1):

- **Транспорт/протокол и сервер** — пока не выбраны (блюпринты `04`/`14`/`15`/`16` — TBD-плейсхолдеры).
- **Auth / local-state** — чтение/хранение идентификатора, session, ветвление splash (1.1).
- **Репозитории** — cache-first Sembast + network-only carve-out (список чатов, лента, POST создания/отправки); `infinite_scroll_pagination` v5.
- **Плагины** (добавить в фазе 2): камера/QR-декод (`mobile_scanner` + `permission_handler` + `app_settings`), отрисовка QR (`qr_flutter`), выбор файла (`file_picker`), сохранение в Downloads (`path_provider`/`file_saver`), десктоп-чром окна (`window_manager`).
- **l10n** — `l10n.yaml` + `.arb` (EN+UK), миграция `TextConstants`; живая перерисовка языка (7.4).
- **Персистентность настроек** — тема/язык/уведомления (prefs vs Sembast).
- **Продуктовый флоу** — замена Галереи экранов реальной навигацией (`1.1 → 2.1↔2.2 → 2.3 → 4.1`, и т.д.).

---

## 10. Как обновлять этот документ

- Меняем статус-чекбокс экрана на `[~]`/`[x]` в таблице этапа по факту работы.
- Обновляем строку «Прогресс фазы 1» (счётчики).
- Закрытые открытые вопросы — зачёркиваем и помечаем «Решено».
- Новые переиспользуемые блоки — добавляем в реестр §6.
