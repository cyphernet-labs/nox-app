# Feature Specification: Инициализация Flutter-проекта NOX (multi-platform skeleton)

**Feature Branch**: `001-flutter-project-init`

**Created**: 2026-06-08

**Status**: Draft

**Input**: User description: "Инициализировать Flutter-проект NOX, поддерживающий все платформы, кроме web (две мобильные — Android, iOS; три десктопные — Windows, Linux, macOS). Проект должен соответствовать спецификации разработки в `docs/patterns/mobile`. Объём — только каркас (skeleton), без реальных фич."

## Обзор

Цель фичи — поднять с нуля пустой репозиторий до запускаемого, соответствующего блюпринту каркаса приложения NOX, на котором дальше будет вестись разработка фич. Сейчас в репозитории нет `lib/`, нет `pubspec.yaml`, Flutter/Dart не установлены — есть только документация. Эта фича закрывает разрыв между фазой дизайна и фазой имплементации: после неё любой разработчик может склонировать репозиторий, поднять окружение по документированным шагам, собрать приложение под все пять целевых платформ и запустить его там, где есть ОС (macOS, iOS, Android на этой итерации; Windows/Linux — сборка, запуск позже на CI).

Каркас — это структура, тулинг и инфраструктура: один Dart-пакет `nox_app`, Clean Architecture слоями-папками, единый DI, тема из дизайн-токенов, app shell (навигационный каркас) и зелёный code-gate. **Реальных фич нет** — содержимое вкладок плейсхолдерное, бэкенд-интеграции нет.

**Авторитет по «как»:** `docs/patterns/mobile/` (блюпринт, особенно `11-scaffolding-plan.md`). Эта спека фиксирует **что** и **границы объёма**; конкретные шаги сборки выводятся из блюпринта на этапах plan/tasks.

## Clarifications

### Session 2026-06-09

- Q: App shell на десктопе — мобильный bottom-bar (FR-004) или desktop-shell по `nox-desktop-screens`? → A: **Adaptive nav без list-detail** — bottom-bar на iOS/Android, `NavigationRail` на Windows/Linux/macOS с тем же набором назначений (`Chats` / `+` / `Settings`); контент вкладок — плейсхолдер full-screen; two-pane list-detail и диалоги-вместо-push откладываются до реальных фич. Блюпринт `05`/`11` расширяется вторым (adaptive) shell-паттерном.
- Q: Что значит «build + launch на всех 5 платформах» (SC-001) для приёмки сейчас? → A: **Launch-verify macOS + iOS + Android** сейчас; Windows/Linux — только **compile/build-verify** на этой итерации; полный launch-verify Windows/Linux — tracked follow-up (CI-раннеры).
- Q: Локализация в каркасе сейчас или отложить? → A: **Отложить full i18n** (дефолт блюпринта) — English-only через `TextConstants` с ARB-portable ключами; без `flutter_localizations`/`gen-l10n` и без украинской локали на этой итерации (en+uk — отдельная i18n-фича).
- Q: SC-004 «neutral-шаблон» vs блюпринт-DoD (сквозной `Item`-слайс) при FR-013 «нет фич»? → A: **Коммитить `Item`-слайс блюпринта как verification harness**, явно помеченный как scaffold-demo (mock-данные, не продуктовая фича/бэкенд); он несёт baseline-тесты (bloc smoke + mapper round-trip). FR-013 запрещает реальные продуктовые фичи, но не verification-harness.
- **Desktop/blueprint deep-dive — 18 решений, все recommended** (ранее deferred (a) desktop flavors и (b) fallback-granularity — теперь решены). Внесены в блюпринт (`00`/`01`/`05`/`06`/`09`/`11`/`13`/`14`/`15` + `README`) в этом же change-set:
  - **Shell:** адаптивная оболочка кастомным breakpoint (`LayoutBuilder`, **без** `flutter_adaptive_scaffold`); switch width-driven на `Constants.railBreakpoint` = **840dp** (M3 medium↔expanded), не `Platform`-driven; desktop — `NavigationRail` width 80, `labelType.all`, 2 destination (`Chats`=forum, `Settings`=settings), `+` = leading FAB, без аккаунт-аватара (нет profile), тело = `IndexedStack`; mobile — `NavigationBar` (3 слота). Без list-detail. Окно — дефолтное окно runner'а (**без** `window_manager`), нативный OS-title-bar; 1440×900 / min 640×600 / кастомный title bar = FUTURE. Single-window подтверждён (без `desktop_multi_window`).
  - **Build:** desktop-флейворы через `--dart-define-from-file=config/<flavor>.json` (только `app.flavor`, закоммичен, без секретов); desktop-идентичность **prod-only** native (`com.cyphernetlabs.noxapp` / `NOX`), stage — только в Dart; secrets-decrypt на desktop **пропускается** (без age-ключа); packaging/signing (MSIX / DMG+notarization / AppImage·.deb) = FUTURE (`TODO(blueprint-desktop-packaging)`).
  - **Fallbacks:** гранулярность = проза + DI no-op stub **только где скелет резолвит** (сейчас проза-only; «no-op с первым desktop-потребителем»); push = disabled/no-op (`firebase_*` mobile-only feature-gated); deep-links = no-op (native `nox://` = FUTURE; single-window warm-link будит то же окно); secure storage = задокументированы бэкенды (Keychain/DPAPI/libsecret), wiring с auth.
  - **Matrix/CI:** `flutter create --platforms=android,ios,macos,windows,linux` (без web); min-OS = дефолты Flutter 3.44.1 (Win10/macOS10.15/GTK3), пин = FUTURE; CI — **3 compile-only джоба** (macos/windows/linux, debug) — закрывает `TODO(blueprint-desktop-build)`; без `yaru`, единая Material 3; excluded-deps подтверждены (нет `flutter_adaptive_scaffold`/`custom_adaptive_scaffold`/`desktop_multi_window`/`window_manager`/`bitsdojo_window`/`yaru`).

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Сборка под все пять платформ и запуск каркаса (Priority: P1)

