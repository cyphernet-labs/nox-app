# Быстрый старт: проверка скелета NOX (Feature-001)

**Branch**: `001-flutter-project-init` | **Phase**: 1 | **Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

**Назначение.** Runnable-руководство, доказывающее, что скелет `nox_app` работает end-to-end на чистом клоне: окружение поднимается, скелет собирается под все пять таргетов, code-gate зелёный, app shell запускается там, где есть ОС, тема переключается light↔dark, а структура готова к старту фич без реструктуризации. Это **гайд проверки**, не имплементация: тел кода здесь нет — шаги скаффолдинга живут в блюпринте [`docs/blueprints/mobile/11-scaffolding-plan.md`](../../docs/blueprints/mobile/11-scaffolding-plan.md) и [`12-dev-commands.md`](../../docs/blueprints/mobile/12-dev-commands.md).

**Границы.** Скелет (FR-013): реальных продуктовых фич нет. Единственный вертикальный путь — `Item`-harness (scaffold-demo на mock-данных): он несёт baseline-тесты и доказывает, что слои компилируются вместе. Бэкенд/протокол/крипто **не выбраны** — все сетевые/auth/envelope-контракты в блюпринте помечены как пример/TBD.

**Терминология приёмки** (из spec.md Clarifications):
- **launch-verify** — собрать **и запустить** app shell, убедиться, что он появляется без падений. Применяется к macOS, iOS, Android.
- **compile/build-verify** — собрать в `--debug` и убедиться, что компиляция проходит; запуск отложен. Применяется к Windows, Linux (launch — tracked follow-up на CI-раннерах).

Каждый сценарий ниже — **команда + ожидаемый результат**. Все вызовы Flutter/Dart идут через `fvm` (Flutter `3.44.1`); голые `flutter`/`dart` не используются.

---

## 1. Предварительные требования (окружение)

**Цель:** воспроизводимое окружение у любого члена команды (SC-003 — рабочее приложение < 30 минут, без правок структуры).

### 1.1 FVM — пин Flutter SDK

```bash
brew install fvm     # macOS; для других платформ см. https://fvm.app
fvm install          # читает .fvmrc, ставит Flutter 3.44.1 в .fvm-кэш
fvm flutter --version
```

**Ожидаемо:** `fvm install` ставит Flutter `3.44.1` без интерактива; `fvm flutter --version` печатает `Flutter 3.44.1` и `Dart 3.x` (≥ `3.12.0`). `.fvmrc` (содержит `{"flutter": "3.44.1"}`) — закоммичен; `.fvm/flutter_sdk` — в `.gitignore`.

### 1.2 mise — инструменты и секреты (опционально на этой итерации)

```bash
mise install         # пинит sops 3.9 / age 1.2 + граф задач decrypt→build
```

**Ожидаемо:** `mise` доступен для mise-задач сборки (`build:<platform>:<flavor>`) и секретов. **Для скелета на десктопе age-ключ не нужен:** desktop-сборки не потребляют реальных секретов и **пропускают** `secrets:decrypt` (флейвор приходит только через `config/<flavor>.json`, без age-ключа — блюпринт `09` §0/§4/§7a). Для мобильных флейворных **релизных** сборок секреты разворачиваются через SOPS+age+mise — но для `--debug` compile/launch скелета они тоже не требуются.

### 1.3 Платформенные toolchain'ы (по таргету, который проверяете)

| Таргет | Что должно стоять |
|---|---|
| iOS | Xcode + симулятор/устройство |
| Android | Android SDK + эмулятор/устройство |
| macOS | Xcode (нативный сборщик desktop) |
| Windows | Visual Studio (C++ desktop workload) |
| Linux | `ninja-build`, `libgtk-3-dev` (GTK3-embedder; блюпринт `09` §8.2) |

```bash
fvm flutter doctor
```

**Ожидаемо:** `flutter doctor` зелёный для тех таргетов, что собираете. Min-OS — дефолты Flutter `3.44.1` (Windows 10 / macOS 10.15 / GTK3); пин конкретики — FUTURE.

---

## 2. Настройка / scaffold (указатель на блюпринт)

**Цель:** поднять структуру скелета по упорядоченному плейбуку. Здесь — только указатель: точные шаги/файлы/шаблоны — в блюпринте `11`, шаги 1–16. **Не инлайнить здесь код** — брать verbatim из шаблонов.

Опорные шаги блюпринта `11`:

