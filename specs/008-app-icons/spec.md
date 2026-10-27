# Feature Specification: App icons — все платформы

**Feature Branch**: `008-app-icons`

**Created**: 2026-06-25

**Status**: Draft

**Input**: User description: "Добавить иконки приложения NOX для всех поддерживаемых платформ (Android, iOS, macOS, Windows, Linux). Готовый набор ресурсов лежит в `docs/design/system/nox-app-icons` (включая `index.html` как визуальное ревью)."

## Контекст

Сейчас приложение использует **дефолтную иконку Flutter** на всех таргетах (iOS / Android / macOS / Windows; на Linux иконка не настроена). Брендовая иконка NOX в лаунчере отсутствует — приложение визуально неотличимо от пустого Flutter-проекта.

Готовый набор иконок для всех платформ уже подготовлен и лежит в `docs/design/system/nox-app-icons/` (структура папок зеркалит Flutter-проект — файлы кладутся «как есть»). Набор включает: единый мастер `source/icon-master-1024.png` + Android-foreground `source/icon-foreground-1024.png`; полные per-platform наборы (iOS `AppIcon.appiconset`, Android `res/` с adaptive, macOS `AppIcon.appiconset` + `.icns`, Windows `app_icon.ico`, Linux `hicolor` + `.desktop`); `index.html` — визуальная галерея для ревью.

**Задокументированные ограничения набора (важно для scope):** набор сгенерирован из единственного растрового логотипа 200×200 (`assets/png/logo.png`, opaque, бэкдроп `#151919`). Размеры **≤256 px чёткие; 512 px и 1024 px — апскейл (мягкие)**. Фон Android adaptive — `#151919` (собственный бэкдроп растра), а не бренд `canvasDark #0C2424`. Оба выбора **временные** — до появления финального векторного логотипа (ожидается, `design-system.md §11` / `nox-assets/brand`). Регенерация из вектора перед публикацией в сторы — **отдельная будущая задача, вне scope этой фичи**.

## Clarifications

### Session 2026-06-25

- Q: Метод установки иконок — drop-in готового набора vs регенерация через `flutter_launcher_icons` из мастера? → A: **Hybrid** — drop-in готового hand-crafted набора сейчас (лучшая визуальная точность), плюс закоммиченный конфиг `flutter_launcher_icons` (на `source/`, фон `#151919`) как воспроизводимый путь регенерации под будущий вектор; генератор сейчас **не запускаем** (чтобы не перезаписать crafted-трактовку macOS rounded-rect / Android adaptive safe-zone).
- Q: Глубина интеграции на Linux — repo-ассеты vs CMake-install vs полный packaging? → A: **Repo-ассеты (packaging-ready)** — закоммитить `hicolor/*` + согласованный `.desktop` (`Exec=nox_app`, `StartupWMClass=com.cyphernetlabs.noxapp`, `Icon=nox`) в репозиторий; видимость в системном меню достигается будущим шагом packaging/install (вне scope этой фичи).
- Q: Глубина верификации / DoD по платформам? → A: Все 5 — зелёный compile-smoke + структурная проверка (ассеты в нативных путях + манифесты ссылаются на них); визуальная проверка на доступных с дев-машины (macOS / iOS-sim / Android-emulator); визуал Windows/Linux отложен до доступности ОС/CI.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Иконка на Android (Priority: P1)

Пользователь устанавливает NOX на Android-устройство и видит в лаунчере брендовую иконку NOX (adaptive: марка поверх тёмного фона), а не дефолтную иконку Flutter.

**Why this priority**: Android и iOS — основная пользовательская база и самая заметная поверхность бренда; иконка лаунчера — первое, что видит пользователь.

**Independent Test**: Собрать Android-таргет (`mise run build:android:stage`), установить на устройство/эмулятор API 26+ и старее — убедиться, что в лаунчере и в списке приложений отображается иконка NOX (adaptive на API 26+, legacy-фолбэк на старых).

**Acceptance Scenarios**:

1. **Given** свежая установка на Android API 26+, **When** пользователь открывает лаунчер, **Then** показывается adaptive-иконка NOX (`ic_launcher_foreground` поверх фона `#151919`), корректно маскируемая темой устройства (круг/squircle/rounded-square).
2. **Given** установка на устройство ниже API 26, **When** пользователь смотрит на иконку, **Then** показывается legacy `ic_launcher` / `ic_launcher_round` (не дефолт Flutter).
3. **Given** листинг в Play Console, **When** загружается иконка приложения, **Then** используется `playstore-icon-512.png`.

---

### User Story 2 — Иконка на iOS (Priority: P1)

Пользователь устанавливает NOX на iPhone/iPad и видит на домашнем экране брендовую иконку NOX; система сама накладывает скругление.

**Why this priority**: см. US1 — мобильная база, максимальная видимость бренда.

**Independent Test**: Собрать iOS-таргет (`mise run build:ios:stage`), установить на симулятор/устройство — убедиться, что иконка NOX видна на домашнем экране и в Settings; проверить отсутствие alpha-канала.

**Acceptance Scenarios**:

1. **Given** установка на iOS, **When** пользователь смотрит на домашний экран, **Then** показывается иконка NOX (квадратная, непрозрачная, скругление накладывает ОС — не скруглённая вручную).
2. **Given** валидация ассетов, **When** проверяется iOS-иконка, **Then** alpha-канал отсутствует (opaque), все требуемые размеры присутствуют (включая 1024 marketing).

---

### User Story 3 — Иконка на macOS (Priority: P2)

Пользователь запускает NOX на macOS и видит иконку NOX в Dock, Launchpad и переключателе приложений (нативная rounded-rect с маржином).

**Why this priority**: десктоп в scope (Windows/Linux/macOS — целевые платформы), но видимость и охват ниже мобильных.

**Independent Test**: Собрать macOS-таргет (`mise run build:macos:stage`), запустить — убедиться, что иконка NOX видна в Dock и переключателе приложений.

**Acceptance Scenarios**:

1. **Given** запуск на macOS, **When** приложение в Dock, **Then** показывается иконка NOX (rounded-rect ≈22.4% радиуса с ~9% маржином, с alpha — нативный вид Dock).
2. **Given** все размеры appiconset (16–1024 + @2x), **When** ОС выбирает размер под контекст, **Then** иконка чёткая во всех штатных местах (Dock/Finder/Launchpad).

---

### User Story 4 — Иконка на Windows (Priority: P2)

Пользователь запускает NOX на Windows и видит иконку NOX в таскбаре, заголовке окна и ярлыке (`.exe`).

**Why this priority**: десктоп в scope; отдельный формат (`.ico`).

**Independent Test**: Собрать Windows-таргет (`mise run build:windows:stage`), запустить — убедиться, что иконка NOX видна в таскбаре и в заголовке окна.

**Acceptance Scenarios**:

1. **Given** запуск на Windows, **When** приложение в таскбаре/заголовке, **Then** показывается иконка NOX из мультиразрешённого `app_icon.ico` (16–256 в одном файле).

---

### User Story 5 — Иконка на Linux (Priority: P3)

Пользователь устанавливает NOX на Linux и видит иконку NOX в меню приложений и доке окружения (через `hicolor` + `.desktop`).

**Why this priority**: десктоп в scope, но Linux — наименьший охват, и интеграция иконки требует уровня упаковки/установки (не drop-in, как у остальных), а также согласования имени бинарника.

**Independent Test**: Собрать Linux-таргет (`mise run build:linux:stage`); при установке `.desktop` + `hicolor` PNG в системные каталоги — убедиться, что иконка NOX видна в меню приложений; либо проверить, что ассеты и `.desktop` корректно попадают в артефакт упаковки.

**Acceptance Scenarios**:

1. **Given** установленный `.desktop` (`Icon=nox`) и `hicolor/<size>/apps/nox.png`, **When** окружение строит меню приложений, **Then** показывается иконка NOX в нужном размере.
2. **Given** реальный Flutter-таргет (`BINARY_NAME=nox_app`, `APPLICATION_ID=com.cyphernetlabs.noxapp`), **When** настраивается `.desktop`, **Then** `Exec` и `StartupWMClass` согласованы с реальным бинарником/WM-классом (присланный набор использует `nox` — рассогласование устраняется).

---

### Edge Cases

- **Мягкие апскейл-размеры (512/1024):** приняты для пред-релизной фазы (сторов пока нет); **перед публикацией в сторы** — обязательная регенерация из финального вектора (вне scope, будущая задача). Зафиксировать как известный долг.
- **Linux: имя бинарника `nox` vs `nox_app`:** присланный `nox.desktop` (`Exec=nox`/`StartupWMClass=nox`) не совпадает с реальным `BINARY_NAME=nox_app`. Согласовать (поправить `.desktop` под `nox_app`/app-id, либо переименовать таргет) — иначе ярлык не запустит приложение / не свяжет окно с иконкой.
- **iOS alpha:** PNG в наборе непрозрачные; если App Store Connect когда-либо пометит alpha — флэттенить на экспорте (Xcode обычно срезает alpha на сборке).
- **Android themed (monochrome) layer отсутствует:** на Android 13+ themed-иконки падают в фолбэк на полноцветный adaptive (валидно). Добавление `<monochrome>` — позже, из вектора.
- **Фон `#151919` vs бренд `#0C2424`:** временно `#151919` (бесшовно с растром); переключить на `#0C2424` при появлении прозрачного вектора.
- **Регрессия сборки:** замена нативных ассетов не должна ломать ни одну из 5 compile-smoke сборок.
- **Источник для регенерации:** мастер живёт в `docs/design/system/nox-app-icons/source/`; путь должен быть доступен для воспроизводимой регенерации (решается в `/plan`).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: На всех пяти платформах (Android, iOS, macOS, Windows, Linux) приложение MUST показывать брендовую иконку NOX вместо дефолтной иконки Flutter — в лаунчере / на домашнем экране / в Dock / таскбаре / меню приложений.
- **FR-002**: Android MUST использовать adaptive icon (API 26+): `foreground`-слой поверх фонового цвета `#151919` (`mipmap-anydpi-v26/ic_launcher.xml` + `ic_launcher_foreground` + `values/ic_launcher_background.xml`), с legacy-фолбэком (`ic_launcher` / `ic_launcher_round`) на устройствах ниже API 26; листинг-иконка Play Console — `playstore-icon-512.png`.
- **FR-003**: iOS-иконка MUST быть непрозрачной (без alpha), квадратной (скругление накладывает ОС), полным `AppIcon.appiconset` со всеми штатными размерами + 1024 marketing.
- **FR-004**: macOS MUST использовать `AppIcon.appiconset` (rounded-rect с маржином, с alpha) во всех размерах 16–1024 (+@2x).
- **FR-005**: Windows MUST использовать мультиразрешённый `app_icon.ico` (16–256) в `windows/runner/resources/app_icon.ico`.
- **FR-006**: Linux MUST поставлять `hicolor/<size>/apps/nox.png` (16–512) + `.desktop` (`Name=NOX`, `Icon=nox`, `Comment=Secure messaging`), при этом `Exec`/`StartupWMClass` MUST быть согласованы с реальным таргетом: конкретно `Exec=nox_app`, `StartupWMClass=com.cyphernetlabs.noxapp` (решено в Clarifications). Ассеты + `.desktop` коммитятся в репозиторий как **packaging-ready** поставка; видимость в системном меню достигается будущим шагом packaging/install (вне scope).
- **FR-007**: Замена иконок MUST NOT ломать сборку ни на одной из пяти платформ — все per-platform compile-smoke сборки остаются зелёными.
- **FR-008**: Проект MUST сохранять задокументированный воспроизводимый путь регенерации всего набора из единого мастера (`source/icon-master-1024.png` + `source/icon-foreground-1024.png`). Конкретно (решено в Clarifications): в проект коммитится конфиг `flutter_launcher_icons` (на эти исходники, `adaptive_icon_background: #151919`), который **сейчас не запускается** — текущая установка идёт drop-in готового hand-crafted набора; конфиг служит воспроизводимой регенерацией при появлении финального вектора.
- **FR-009**: Известные ограничения MUST быть задокументированы в репозитории: 512/1024 — апскейл из 200px (мягкие); фон `#151919` временный; регенерация из вектора перед публикацией в сторы — отдельная будущая задача.
- **FR-010**: Фича MUST менять только иконки — имя приложения, wordmark и прочие брендовые тексты остаются `NOX` без изменений.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: На каждой из пяти платформ свежесобранное приложение показывает иконку NOX (не дефолт Flutter) в системной поверхности (лаунчер/домашний экран/Dock/таскбар/меню). **Уровень проверки (решено в Clarifications):** визуально на доступных с дев-машины (macOS / iOS-sim / Android-emulator); для Windows/Linux — структурная проверка (см. SC-006), визуал — при доступности ОС/CI.
- **SC-002**: Все пять per-platform compile-smoke сборок (`mise run build:<platform>:stage`) проходят после замены иконок (ноль регрессий сборки).
- **SC-003**: Android adaptive icon корректно рендерится на API 26+ (foreground над фоном `#151919`) и имеет работающий legacy-фолбэк ниже API 26.
- **SC-004**: iOS-иконка непрозрачна (без alpha) и содержит все штатные размеры (включая 1024) — проходит формальные требования к ассетам.
- **SC-005**: Полный набор иконок для всех платформ регенерируется из единого мастера одной задокументированной операцией; ре-брендинг при появлении вектора = повтор этой операции (а не ручная пересборка 5 наборов).
- **SC-006**: Для всех пяти платформ нативные ассеты лежат в ожидаемых путях и связаны манифестами/каталогами (`ios`/`macos` `Contents.json`, Android `mipmap-anydpi-v26` + `values/ic_launcher_background.xml`, `windows/runner/resources/app_icon.ico`, Linux `.desktop` + `hicolor`) — проверяемо инспекцией (структурная верификация, независимо от наличия Windows/Linux-машины).