Разработчик собирает приложение под все пять целевых платформ и запускает работающий app shell там, где у него есть ОС: macOS, iOS, Android (launch-verify); Windows и Linux на этой итерации — только сборка (compile/build-verify), их запуск проверяется позже на CI-раннерах. На мобильных таргетах shell — нижняя панель, на десктопе — `NavigationRail` (адаптивный shell, см. FR-004). Мульти-платформенная основа доказана с самого начала, до того как поверх неё ляжет хоть одна фича.

**Why this priority**: Это заголовочный результат фичи и одновременно главный риск — десктоп выходил за рамки исходного мобильного блюпринта (build/secrets, push, deep-links, native-слои были iOS/Android-специфичны); блюпринт уже расширен на desktop в этом change-set (см. Dependencies). Если каркас не собирается под все пять таргетов и не запускается там, где есть ОС, дальнейшая работа бессмысленна.

**Independent Test**: На чистом клоне по документированным шагам собрать приложение под все пять таргетов; запустить app shell на macOS, iOS, Android (появляется адаптивный shell — bottom-bar на мобиле, `NavigationRail` на macOS); для Windows/Linux подтвердить успешную сборку. Web-таргет отсутствует.

**Acceptance Scenarios**:

1. **Given** чистый клон и поднятое по документации окружение, **When** разработчик собирает и запускает приложение на Android и iOS, **Then** запускается app shell с нижней панелью (`Chats`, центральный `+`, `Settings`) без падений.
2. **Given** то же окружение на macOS, **When** разработчик собирает и запускает приложение на macOS, **Then** запускается тот же app shell, но с `NavigationRail` (адаптив по форм-фактору), без падений.
3. **Given** то же окружение, **When** разработчик собирает приложение под Windows и Linux, **Then** сборка проходит успешно (compile/build-verify); их запуск проверяется позже на CI-раннерах (tracked follow-up).
4. **Given** конфигурацию проекта, **When** перечисляются доступные платформенные таргеты, **Then** их ровно пять (Android, iOS, Windows, Linux, macOS) и web среди них нет.

---

### User Story 2 — Структура, готовая к разработке фич (Priority: P1)

Разработчик начинает новую фичу и обнаруживает, что все архитектурные слои, DI, контракт `RepositoryResult`, дизайн-токены и кодоген уже на месте — реструктуризация каркаса не требуется, можно сразу писать фичу по шаблонам блюпринта.

