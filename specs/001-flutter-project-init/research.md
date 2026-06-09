# Research / Decisions: Инициализация Flutter-проекта NOX (multi-platform skeleton)

**Branch**: `001-flutter-project-init` | **Phase**: 0 (research) | **Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

## Назначение

Это канонический record решений Phase 0. Для Feature-001 фаза clarify (4 решения) и
desktop/blueprint deep-dive (18 решений, все recommended) уже разрешили все неизвестные; этот
файл консолидирует их в формате **Decision / Rationale / Alternatives considered** и фиксирует
инварианты блюпринта, которые наследует скелет. Авторитет по «как» — `docs/patterns/mobile/`
(особенно `11-scaffolding-plan.md`); эта спека фиксирует «что» и границы объёма.

## Resolved unknowns

- **`NEEDS CLARIFICATION` — ноль.** Все открытые вопросы спеки закрыты в `## Clarifications`
  (4 решения сессии 2026-06-09 + desktop deep-dive из 18 решений) и спроецированы в блюпринт
  (`00`/`01`/`05`/`06`/`09`/`11`/`13`/`14`/`15` + `README`).
- **Бэкенд / протокол / криптоядро — намеренно не выбраны (не блокер).** Это ограничение
  конституции: контракты сети, авторизации, конверта ответа, push-эндпоинтов, file-upload и
  deep-link-схемы остаются **пример/TBD** по блюпринту (`04`/`14`/`15`/`16`). Скелет поднимает
  структуру и НЕ интегрируется с реальным бэкендом (FR-013), поэтому отсутствие контракта не
  блокирует ни план, ни tasks. Любой network/auth/envelope/endpoint-артефакт в скелете —
  пример с пометкой TBD, заменяемый на реальный контракт с первой бэкенд-фичей.

---

## A. Решения clarify (4)

### A1. App shell на десктопе — adaptive nav без list-detail

- **Decision**: App shell — **адаптивный по форм-фактору** при одинаковом наборе из трёх
  назначений (`Chats` / создание чата `+` / `Settings`): нижняя панель на iOS/Android,
  `NavigationRail` на Windows/Linux/macOS. Содержимое вкладок — плейсхолдер full-screen. Two-pane
  list-detail и диалоги-вместо-push на этой итерации **не вводятся** (приходят с реальными фичами).
  Блюпринт `05`/`11` расширяется вторым (adaptive) shell-паттерном.
- **Rationale**: Десктоп — first-class таргет (v1.1.0), но переписывать оболочку под list-detail
  до появления реальных экранов преждевременно; адаптивная оболочка с общим набором назначений
  даёт корректную desktop-раскладку без продуктовой логики и совместима с FR-013 (нет фич).
- **Alternatives considered**: (a) мобильный bottom-bar на десктопе (FR-004-исходный) —
  отвергнут как не desktop-нативный; (b) полноценный desktop-shell по `nox-desktop-screens`
  (two-pane list-detail + диалоги) — отвергнут как преждевременный для скелета (см. «Alternatives
  rejected» → *full-adaptive-now*, *bottom-bar-everywhere*).

### A2. Объём «build + launch на 5 платформах» (SC-001)

- **Decision**: **Launch-verify** на macOS + iOS + Android на этой итерации; Windows/Linux — только
  **compile/build-verify** (debug compile-smoke). Полный launch-verify Windows/Linux — tracked
  follow-up на CI-раннерах, не блокер.
- **Rationale**: Запуск под три ОС, доступные исполнителю/CI сейчас, доказывает живую оболочку;
  Windows/Linux launch требует выделенных раннеров и keyring-предусловий (libsecret) — это
  отдельная инфраструктурная работа, не влияющая на готовность каркаса.
- **Alternatives considered**: launch-verify всех 5 платформ сейчас — отвергнут (нет раннеров; не
  блокирует структуру каркаса; см. «Alternatives rejected» → *all-5-launch-now*).

### A3. Локализация — отложить full i18n