1. **Scaffold пяти runner'ов** (шаг 2): создаёт реальный Flutter-проект под ровно пять таргетов (без web).
   ```bash
   fvm flutter create --org com.cyphernetlabs --project-name nox_app \
     --platforms=android,ios,macos,windows,linux .
   ```
   Затем заменить сгенерированный `pubspec.yaml` единым манифестом (`name: nox_app`, объединённые зависимости одного пакета) и:
   ```bash
   fvm flutter pub get
   ```
2. **Слои-папки + база** (шаги 3–9): `build.yaml` / `analysis_options.yaml` (line length `140`, генерируемые исключены), дерево `lib/{data,domain,presentation,di,general,design,resource}`, доменная база (`RepositoryResult<T>`), data-база (`LogRepository`, env-scoped `AppDatabase`), единый DI (`configureDependencies(env)`), тема из токенов, presentation-база + адаптивный `AppShell`.
3. **`Item`-harness end-to-end** (шаг 10): сквозной scaffold-demo-слайс (model → entity → mapper → network-only repo → PagingState-BLoC → page) на mock-данных.
4. **Tooling + tests + CI + flavors** (шаги 11–14): скрипты, baseline-тесты, `ci.yml` + `compile-check.yml`, desktop flavor-конфиги `config/{stage,prod}.json` (`{"app.flavor": "<flavor>"}`, закоммичены, без секретов).

**Кодоген — один прогон** на весь пакет (один `pubspec.yaml`, один `build_runner`):

```bash
fvm dart run build_runner build --delete-conflicting-outputs
```

**Ожидаемо:** сгенерированы `*.freezed.dart` (Freezed-модели/BLoC-юнионы/`RepositoryResult`), `*.g.dart` (только entity-слой), `lib/di/configure_dependencies.config.dart` (ровно один `$initGetIt`). Runner'ы пяти таргетов (`android/ ios/ macos/ windows/ linux/`) на месте, `web/` нет.

---

## 3. Code-gate (зелёный gate — SC-002 / FR-009)

**Цель:** на чистом клоне полный gate проходит с нулём ошибок и нулём блокирующих предупреждений. Порядок: **кодоген (один прогон) → формат изменённых файлов (`-l 140`) → analyze (ноль ошибок) → baseline-тесты**.

```bash
# 1. Кодоген — ОДИН прогон по всему lib/ (без data->domain->root порядка)
fvm dart run build_runner build --delete-conflicting-outputs

# 2. Формат — ТОЛЬКО изменённые файлы, явные пути, line length 140
fvm dart format -l 140 <изменённые .dart-пути>

# 3. Статический анализ — ноль ошибок (генерируемые файлы исключены)
fvm flutter analyze

# 4. Baseline-тесты
fvm flutter test
```

**Ожидаемо по шагам:**
1. `build_runner` завершается кодом 0, без конфликтов (`--delete-conflicting-outputs` чистит устаревшие выходы). Доменные модели и BLoC-типы — только `*.freezed.dart` (никаких `*.g.dart`); `item_entity.g.dart` есть (entity — с JSON).
2. Форматирование стабильно при line length `140`; повторный прогон не даёт диффа. Генерируемые файлы (`*.g.dart`, `*.freezed.dart`, `*.config.dart`, `lib/design/gen/**`) не форматируются и не правятся руками.
3. `fvm flutter analyze` — **ноль ошибок** (стоковый `flutter_lints`, генерируемые файлы и `build/` исключены).
4. `fvm flutter test` — зелёный: baseline-набор `Item`-harness (`ItemListBloc` smoke `Initialize → Initialized` + раунд-трип `ItemMapper` `ItemEntity ↔ ItemModel` без потерь).

> Локальное зеркало CI (тот же порядок, что `ci.yml`): `make generate && make format && make analyze && make test` (блюпринт `09` §8.3). `make format` форматирует всё дерево с `--set-exit-if-changed` — это **CI-гейт**, не шаг завершения задачи; в работе форматируйте только изменённые файлы.

---

## 4. Сборка / запуск по каждой платформе (SC-001 / US1)

**Цель:** скелет собирается под все пять таргетов; app shell запускается без падений на macOS, iOS, Android (launch-verify); Windows/Linux — compile/build-verify. Ровно пять таргетов, web нет.

### 4.1 launch-verify — macOS, iOS, Android

```bash
# macOS (desktop launch-verify; флейвор через config-файл, нативного --flavor нет)
fvm flutter run -d macos --dart-define-from-file=config/stage.json

# iOS (флейвор через --dart-define-from-file; нативного --flavor нет — skeleton carve-out)
fvm flutter run -d <ios-device-or-simulator> --dart-define-from-file=config/stage.json

# Android
fvm flutter run -d <android-device-or-emulator> --dart-define-from-file=config/stage.json
```