**Why this priority**: Смысл каркаса — быть готовым основанием. Если старт фичи требует доделок структуры, инициализация не выполнила свою задачу.

**Independent Test**: Сверить дерево проекта с блюпринтом (`00-architecture-overview.md`, `11-scaffolding-plan.md`): присутствуют слои-папки `lib/data`, `lib/domain`, `lib/presentation`, `lib/di`, `lib/general`, `lib/design`, `lib/resource`; один `pubspec.yaml`; единый DI-init; сквозной `Item`-verification-слайс блюпринта собран по шаблону и не потребовал реструктуризации каркаса.

**Acceptance Scenarios**:

1. **Given** инициализированный проект, **When** разработчик открывает дерево `lib/`, **Then** присутствуют все слои-папки блюпринта в составе одного пакета `nox_app` с однонаправленными зависимостями (`presentation → domain ← data`).
2. **Given** инициализированный проект, **When** разработчик добавляет фичу по copy-paste-шаблону из блюпринта, **Then** ему не нужно менять структуру каркаса, поднимать DI заново или вводить новые инфраструктурные примитивы.

---

### User Story 3 — Зелёный code-gate и воспроизводимая среда (Priority: P2)

Разработчик прогоняет полный code-gate — кодоген (один прогон) → форматирование → анализ → тесты — и всё зелёное; окружение воспроизводимо у любого члена команды благодаря запиненной через FVM версии Flutter.

**Why this priority**: Зелёный gate с первого дня задаёт планку качества и не даёт каркасу деградировать; воспроизводимость убирает «у меня работает».

**Independent Test**: На чистом клоне выполнить документированные команды gate; кодоген проходит за один прогон, `flutter analyze` даёт ноль ошибок, baseline-тесты проходят, форматирование стабильно при line length 140.

**Acceptance Scenarios**:

1. **Given** инициализированный проект, **When** разработчик прогоняет кодоген одним прогоном `build_runner`, **Then** он завершается без ошибок и без конфликтов.
2. **Given** инициализированный проект, **When** разработчик запускает анализ, **Then** ошибок ноль (сгенерированные файлы исключены из анализа).
3. **Given** инициализированный проект, **When** разработчик запускает baseline-тесты, **Then** они проходят.

---

### User Story 4 — Тема из дизайн-системы (light + dark) (Priority: P3)

App shell оформлен темой, собранной из дизайн-токенов NOX, поддерживает light и dark и следует системной настройке; в коде каркаса нет ни одного хардкод-стиля.

**Why this priority**: Верность дизайн-системе — принцип конституции; задать её на уровне каркаса дешевле, чем вычищать хардкод позже. Приоритет ниже, чем у сборки и структуры, потому что каркас запускается и без полной темизации.

**Independent Test**: Переключить системную тему — app shell переключается между light и dark; grep по коду каркаса не находит хардкод-цветов/отступов/типографики; splash background остаётся тёмным независимо от темы.

**Acceptance Scenarios**:

1. **Given** запущенный app shell, **When** меняется системная тема устройства, **Then** приложение переключается между light и dark, используя только токены.
2. **Given** код каркаса, **When** его просматривают на предмет стилей, **Then** все цвета, отступы и типографика берутся из токенов, без хардкода.

---

### Edge Cases