- **Decision**: **English-only** через `TextConstants` с ARB-portable ключами; **без**
  `flutter_localizations`/`gen-l10n` и без украинской локали на этой итерации. Микрокопия каркаса
  (`Chats`, `Settings`, `+`) — на английском. en+uk — отдельная i18n-фича.
- **Rationale**: Дефолт блюпринта; ARB-portable ключи делают будущий переход на ARB дешёвым;
  каркас запускается и без локализации, а Принцип V (языковая дисциплина) соблюдён (UI EN-only).
  Полное требование en+uk закрывается в i18n-фиче, где и появляется `flutter_localizations`.
- **Alternatives considered**: подключить `flutter_localizations`/`gen-l10n` + uk-локаль в каркасе
  — отвергнут как преждевременный gold-plating вне объёма скелета (см. «Alternatives rejected» →
  *wire-i18n-now*).

### A4. SC-004 «neutral-шаблон» vs DoD-слайс при FR-013 — коммитить `Item`-harness

- **Decision**: Сквозной `Item`-слайс блюпринта (model + entity + mapper + dao + network-only repo
  + `PagingState`-BLoC + страница) **коммитится** как **verification harness**, явно помеченный как
  scaffold-demo на **mock-данных** (не продуктовая фича, не реальный бэкенд). Несёт baseline-тесты
  (bloc smoke + mapper round-trip).
- **Rationale**: FR-013 запрещает реальные продуктовые фичи, но не verification-harness;
  сквозной слайс доказывает, что полный вертикальный путь компилируется end-to-end (DoD блюпринта
  `11`), и даёт осмысленный зелёный gate. Список чатов (первая реальная фича) ляжет в этот слайс
  один-в-один (network-only paginated carve-out).
- **Alternatives considered**: голый neutral-шаблон без сквозного слайса — отвергнут: оставил бы
  gate без тестов и не доказал бы совместимость слоёв (нарушил бы DoD блюпринта при формально
  выполненном FR-013).

---

## B. Desktop/blueprint deep-dive (18 решений)

Все 18 — recommended, внесены в блюпринт в том же change-set. Сгруппированы по осям Shell / Build /
Fallbacks / Matrix-CI.

### B-Shell (адаптивная оболочка)

> Внесено в `05` §6.5 и `11` Шаг 9. Референс desktop-раскладки — `docs/design/system/nox-desktop-screens/`.

- **B1. Custom breakpoint, без `flutter_adaptive_scaffold`.**
  **Decision**: Адаптив строим сами на `AppShell` (`LayoutBuilder`-обёртка), без сторонней
  adaptive-scaffold-зависимости. **Rationale**: `custom_adaptive_scaffold`/`flutter_adaptive_scaffold`
  исключены блюпринтом (`11` Шаг 2); один шов адаптива не требует фреймворка.
  **Alternatives considered**: `flutter_adaptive_scaffold` — отвергнут (лишняя зависимость, навязывает
  list-detail-модель, которую мы откладываем).
- **B2. Switch width-driven на `Constants.railBreakpoint = 840dp`, не `Platform`-driven.**
  **Decision**: Ветвление по `constraints.maxWidth >= 840` (граница M3 medium↔expanded), не по
  `Platform`. **Rationale**: один size-зависимый код корректен на всех 5 таргетах; узкое окно на
  десктопе остаётся на мобильной раскладке, большой планшет получает rail. **Alternatives considered**:
  `Platform.isWindows/…` — отвергнут (ломает планшеты и resize-десктоп, дублирует ветки).
- **B3. `NavigationRail` width 80, `labelType.all`, 2 destination.**
  **Decision**: Desktop-ветка — `Row[ NavigationRail(width: 80, extended: false,
  labelType: NavigationRailLabelType.all), VerticalDivider(width: 1), Expanded(body) ]`; две
  destination (`Chats` = `forum`, `Settings` = `settings`). **Rationale**: точные значения из `05` §6.5;
  две destination, т.к. `+` — не destination (см. B4) и profile-экрана нет (см. B5). **Alternatives
  considered**: extended-rail / `extended: true` — отвергнут (не нужен в скелете; ширина 80 — канон).