**Ожидаемо:**
- **iOS / Android** (`maxWidth < 840dp`): app shell появляется с **нижней панелью** — `Chats` / центральный docked `+` FAB / `Settings` — без падений (US1 сценарий 1). Тап по `+` — no-op со snackbar'ом (не create-flow).
- **macOS** (десктоп-окно `≥ 840dp`): тот же app shell, но с **`NavigationRail`** (ширина `80`, `labelType.all`, `+` как leading-FAB) — адаптив по форм-фактору, **width-driven** на `Constants.railBreakpoint = 840dp`, не по платформе — без падений (US1 сценарий 2). Нативный OS-title-bar, дефолтное окно runner'а.
- Обе destination'ы (`Chats` / `Settings`) ведут на страницу-плейсхолдер `Item`-harness через `IndexedStack`. List-detail / двухпанельная раскладка отсутствуют (приходят с фичами).

> Проверка адаптивного шва на одном таргете: на macOS перетащить край окна через границу `840dp` — раскладка переключается `NavigationRail` ↔ нижняя панель (шов width-driven, не `Platform`-driven).

### 4.2 compile/build-verify — Windows, Linux

```bash
fvm flutter build windows --debug --dart-define-from-file=config/stage.json
fvm flutter build linux   --debug --dart-define-from-file=config/stage.json
```

**Ожидаемо:** обе сборки проходят успешно (US1 сценарий 3). Запуск Windows/Linux на этой итерации **не** проверяется — tracked follow-up на CI-раннерах (не блокер). Подкреплено 3 desktop compile-smoke CI-джобами (`compile-macos` / `compile-windows` / `compile-linux`, `--debug`, без секретов; блюпринт `09` §8.2).

### 4.3 Ровно пять таргетов, web отсутствует (SC-006 / US1 сценарий 4)

```bash
ls -d android ios macos windows linux 2>/dev/null   # пять runner'ов
ls web 2>/dev/null || echo "no web target"           # web отсутствует
```

**Ожидаемо:** присутствуют ровно пять runner'ов (`android/ ios/ macos/ windows/ linux/`); каталога `web/` нет.

### 4.4 Оба флейвора компилируются (FR-010)

```bash
fvm flutter build macos --debug --dart-define-from-file=config/stage.json
fvm flutter build macos --debug --dart-define-from-file=config/prod.json
```

**Ожидаемо:** обе сборки (`stage`/`prod`) проходят; `app.flavor` доходит до `AppFlavor.getFlavor()` через `--dart-define-from-file`. На десктопе native-идентичность — **prod-only** (`com.cyphernetlabs.noxapp` / `NOX`); stage виден только в Dart. Никакого runtime-ветвления по флейвору. (mise-обёртки: `mise run build:<platform>:<flavor>`.)

---

## 5. Переключение темы (light / dark — SC-005)

**Цель:** app shell оформлен темой из дизайн-токенов NOX, переключается light↔dark по системной настройке; splash-фон всегда тёмный; в коде каркаса нет хардкод-стилей.

```bash
# При запущенном app shell сменить системную тему ОС:
#   macOS:   System Settings → Appearance → Light / Dark
#   iOS:     Settings → Display & Brightness → Light / Dark (или Control Center)
#   Android: Settings → Display → Dark theme
```

**Ожидаемо:**
- App shell мгновенно переключается между light и dark (дефолт `themeMode: ThemeMode.system`; `MaterialApp` читает `state.themeMode` из `AppRootBloc`) — Material 3, seed = teal, цвета только из токенов `nox-handoff`.
- **Splash-фон остаётся тёмным** независимо от темы (brand-fixed исключение, FR-005).
- Проверка отсутствия хардкода (FR-005 / SC-005):
  ```bash
  grep -rnE "Color\(0x|EdgeInsets\.|TextStyle\(|SystemUiOverlayStyle\(" lib/presentation lib/general \
    | grep -vE "\.(freezed|g|config)\.dart"
  ```
  **Ожидаемо:** ноль попаданий вне файлов токенов/темы (`lib/design/theme/`, `lib/design/*_tokens.dart`) — все цвета/отступы/типографика/overlay приходят из токенов (`context.appColors`, `AppSpacingTokens`, `AppTextStyleTokens`, `AppOverlayStyleTokens`).

---

## 6. Проверка структуры (готовность к фичам — SC-004 / US2)

**Цель:** все архитектурные слои, DI, `RepositoryResult`, токены и кодоген уже на месте; старт фичи по шаблону блюпринта не требует реструктуризации каркаса.

### 6.1 Слои-папки одного пакета (US2 сценарий 1 / FR-001)