- **Десктоп вне блюпринта.** Блюпринт не определяет нативные слои для десктопа (flavor/secrets-механика сборки, push через FCM, deep/universal links, native auth/secure storage). На этой итерации для десктопа эти подсистемы должны иметь явный, документированный fallback (no-op / disabled / placeholder), а не молча ломать сборку.
- **Плагин без desktop-реализации.** Если зависимость из блюпринта не имеет реализации под одну из десктопных платформ, нужно зафиксировать деградацию (заглушка/исключение функции на этой платформе), а не оставлять сборку битой.
- **Flavor-механика на десктопе** (решено). Compile-time flavor'ы `stage`/`prod` спроектированы под Android/iOS; на десктопе (нет native `--flavor`) flavor приходит через `--dart-define-from-file=config/<flavor>.json` (см. FR-010), native-идентичность — prod-only (FR-003).
- **Secure storage / single identity per device на десктопе** (решено). Модель «одна идентичность на устройство, полный local wipe при logout» опирается на платформенное защищённое хранилище; на десктопе это `flutter_secure_storage` (macOS Keychain / Windows DPAPI / Linux libsecret) — бэкенды задокументированы в блюпринте; wiring появляется с auth (в скелете — проза-only, см. FR-012).
- **Пустые вкладки.** `Chats` и `Settings` на этой итерации — плейсхолдеры; должно быть очевидно, что это каркас, а не сломанная фича.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Проект MUST быть одним Dart-пакетом `nox_app` с одним `pubspec.yaml` и слоями-папками блюпринта (`lib/data`, `lib/domain`, `lib/presentation`, `lib/di`, `lib/general`, `lib/design`, `lib/resource`) с однонаправленными зависимостями `presentation → domain ← data` (`domain` не импортирует ничего).
- **FR-002**: Проект MUST собираться (compile/build-verify) под все пять целевых платформ: Android, iOS, Windows, Linux, macOS. App shell MUST запускаться на macOS, iOS, Android на этой итерации; launch-verify Windows/Linux — tracked follow-up (CI-раннеры). Web MUST NOT входить в набор платформенных таргетов.
- **FR-003**: Платформенные конфигурации (идентификаторы приложения, имена, иконки/ассеты запуска) MUST быть выставлены для всех пяти платформ; display name приложения — `NOX`; prod `applicationId`/bundle id — `com.cyphernetlabs.noxapp`, stage — `com.cyphernetlabs.noxapp.stage`. На десктопе native-идентичность — **prod-only** этой итерации: macOS `PRODUCT_BUNDLE_IDENTIFIER = com.cyphernetlabs.noxapp` + `PRODUCT_NAME = NOX`, Windows `BINARY_NAME = NOX` + фиксированный GUID, Linux `APPLICATION_ID = com.cyphernetlabs.noxapp` / `.desktop` `Name = NOX`; distinct stage native-идентичность на десктопе — FUTURE (packaging).
- **FR-004**: App shell MUST быть адаптивным по форм-фактору при одинаковом наборе из трёх назначений (`Chats`, создание чата `+`, `Settings`; отдельного profile-экрана нет): на мобильных таргетах (iOS/Android) — нижняя панель из трёх элементов с центральным docked `+` FAB; на десктопных таргетах (Windows/Linux/macOS) — `NavigationRail` с теми же назначениями (по корпусу `docs/design/system/nox-desktop-screens/`). На этой итерации two-pane list-detail и диалоги-вместо-push НЕ вводятся (приходят с реальными фичами); содержимое вкладок — плейсхолдер full-screen. Переключение оболочки — **width-driven** (`LayoutBuilder`, `Constants.railBreakpoint` = 840dp, M3 medium↔expanded), не по платформе; `NavigationRail` width 80, `labelType.all`, `+` = leading FAB; тело = `IndexedStack`; нативный OS-title-bar и дефолтное окно runner'а (`window_manager` / 1440×900 / min-size / кастомный title bar = FUTURE). Адаптивный shell-паттерн добавляется в блюпринт (`05`/`11`).
- **FR-005**: Тема MUST собираться только из дизайн-токенов (`docs/design/system/nox-handoff/`), Material Design 3, light + dark, системная по умолчанию, seed = teal. В коде каркаса MUST NOT быть хардкод-цветов, отступов, типографики и system-overlay-стилей. Splash background MUST оставаться тёмным независимо от темы.
- **FR-006**: DI MUST подниматься единым `configureDependencies(env)` (injectable + get_it) с одним сгенерированным конфигом; `main.dart` MUST оборачиваться в `runZonedGuarded`, дожидаться инициализации DI и `getIt.allReady()`, затем вызывать `runApp`.
- **FR-007**: Кодоген (freezed + json_serializable + injectable + flutter_gen) MUST проходить за один прогон `build_runner` без ошибок; сгенерированные файлы MUST быть исключены из анализа и не правиться руками.
- **FR-008**: Flutter SDK MUST быть запинен через FVM на версии `3.44.1`; Dart constraint — `>=3.12.0 <4.0.0`; line length — `140`; lint-набор — стоковый `flutter_lints`.
- **FR-009**: Полный code-gate MUST быть зелёным: кодоген (один прогон) → форматирование изменённых файлов (`-l 140`) → анализ с нулём ошибок → baseline-тесты проходят.
- **FR-010**: Compile-time flavor'ы `stage` и `prod` MUST присутствовать; flavor-специфичные значения приходят через конфигурацию сборки, без runtime-ветвления по flavor'у. На десктопе (нет native `--flavor`) flavor выбирается через `--dart-define-from-file=config/<flavor>.json` (только `app.flavor`, закоммичен, без секретов), читается `AppFlavor.getFlavor()`; secrets-decrypt на десктопе в скелете пропускается (без age-ключа).
- **FR-011**: Логирование MUST идти через единый `LogRepository`; сырые `print` / `debugPrint` в `lib/` MUST быть запрещены.
- **FR-012**: Подсистемы, которые блюпринт определяет только для мобильных платформ (flavor/secrets-механика сборки, push через FCM, deep/universal links, native auth/secure storage), MUST иметь на десктопе явный, документированный fallback (no-op / disabled / placeholder) на этой итерации, не ломающий сборку и запуск. **Гранулярность:** проза на подсистему + DI-wired no-op stub только там, где каркас реально резолвит подсистему (в скелете — проза-only, т.к. ни push/deep-links/secure-storage не резолвятся; no-op stub вводится с первым desktop-потребителем). **Стансы:** push = disabled, deep-links = no-op (native `nox://` = FUTURE), secure storage = задокументированы desktop-бэкенды (Keychain/DPAPI/libsecret) + identity/wipe-модель.
- **FR-013**: На этой итерации MUST NOT быть реальных продуктовых фич: нет списка чатов с данными, нет авторизации, нет интеграции с реальным бэкендом, нет регистрации push. **Исключение — verification harness:** сквозной `Item`-слайс блюпринта (model+entity+mapper+dao+network-only repo+PagingState BLoC+страница) коммитится, **явно помеченный как scaffold-demo на mock-данных** (не продуктовая фича, не реальный бэкенд), и несёт baseline-тесты. Кроме этого harness — только структурный каркас.
- **FR-014**: Repository-слой MUST использовать контракт `RepositoryResult<T>` (data XOR exception) как единый тип результата — примитив доступен в каркасе, даже без реальных репозиториев фич.