- **B4. `+` = leading FAB рейла.**
  **Decision**: На десктопе `+` — `leading: FloatingActionButton(child: Icon(Icons.add))` рейла; на
  мобиле — центральный docked `+` FAB (`BottomAppBar` с `CircularNotchedRectangle` +
  `floatingActionButtonLocation: centerDocked`, стоковый `NavigationBar` не умеет docked-FAB).
  **Rationale**: единое назначение «создать чат» в обоих форм-факторах; `05` §6.5 + locked-спека
  `docs/design/spec/screens/tab-bar-shell.md`. **Alternatives considered**: `+` как третья
  destination рейла — отвергнут (это действие, не вкладка).
- **B5. Без аккаунт-аватара / profile.**
  **Decision**: В оболочке нет аккаунт-аватара и нет profile-экрана; profile-like items живут в
  Settings. **Rationale**: продуктовая модель NOX («No profile screen»). **Alternatives considered**:
  trailing-аватар в рейле — отвергнут (нет profile в продукте).
- **B6. No list-detail (этой итерации).**
  **Decision**: Two-pane list-detail и диалоги-вместо-push не вводятся; тело = `IndexedStack`
  (сохраняет состояние вкладок). **Rationale**: FR-013 (нет фич) + A1. **Alternatives considered**:
  см. A1.
- **B7. Single-window.**
  **Decision**: Одно окно на приложение; `desktop_multi_window` исключён; единый `Navigator` /
  `MaterialApp.navigatorKey` на всех 5 таргетах. **Rationale**: `05` (single-window — единый канон).
  **Alternatives considered**: multi-window (`desktop_multi_window`) — отвергнут (исключён блюпринтом).
- **B8. Дефолтное окно runner'а + нативный OS-title-bar.**
  **Decision**: Скелет поставляет дефолтное окно desktop-раннера (нативный chrome/title bar), **без**
  `window_manager`. Начальный размер `1440×900` / `minimumSize 640×600` / кастомный unified title
  bar — **FUTURE** (`TODO(blueprint-desktop-window)`). **Rationale**: оболочка size-driven (B2)
  корректна при любом размере окна — управление окном не требуется для каркаса. **Alternatives
  considered**: `window_manager`/`bitsdojo_window` сейчас — отвергнуты (исключены блюпринтом; полировка
  окна — FUTURE).

### B-Build (флейворы / идентичность / секреты / packaging)

> Внесено в `09` §4/§7a/§11a и `11` Шаги 2/14.

- **B9. Desktop-флейворы через `--dart-define-from-file=config/<flavor>.json`.**
  **Decision**: На десктопе нативного `--flavor` нет — flavor выбирается через
  `--dart-define-from-file=config/<flavor>.json` (закоммиченный, secret-free файл, только
  `{"app.flavor":"stage|prod"}`), читается `AppFlavor.getFlavor()` из `String.fromEnvironment`.
  **Rationale**: Flutter не поддерживает product flavors для desktop-таргетов; резолюция и маппинг
  (`prod → Environment.prod`, `stage → Environment.dev`) идентичны мобильным. **Alternatives
  considered**: native desktop-флейворы — отвергнут (нет такого механизма в Flutter desktop).