## Assumptions

- **Пред-релизная фаза:** поставка текущего (частично апскейл) набора сейчас допустима — публикации в сторы пока нет; регенерация из финального вектора перед публичным релизом — отдельная будущая задача (вне scope).
- **Фон `#151919`** сохраняется как есть (бесшовно с растром); переключение на бренд `#0C2424` — вместе с приходом прозрачного вектора (вне scope).
- **Источник истины** для этой фичи — готовый набор `docs/design/system/nox-app-icons/` (структура зеркалит Flutter-проект).
- **Web — вне scope** (вне scope проекта в целом).
- **Имя приложения** не меняется (только иконки); отображаемое имя остаётся `NOX`.
- **Метод установки (решено, Clarifications 2026-06-25):** **hybrid** — drop-in готового hand-crafted набора сейчас (лучшая визуальная точность; `flutter_launcher_icons` сейчас НЕ запускаем, чтобы не перезаписать crafted-трактовку macOS/adaptive), плюс закоммиченный конфиг `flutter_launcher_icons` на `source/` как воспроизводимый путь регенерации под будущий вектор (FR-008).

## Out of Scope

- Финальный векторный логотип и регенерация набора из него (включая переключение фона на `#0C2424` и добавление Android `<monochrome>`-слоя).
- Публикация в сторы и листинговые ассеты сверх предоставленной `playstore-icon-512.png`.
- Splash-экран и in-app логотип (splash уже использует `assets/png/logo.png` — отдельная поверхность).
- Иконки уведомлений (push/notification small icon).
- Любые изменения брендовых текстов/имени приложения.
- Системная установка / пакетирование под Linux (`.deb` / AppImage / flatpak): ассеты и `.desktop` готовятся (packaging-ready), но интеграция в системное меню — будущий packaging-шаг.