### Key Entities *(структурные элементы проекта)*

- **App package (`nox_app`)**: единый Dart-пакет — корень всего кода; держит все слои как папки.
- **Layer module**: слой-папка внутри пакета (`data` / `domain` / `presentation` / `di` / `general` / `design` / `resource`) с фиксированными правилами зависимостей.
- **Platform target**: целевая платформа сборки; ровно пять — Android, iOS, Windows, Linux, macOS (без web).
- **Flavor**: compile-time вариант сборки (`stage` / `prod`), задающий идентификаторы и конфигурацию.
- **App shell**: адаптивный навигационный каркас (`Chats` / `+` / `Settings`) — нижняя панель на мобиле, `NavigationRail` на десктопе — с плейсхолдерным содержимым вкладок.
- **Design theme**: тема light/dark, собранная из дизайн-токенов NOX.
- **Verification harness (`Item`-слайс)**: сквозной scaffold-demo-слайс блюпринта на mock-данных (не продуктовая фича) — несёт baseline-тесты и доказывает, что полный вертикальный путь компилируется end-to-end.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Приложение собирается под все пять целевых платформ (5/5 compile/build-verify, подкреплено 3 desktop compile-smoke CI-джобами: `compile-macos` / `compile-windows` / `compile-linux`, debug); app shell запускается без падений на macOS, iOS, Android (launch-verify этой итерации). Launch-verify Windows/Linux — tracked follow-up (CI-раннеры), не блокер этой итерации.
- **SC-002**: На чистом клоне полный code-gate (кодоген → форматирование → анализ → тесты) проходит с нулём ошибок и нулём блокирующих предупреждений.
- **SC-003**: Новый член команды по документированным шагам поднимает окружение и получает запускаемое приложение менее чем за 30 минут, не внося изменений в структуру проекта.
- **SC-004**: Старт новой фичи по шаблону блюпринта не требует реструктуризации каркаса, повторного поднятия DI или ввода новых инфраструктурных примитивов (проверяется наличием собранного по шаблону сквозного `Item`-verification-слайса).
- **SC-005**: В коде каркаса ноль хардкод-стилей (цвета/отступы/типографика — только токены); app shell корректно переключается light↔dark по системной настройке.
- **SC-006**: Набор платформенных таргетов содержит ровно пять платформ; web отсутствует.
- **SC-007**: Для каждой десктоп-специфичной деградации (push, deep-links, secrets/flavor, secure storage) существует явная документированная запись о выбранном fallback — ноль молчаливых пропусков.