- **B10. Desktop-идентичность — prod-only native.**
  **Decision**: Native-идентичность на десктопе — **только prod**: macOS
  `PRODUCT_BUNDLE_IDENTIFIER = com.cyphernetlabs.noxapp` + `PRODUCT_NAME = NOX`; Windows
  `BINARY_NAME = NOX` + закоммиченный фиксированный GUID + `VERSIONINFO` (`CompanyName = Cyphernet
  Labs`, `ProductName = NOX`); Linux `APPLICATION_ID = com.cyphernetlabs.noxapp` + `.desktop`
  `Name = NOX`. Distinct stage native-идентичность на десктопе — FUTURE (packaging). Stage на
  десктопе виден только через `app.flavor` в Dart. **Rationale**: одна нативная конфигурация на
  платформу достаточна для compile/launch скелета; раздельные stage/prod-артефакты требует packaging,
  который отложен. **Alternatives considered**: distinct stage native identity сейчас — отвергнут
  (см. «Alternatives rejected» → *distinct-stage-native-desktop-now*).
- **B11. Secrets-decrypt на десктопе — пропускается.**
  **Decision**: Desktop в скелете не потребляет реальных секретов → пропускает `secrets:decrypt`,
  не нуждается в age-ключе; `build:<desktop>:<flavor>` несёт только `--dart-define-from-file`.
  **Rationale**: нет бэкенда/секретов в скелете (FR-013); SOPS+age+mise остаётся для Android/iOS,
  на desktop расширяется, когда появятся секреты. **Alternatives considered**: тянуть age-ключ на
  desktop сейчас — отвергнут (нечего расшифровывать).
- **B12. Packaging/signing — FUTURE.**
  **Decision**: Desktop packaging/signing (Windows MSIX + EV/OV code-signing; macOS DMG + `codesign`
  + notarization через `xcrun notarytool` + hardened runtime; Linux AppImage и/или `.deb`) —
  **FUTURE** (`TODO(blueprint-desktop-packaging)`), в скелет не входят. **Rationale**: тот же блокер,
  что у мобильного CD — нет аккаунтов/сертификатов подписи; скелету достаточно собираемого артефакта.
  **Alternatives considered**: настроить packaging сейчас — отвергнут (нет сертификатов; вне объёма
  скелета).

### B-Fallbacks (desktop-native подсистемы)

> Внесено в `13` §9, `14` §«Secure storage — desktop backends & local wipe», `15` §10. Гранулярность:
> **проза на подсистему + DI-wired no-op stub только там, где каркас реально резолвит подсистему.** В
> скелете ни push, ни deep-links, ни secure-storage не резолвятся → **проза-only**; no-op stub каждой
> подсистемы вводится **с первым desktop-потребителем**, не раньше (FR-012).

- **B13. Push — disabled / no-op.**
  **Decision**: На Windows/Linux/macOS push деградирует в no-op; `firebase_*` подключаются как
  mobile-only feature-gated (platform-conditional) deps; desktop-env регистрирует no-op
  `PushTokenRepository`. В скелете — проза-only (FCM не подключён вовсе, FR-013). **Rationale**:
  desktop push вне scope (FUTURE отдельный канал); FCM mobile-only. **Alternatives considered**:
  desktop push-канал сейчас — отвергнут (FUTURE).
- **B14. Deep-links — no-op.**
  **Decision**: В скелете deep links — no-op: `DeepLinkRepository` не регистрируется в DI, `AppRoot`
  не подписан на `watchDeepLink()`. `app_links` кросс-компилируется на desktop из коробки (гейтить
  по платформе не нужно). Native-регистрация custom-scheme `nox://` (macOS Info.plist
  `CFBundleURLTypes`; Windows registry; Linux `.desktop` `MimeType=x-scheme-handler/nox`) — **FUTURE**,
  вносится с самой deep-link-фичей. Single-window: warm-link будит то же окно через
  `stringLinkStream`, без второго окна/Navigator. **Rationale**: FR-013 (нет фич); пайплайн вносится
  с deep-link-фичей. **Alternatives considered**: native `nox://` сейчас — отвергнут (FUTURE).