```bash
ls -d lib/data lib/domain lib/presentation lib/di lib/general lib/design lib/resource
ls pubspec.yaml          # ровно ОДИН манифест
```

**Ожидаемо:** присутствуют все семь слоёв-папок в составе одного пакета `nox_app`; один `pubspec.yaml`; нет path-зависимостей `domain`/`data` (это один пакет). Зависимости однонаправленны: `presentation → domain ← data`, `domain` не импортирует ничего из `data`/`presentation`.

### 6.2 `Item`-harness компилируется и несёт baseline-тесты (FR-013 / SC-004)

```bash
fvm flutter test test/presentation/pages/item_list_page/item_list_bloc_test.dart
fvm flutter test test/data/mapper/item/item_mapper_test.dart
```

**Ожидаемо:** оба зелёные. `Item`-harness — сквозной scaffold-demo на mock-данных (помечен как scaffold-demo, не продуктовая фича, не реальный бэкенд): `ItemListBloc` резолвит `getIt<ItemRepository>()` (impl зарегистрирован `as: ItemRepository` для `[dev, prod, test]`), `PagingState`-в-bloc, страница рендерит три состояния (`AppProgressWidget` / `AppErrorWidget` / `AppEmptyContentWidget`). Это доказывает, что полный вертикальный путь компилируется end-to-end.

### 6.3 Старт фичи не требует реструктуризации (US2 сценарий 2 / SC-004)

**Проверка (без написания фичи):** новый экран добавляется по шаблону блюпринта (`/new-model` → `/new-repository` → `/new-page`, блюпринт `12` §3) внутри существующего дерева — новая папка `lib/presentation/pages/<name>_page/`, регистрация в существующем DI через аннотацию (`@LazySingleton(as: …, env: [dev, prod, test])`), один прогон `build_runner`.

**Ожидаемо:** не требуется менять структуру каркаса, поднимать DI заново или вводить новые инфраструктурные примитивы — `RepositoryResult<T>`, `BaseBloc`, `BaseStatePage`, `LogRepository`, `EntityConverter`, токены и единый `$initGetIt` уже доступны. `RepositoryResult<T>` (data XOR exception) — единый тип результата repo-слоя, доступен даже без реальных репозиториев фич (FR-014).

---

## 7. Desktop-fallback'ы — документированы (SC-007 / FR-012)

**Цель:** для каждой десктоп-специфичной деградации есть явная документированная запись — ноль молчаливых пропусков. На этой итерации это **проза-only** (кода fallback'ов в скелете нет — FR-013); no-op stub вводится с первым desktop-потребителем подсистемы.

**Проверка:** сверить с матрицей десктопных fallback'ов (блюпринт `11` шаг 14):

| Подсистема | Стенс на десктопе | Источник |
|---|---|---|
| Push | disabled / no-op (`firebase_*` mobile-only) | блюпринт `15`, `11` шаг 14 |
| Deep-links | no-op (native `nox://` = FUTURE) | блюпринт `13`, `11` шаг 14 |
| Secure storage | задокументированы бэкенды (macOS Keychain / Windows DPAPI / Linux libsecret), wiring с auth | блюпринт `14`, `11` шаг 14 |
| Flavor-secrets | secrets-decrypt пропущен (без age-ключа); флейвор через `config/<flavor>.json` | блюпринт `09` §0/§4/§7a |

**Ожидаемо:** все четыре деградации зафиксированы прозой; скелет компилируется на десктопе, ни одна из подсистем не ломает сборку (no-op/disabled/placeholder).

---

## Итоговый чеклист приёмки (Phase 1)

- [ ] **SC-003:** `fvm install` + `pub get` + один `build_runner` → окружение поднято без правок структуры.
- [ ] **SC-002 / FR-009:** code-gate зелёный (кодоген один прогон → формат `-l 140` → analyze ноль ошибок → baseline-тесты).
- [ ] **SC-001 / US1:** launch-verify macOS + iOS + Android (app shell без падений: нижняя панель на мобиле, `NavigationRail` на macOS); compile/build-verify Windows + Linux.
- [ ] **SC-006:** ровно пять таргетов, web отсутствует.
- [ ] **FR-010:** оба флейвора (`stage`/`prod`) компилируются; флейвор на десктопе — через `config/<flavor>.json`.
- [ ] **SC-005 / FR-005:** light↔dark по системной настройке; splash тёмный; ноль хардкод-стилей в коде каркаса.
- [ ] **SC-004 / US2:** семь слоёв-папок, один `pubspec.yaml`, `Item`-harness компилируется и зелёный в тестах; старт фичи без реструктуризации.
- [ ] **SC-007 / FR-012:** четыре desktop-fallback'а задокументированы прозой.