## Assumptions

- Блюпринт `docs/patterns/mobile/` (особенно `11-scaffolding-plan.md`) — авторитет по «как»; эта спека фиксирует «что» и границы объёма, а конкретные шаги сборки выводятся из блюпринта на этапах plan/tasks.
- **Расширение платформ согласовано на уровне governance.** Добавление десктопа (Windows/Linux/macOS) выходило за рамки конституции v1.0.0; владелец одобрил, и конституция **поправлена до v1.1.0** (набор платформ — iOS, Android, Windows, Linux, macOS; web — вне scope; Принцип III расширен на весь клиентский Flutter-код). Остаётся зависимость: **расширить блюпринт на desktop** (нативные части — build/secrets, push, deep-links, secure storage, multi-window) либо зафиксировать desktop-fallback per-подсистема.
- **Бэкенд/протокол/криптоядро ещё не выбраны.** Контракты сети, авторизации, конверта, push, file-upload и deep-links остаются примером/TBD по блюпринту; каркас поднимает структуру, но не интегрируется с реальным бэкендом.
- **«Только каркас, без фич».** Первая реальная фича (открытый общий список чатов) — отдельный spec-цикл, не входит в эту инициализацию.
- **Десктопные нативные подсистемы — решены.** Push = disabled/no-op, deep-links = no-op (native `nox://` = FUTURE), secure storage = задокументированы бэкенды (Keychain/DPAPI/libsecret), flavor = `--dart-define-from-file`, secrets-decrypt на десктопе пропущен; no-op stub каждой подсистемы вводится с первым desktop-потребителем. Полный desktop-паритет (packaging/signing, distinct stage native identity, window-полировка) — FUTURE.
- **Десктоп — first-class таргеты этой итерации** (compile на всех трёх, launch на macOS; Windows/Linux launch — CI follow-up), но релизный конвейер (подпись, дистрибуция, packaging) — FUTURE; здесь достаточно собираемого каркаса (+ запуск на macOS).
- Источник истины темы — дизайн-токены `docs/design/system/nox-handoff/`; сгенерированный Dart дропается/регенерируется из токенов, а не правится руками.
- Языки UI продукта — English + Українська (Russian в UI не используется); микрокопия каркаса (`Chats`, `Settings`, `+`) — на английском. На этой итерации каркас — **English-only через `TextConstants`** с ARB-portable ключами; `flutter_localizations`/`gen-l10n` и украинская локаль — отдельная i18n-фича (дефолт блюпринта), где и закрывается требование en+uk Принципа V.

## Dependencies

- ✅ **Поправка конституции** — выполнено: конституция амендмент до **v1.1.0** (набор платформ = iOS + Android + Windows + Linux + macOS, web вне scope; Принцип III расширен). Constitution Check на этапе plan проходит против v1.1.0.
- ✅ **Расширение блюпринта на desktop — выполнено в этом change-set:** desktop-части внесены в `00`/`01`/`05`/`06`/`09`/`11`/`13`/`14`/`15` + `README` (adaptive shell `05`/`11`; desktop flavors/identity/secrets/packaging/CI/min-OS `09`/`11`; deep-links `13`; secure-storage `14`; push `15`). Остаётся FUTURE (не блокер скелета): packaging/signing, distinct stage native identity, `window_manager`-полировка, per-подсистема desktop-native wiring (с первым потребителем).
- **Дизайн-токены**: `docs/design/system/nox-handoff/` должны быть доступны для генерации темы.