- **B15. Secure storage — задокументированы desktop-бэкенды.**
  **Decision**: `flutter_secure_storage` кросс-платформен (5/5); бэкенды задокументированы — macOS
  Keychain / Windows DPAPI/wincreds / Linux libsecret/gnome-keyring (или KWallet). Продуктовое правило
  «one identity per device» + «full local wipe на Logout» (`secureStorage.deleteAll()` + очистка
  Sembast/`shared_preferences`) — единый путь без платформенных веток. Linux known-risk: рабочий
  keyring — рантайм-предусловие именно для launch-deferred Windows/Linux. В скелете secure storage
  **не подключается** (нет `AuthRepository`, FR-013); активируется с будущим auth-флоу. **Rationale**:
  identity/wipe-модель опирается на ОС-keystore, который есть на всех 5; wiring появляется с auth.
  **Alternatives considered**: подключить `AuthRepository`/secure-storage сейчас — отвергнут (нет
  auth-флоу в скелете).

### B-Matrix / CI

> Внесено в `09` §8.2/§«Platform support matrix» и `11` Шаги 2/13.

- **B16. `flutter create --platforms=android,ios,macos,windows,linux` (без web).**
  **Decision**: Пять нативных runner'ов одного пакета генерируются `flutter create --org
  com.cyphernetlabs --project-name nox_app --platforms=android,ios,macos,windows,linux .`; `web/` не
  генерируется. **Rationale**: ровно 5 целевых платформ (v1.1.0); web вне scope (FR-002, SC-006).
  **Alternatives considered**: включить web — отвергнут (вне scope конституции).
- **B17. Min-OS = дефолты Flutter 3.44.1.**
  **Decision**: Минимальные версии — дефолты `flutter create` под Flutter 3.44.1: Windows 10 /
  macOS 10.15+ / Linux GTK3. Пиннинг конкретики и подбор Linux apt-deps — FUTURE (с packaging).
  **Rationale**: floor от `flutter create`-дефолтов достаточен для скелета; точный min-OS-таргетинг —
  релизная задача. **Alternatives considered**: пинить min-OS сейчас — отвергнут (FUTURE, с packaging).
- **B18. 3 compile-smoke desktop CI-джоба.**
  **Decision**: `.github/workflows/compile-check.yml` несёт **3 desktop compile-only джоба**
  (`compile-macos` / `compile-windows` / `compile-linux`, `--debug`, без секретов; Linux ставит
  `ninja-build libgtk-3-dev`), плюс мобильные `compile-android` / `compile-ios` (iOS `--no-codesign`).
  Закрывает `TODO(blueprint-desktop-build)`. Без Rust/FFI/`frb_*` шагов. **Rationale**: доказывает
  5/5 compile (SC-001) на CI; debug compile-check секретов не требует. **Alternatives considered**:
  launch-джобы Windows/Linux в CI сейчас — отвергнуты (нужны раннеры/keyring; tracked follow-up, A2).

**Сквозные исключения (подтверждены, без yaru-deps).** Единая Material 3 на всех 5 таргетах, **без**
`yaru`; исключённые зависимости подтверждены: `flutter_adaptive_scaffold` / `custom_adaptive_scaffold`
(адаптив строим сами, B1), `desktop_multi_window` (single-window, B7), `window_manager` /
`bitsdojo_window` (дефолтное окно, B8). `NavigationRail`-цвета берутся из стокового M3 `ColorScheme`
(`secondaryContainer`/`onSecondaryContainer`) — новой роли в `AppColors` не нужно.

---

## C. Инварианты блюпринта, наследуемые скелетом

Не пере-решаются здесь — это standing-решения блюпринта (см. `README` «Несущие инварианты» и
`08-conventions-and-constitution.md»). Скелет строится строго к ним.

| # | Инвариант | Источник |
|---|---|---|
| C1 | **Один Dart-пакет** `nox_app`, слои — папки в одном `lib/` (`data`/`domain`/`presentation`/`di`/`general`/`design`/`resource`); один `pubspec.yaml`, один `build_runner`; зависимости `presentation → domain ← data`, `domain` не импортирует ничего | `00`, `11` |
| C2 | **BLoC = Freezed**: `@freezed sealed` State/Event, тонкий `BaseBloc<E,S>` с `executeLogic`, производная логика в extension-геттерах, без `*.g.dart` на BLoC-типах | `05` |
| C3 | **Единый DI**: один `configureDependencies(env)` + один `@InjectableInit($initGetIt)` + один `.config.dart` (injectable + get_it) | `02` |
| C4 | **`RepositoryResult<T>`** — `@freezed` data-XOR-exception; `RepositoryException` как единый домен-тип ошибок; `match<R>(onData,onError)` | `03` |
| C5 | **Sembast cache-first** реактивные репозитории (`BehaviorSubject` + DAO, env-scoped `AppDatabase` Dev/Prod=IO, Test=memory) с **network-only carve-out** для server-owned paginated списков и one-shot POST'ов | `04` |
| C6 | **`infinite_scroll_pagination` ^5** — stateless `PagingState`-в-bloc (никогда `PagingController`), `PagingStateExt.applyPage`; дефолт — OFFSET | `07` |
| C7 | **Только design-токены**: M3 light+dark через `ThemeExtension<AppColors>` + `AppTheme.light()/dark()` + `themeMode` из `AppRootBloc`, `flutter_screenutil`-токены; seed = teal из `nox-handoff`; **без** хардкода цвета/отступов/типографики/overlay; splash background — тёмный независимо от темы | `06` |
| C8 | **Обязательный `LogRepository`** — единый канал логирования; сырые `print`/`debugPrint` в `lib/` запрещены | `04` |
| C9 | **Codegen-first** (freezed + json_serializable + injectable + flutter_gen), один прогон `build_runner`; генерируемые файлы исключены из анализа и не правятся руками | `01`, `03`–`07` |
| C10 | **FVM-пин Flutter `3.44.1`** (`.fvmrc`), Dart `>=3.12.0 <4.0.0`, line length `140`, стоковый `flutter_lints` | `01`, `08` |
| C11 | **Compile-time изоляция флейворов** `stage`/`prod` (`AppFlavor.getFlavor()` из `String.fromEnvironment('app.flavor')`), без runtime-ветвления; `main.dart` в `runZonedGuarded` → `configureDependencies(env)` → `getIt.allReady()` → `runApp(AppRoot)` | `09`, `02` |

---

## Alternatives rejected (явный список спорных)

- **full-adaptive-now** — полноценный desktop-shell (two-pane list-detail + диалоги-вместо-push)
  по `nox-desktop-screens` сейчас. Отвергнут: преждевременно без реальных экранов; FR-013 (нет фич).
  Принято: adaptive nav без list-detail (A1, B6).
- **bottom-bar-everywhere** — мобильный bottom-bar и на десктопе. Отвергнут: не desktop-нативно.
  Принято: `NavigationRail` на десктопе, width-driven (A1, B2/B3).
- **all-5-launch-now** — launch-verify всех 5 платформ на этой итерации. Отвергнут: нет
  Windows/Linux раннеров/keyring; не блокирует каркас. Принято: launch macOS+iOS+Android, compile
  Win+Linux (A2, B18).
- **wire-i18n-now** — подключить `flutter_localizations`/`gen-l10n` + uk-локаль в каркас. Отвергнут:
  вне объёма скелета. Принято: EN-only через `TextConstants` (ARB-portable), full i18n — отдельная
  фича (A3).
- **distinct-stage-native-desktop-now** — отдельная stage native-идентичность (2 артефакта на
  платформу) на десктопе сейчас. Отвергнут: требует packaging, который FUTURE. Принято: prod-only
  native, stage — только через `app.flavor` в Dart (B10, B12).
- **full-no-op-stubs** — DI-wired no-op stub для каждой desktop-native подсистемы (push/deep-links/
  secure-storage) в скелете. Отвергнут: каркас ни одну из них не резолвит (FR-013), DI-stub без
  потребителя — мёртвый код. Принято: проза-only; no-op stub вводится с первым desktop-потребителем
  (B13–B15, FR-012).
