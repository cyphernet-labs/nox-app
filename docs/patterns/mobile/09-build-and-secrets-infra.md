# 09 — Сборка, секреты и CI

> **Назначение:** превратить пустой плейсхолдер `lib/` в воспроизводимо собираемый и публикуемый проект с **нулём секретов в репозитории**. Описывает production-grade инфраструктуру: FVM (пин SDK), mise (пины инструментов + граф задач), SOPS + age (шифрованные секреты), Android Gradle flavors, iOS xcconfig/schemes, тонкий Makefile, релизный поток (CalVer + shifted-epoch) и GitHub Actions CI.
> **Когда читать:** когда вы развернули дерево исходников (см. `11-scaffolding-plan.md`) и нужно сделать его собираемым/тестируемым на машине и в CI; перед первой сборкой stage/prod APK/IPA; при онбординге проекта NOX в CI/CD-политику.
> **Связанные документы:** `01-stack-and-tooling.md` (версии инструментов, `analysis_options.yaml`, `build.yaml`), `02-dependency-injection.md` (`configureDependencies(String env)` + флейворная изоляция), `08-conventions-and-constitution.md` (правило line-length 140, политика форматирования), `12-dev-commands.md` (обёртки `.claude/commands` вокруг этих задач), `11-scaffolding-plan.md` (порядок раскатки файлов).

---

## 0. Ментальная модель

Этот документ описывает **один Dart-пакет** `nox_app` (слои — это папки `lib/data`, `lib/domain`, `lib/presentation`, …; см. `00-architecture-overview.md`). Из этого следуют ключевые правила:

1. **Один `pubspec.yaml`, один прогон `build_runner`.** Нет порядка «data → domain → root»: кодогенерация — это **единственный** прогон `build_runner build` в корне пакета. Кодоген не раскладывается на три каталога — он схлопнут в один шаг.
2. **Flutter пинится через FVM.** Никогда не вызываем голый `flutter`/`dart` — каждый скрипт и каждый CI-шаг использует `fvm flutter` / `fvm dart`, чтобы SDK был идентичен везде. Версия в `.fvmrc` — единственный источник истины.
3. **Сгенерированные файлы не редактируются и не форматируются вручную.** `*.freezed.dart`, `*.config.dart`, `lib/design/gen/**` (а также `*.g.dart` / `*.mocks.dart`, если они появятся) производятся `build_runner` и исключены из форматирования и анализа. Доменные/BLoC-типы по конвенции имеют только `*.freezed.dart` (никаких `*.g.dart` — JSON живёт в entity-слое; см. `03-domain-layer.md`, `04-data-layer.md`).
4. **Компайл-таймовая изоляция флейворов.** Флейвор приходит в Dart через `--dart-define=app.flavor=<flavor>` и читается `AppFlavor.getFlavor()` из `String.fromEnvironment('app.flavor')`; маппинг `prod → Environment.prod`, `stage → Environment.dev` (см. `02-dependency-injection.md`). Секреты приходят через `--dart-define-from-file=...`. На desktop (Windows/Linux/macOS) **нет** нативного `--flavor` (Flutter не поддерживает product flavors для desktop-таргетов): stage/prod выбирается через `--dart-define-from-file=config/<flavor>.json` — закоммиченный, secret-free файл, несущий только `app.flavor`. Резолюция `AppFlavor.getFlavor()` и маппинг `prod → Environment.prod` / `stage → Environment.dev` остаются **идентичны** мобильным.

Поток сборки — одной картинкой:

```
secrets/<flavor>.enc.yaml   (SOPS+age зашифровано, закоммичено)
        │  mise run secrets:decrypt:<flavor>
        ▼
.secrets-runtime/<flavor>.dart-define.json   (gitignored, атомарная запись tmp+mv)
        │  fvm flutter build --dart-define=app.flavor=<flavor>
        │                    --dart-define-from-file=.secrets-runtime/<flavor>.dart-define.json
        ▼
String.fromEnvironment('API_URL') / AppFlavor.getFlavor() / configureDependencies(env)
```

---

## 1. FVM — пин Flutter SDK

`.fvmrc` в корне `lib/`, закоммичен. Единственный источник истины для версии SDK.

```json
{
  "flutter": "3.44.1"
}
```

Соответствующее SDK-ограничение — в единственном `pubspec.yaml`:

```yaml
environment:
  sdk: '>=3.12.0 <4.0.0'
  flutter: 3.44.1
```

Первичная настройка на любой машине или CI-раннере:

```bash
brew install fvm   # либо см. https://fvm.app
fvm install        # читает .fvmrc, ставит Flutter 3.44.1
```

`.fvm/flutter_sdk` (локальный симлинк/кэш) — gitignored; `.fvmrc` — закоммичен. Все скрипты ниже предполагают, что `fvm` есть в `PATH`, и проверяют это.

> **Согласование с FVM.** NOX использует **полноценный FVM CLI** (`fvm install`), потому что у проекта своя сборочная инфраструктура и mise-задачи. `.fvmrc` — единственный источник истины для версии SDK; не подменяйте его вручную созданным симлинком `.fvm/flutter_sdk` в обход CLI.

---

## 2. Концепция секретов

- Одна командная пара ключей **age**. Публичный ключ закоммичен в `.sops.yaml`; приватный распространяется out-of-band (менеджер паролей / 1Password) в `~/.config/sops/age/keys.txt`.
- `mise` пинит версии `sops`/`age` и владеет графом задач decrypt → build.
- `Makefile` — человеко-дружелюбная поверхность; реальная логика живёт в `.mise.toml`.
- Зашифрованные бандлы `secrets/<flavor>.enc.yaml` коммитятся; расшифрованные артефакты (`*.dart-define.json`, нативные `google-services.json` / `GoogleService-Info.plist`, keystores) — **никогда** (см. §10 `.gitignore`).

> **Согласование с бэкендом NOX.** Когда у бэкенда NOX появится свой набор секретов (например, `secrets/{dev,stage,production}.enc.yaml` + задачи `mise run secrets:*`), мобильный проект использует **тот же стек инструментов** (SOPS+age+mise), но со своим набором флейворных файлов `secrets/<flavor>.enc.yaml` и своими decrypt-в-`dart-define`-задачами. Разные схемы потребления (backend → `.env`-файлы; mobile → `dart-define`-JSON + нативные конфиги) не смешивайте — это разные наборы задач.

> **Desktop (Win/Linux/macOS) в скелете не потребляет реальных секретов** → пропускает `secrets:decrypt`, не нуждается в age-ключе. Когда у desktop появятся секреты, на него расширяется та же схема SOPS+age+mise (именование задач — см. §4).

---

## 3. `.sops.yaml`

```yaml
creation_rules:
  - path_regex: ^secrets/.*\.enc\.yaml$
    age: age1examplepublickeyreplaceme0000000000000000000000000000000
```

Каждый `secrets/**/*.enc.yaml` автоматически шифруется на командный публичный age-ключ при `sops edit`. Замените `age1example...` на реальный командный публичный ключ.

---

## 4. `.mise.toml` — пины инструментов + граф задач

Пинит `sops 3.9` / `age 1.2`, указывает путь к приватному age-ключу и владеет всем графом «decrypt → build». Это структурный TOML-файл — ключи на английском.

```toml
[tools]
sops = "3.9"
age  = "1.2"

[env]
SOPS_AGE_KEY_FILE = "{{ env.HOME }}/.config/sops/age/keys.txt"
# Resolve Flutter via the FVM symlink (.fvmrc pins the version).
FLUTTER = "{{ config_root }}/.fvm/flutter_sdk/bin/flutter"

# --- secrets CRUD -----------------------------------------------------------
[tasks."secrets:edit:stage"]
description = "sops-edit the stage secret bundle"
run = "sops edit secrets/stage.enc.yaml"

[tasks."secrets:edit:prod"]
description = "sops-edit the prod secret bundle"
run = "sops edit secrets/prod.enc.yaml"

[tasks."secrets:list"]
description = "Print a tree of encrypted files (never decrypts)"
run = "find secrets -name '*.enc.yaml' -print | sort"

# --- decrypt (atomic tmp-and-rename) ----------------------------------------
[tasks."secrets:decrypt:stage"]
description = "Decrypt stage secrets into .secrets-runtime/stage.dart-define.json (atomic)"
run = """
mkdir -p .secrets-runtime
sops -d --output-type json secrets/stage.enc.yaml \
  | jq '{API_URL, SUPPORT_EMAIL, OBSERVABILITY_DSN}' \
  > .secrets-runtime/stage.dart-define.json.tmp
mv .secrets-runtime/stage.dart-define.json.tmp .secrets-runtime/stage.dart-define.json
# Also materialize native config files atomically where the IDE/build needs them:
#   android/app/src/stage/google-services.json
#   ios/Runner/Firebase/Stage/GoogleService-Info.plist
#   android/stage_keystore.jks  +  android/stage_keystore.properties
"""

[tasks."secrets:decrypt:prod"]
description = "Decrypt prod secrets into .secrets-runtime/prod.dart-define.json (atomic)"
run = """
mkdir -p .secrets-runtime
sops -d --output-type json secrets/prod.enc.yaml \
  | jq '{API_URL, SUPPORT_EMAIL, OBSERVABILITY_DSN}' \
  > .secrets-runtime/prod.dart-define.json.tmp
mv .secrets-runtime/prod.dart-define.json.tmp .secrets-runtime/prod.dart-define.json
# Mirror the native-config materialization for prod (prod keystore + Firebase plist).
"""

[tasks."secrets:clean"]
description = "Wipe decrypted artifacts"
run = "rm -f .secrets-runtime/*.dart-define.json"

# --- build matrix (each depends on the matching decrypt) --------------------
[tasks."build:android:stage"]
description = "Build the stage APK"
depends = ["secrets:decrypt:stage"]
run = """
$FLUTTER clean
$FLUTTER build apk --flavor stage --obfuscate --split-debug-info=build/symbols \
  --dart-define=app.flavor=stage \
  --dart-define-from-file=.secrets-runtime/stage.dart-define.json
"""

[tasks."build:android:prod"]
description = "Build the prod App Bundle (AAB)"
depends = ["secrets:decrypt:prod"]
run = """
$FLUTTER clean
$FLUTTER build appbundle --flavor prod --obfuscate --split-debug-info=build/symbols \
  --dart-define=app.flavor=prod \
  --dart-define-from-file=.secrets-runtime/prod.dart-define.json
"""

[tasks."build:ios:stage"]
description = "Build the stage IPA"
depends = ["secrets:decrypt:stage"]
run = """
$FLUTTER clean
$FLUTTER build ipa --flavor stage --obfuscate --split-debug-info=build/symbols \
  --export-options-plist=ios/ExportOptions-Stage.plist \
  --dart-define=app.flavor=stage \
  --dart-define-from-file=.secrets-runtime/stage.dart-define.json
"""

[tasks."build:ios:prod"]
description = "Build the prod IPA"
depends = ["secrets:decrypt:prod"]
run = """
$FLUTTER clean
$FLUTTER build ipa --flavor prod --obfuscate --split-debug-info=build/symbols \
  --export-options-plist=ios/ExportOptions-Prod.plist \
  --dart-define=app.flavor=prod \
  --dart-define-from-file=.secrets-runtime/prod.dart-define.json
"""

# --- desktop build matrix (no native --flavor; flavor-only config) ----------
# skeleton: no real secrets on desktop — flavor-only config
[tasks."build:macos:stage"]
description = "Build the stage macOS app"
run = "$FLUTTER build macos --dart-define-from-file=config/stage.json"

[tasks."build:macos:prod"]
description = "Build the prod macOS app"
run = "$FLUTTER build macos --dart-define-from-file=config/prod.json"

[tasks."build:windows:stage"]
description = "Build the stage Windows app"
run = "$FLUTTER build windows --dart-define-from-file=config/stage.json"

[tasks."build:windows:prod"]
description = "Build the prod Windows app"
run = "$FLUTTER build windows --dart-define-from-file=config/prod.json"

[tasks."build:linux:stage"]
description = "Build the stage Linux app"
run = "$FLUTTER build linux --dart-define-from-file=config/stage.json"

[tasks."build:linux:prod"]
description = "Build the prod Linux app"
run = "$FLUTTER build linux --dart-define-from-file=config/prod.json"
```

Инварианты, которые нужно сохранить:

- **Decrypt-задачи атомарны** — пишут в `.tmp`, затем `mv`. Это защищает от частично записанного `dart-define.json`, если процесс упадёт посередине.
- Decrypt пишет **и** `dart-define.json`, **и** нативные конфиги туда, где их ждёт IDE/Gradle/Xcode для one-click переключения флейворов.
- Сборки резолвят Flutter через симлинк FVM (`$FLUTTER`), передают `--dart-define=app.flavor=<flavor>` + `--dart-define-from-file=...`, и сначала делают `flutter clean`.
- `--obfuscate --split-debug-info=build/symbols` включён для релизных сборок (символы для дешифровки стек-трейсов в observability-бэкенде — см. `OBSERVABILITY_DSN` в env-наборе; конкретный observability-вендор не зафиксирован, DSN env-gated в `prod`/`stage`).
- `jq '{ ... }'` явно перечисляет только те ключи, которые должны попасть в `dart-define` — это allowlist, а не «весь YAML». Набор ключей (`API_URL`, `SUPPORT_EMAIL`, `OBSERVABILITY_DSN`) — **пример** (бэкенд/протокол NOX ещё не выбран; замените на реальный контракт). Добавляя новую переменную в `dart-define`, расширьте этот список **в обоих** флейворах.

> **Расширение матрицы задач (на будущее).** Та же mise-схема (`secrets:decrypt:<flavor>` + `build:<platform>:<channel>` + `depends = ["secrets:decrypt:<flavor>"]`, тот же путь `SOPS_AGE_KEY_FILE = ~/.config/sops/age/keys.txt`, атомарный tmp+mv) может разворачиваться шире по двум осям: (1) **prod разбит по назначению дистрибуции** — например `build:android:prod:firebase` (Firebase App Distribution) / `build:android:prod:google` (Google Play AAB) и `build:ios:prod:firebase` / `build:ios:prod:apple` (TestFlight); этот firebase/google/apple-сплит — нейтральный пример, конкретные каналы дистрибуции выбираются позже; (2) `secrets:decrypt:<flavor>` может материализовать **оба** flavor-JSON сразу (cross-flavor invariant — переключение флейвора в IDE никогда не упирается в отсутствующий `--dart-define-from-file`). Здесь оставлен базовый 4-entrypoint вариант (`build:<platform>:{stage,prod}`), потому что мобильный CD отложен (§11); при активации дистрибуции расширьте матрицу по схеме именования задач `namespace:action:channel` (для сборок — `build:<platform>:<channel>[:destination]`), `depends` на decrypt — те же. Дополнительно при онбординге дистрибуции добавьте `secrets:edit-binary` (редактирование зашифрованных keystore/plist по label-аргументу), `release:prepare` и `install:hooks`.

---

## 5. `Makefile` — тонкая обёртка

`Makefile` — человеко-дружелюбная поверхность над dev-workflow и mise-задачами. Реальная логика секретов/сборок живёт в `.mise.toml`; dev-команды делегируют в `fvm`.

```makefile
.DEFAULT_GOAL := help

help: ## Show all targets
	@awk 'BEGIN {FS=":.*?## "} /^[a-zA-Z0-9_.-]+:.*?## / {printf "  \033[36m%-28s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# --- Dev workflow -----------------------------------------------------------
generate: ## Regenerate code (freezed, injectable, assets) — SINGLE build_runner run
	fvm dart pub get && fvm dart run build_runner build --delete-conflicting-outputs

analyze: ## flutter analyze
	fvm flutter analyze

test: ## Run all tests, or one via `make test FILE=<path>`
	fvm flutter test $(FILE)

format: ## Format the whole tree at 140 cols — CI GATE ONLY, never as a task-completion step
	fvm dart format --line-length 140 --set-exit-if-changed .

# --- Builds — delegate to mise (logic lives in .mise.toml) -------------------
build-android-stage: ## Stage APK
	mise run build:android:stage
build-android-prod: ## Prod AAB
	mise run build:android:prod
build-ios-stage: ## Stage IPA
	mise run build:ios:stage
build-ios-prod: ## Prod IPA
	mise run build:ios:prod

# --- Secrets ----------------------------------------------------------------
secrets-list: ## Tree of encrypted files (never decrypts)
	mise run secrets:list
secrets-edit-stage: ## sops-edit stage bundle
	mise run secrets:edit:stage
secrets-edit-prod: ## sops-edit prod bundle
	mise run secrets:edit:prod
secrets-decrypt-stage: ## Decrypt stage into the working tree
	mise run secrets:decrypt:stage
secrets-decrypt-prod: ## Decrypt prod into the working tree
	mise run secrets:decrypt:prod
secrets-clean: ## Wipe decrypted artifacts
	mise run secrets:clean
```

> **Важно — `make format` это CI-гейт, а не шаг завершения задачи.** Целевой `format` форматирует всё дерево с `--set-exit-if-changed` и предназначен **только** для проверки в CI. По репозиторному правилу форматирования (`08-conventions-and-constitution.md`) после правок форматируйте **только изменённые в текущей задаче файлы**: `fvm dart format -l 140 <явные пути>`. Никогда не запускайте `make format` как финальный шаг рабочей задачи — он зашумит diff (включая регенерированные `*.freezed.dart` / `*.config.dart`).

---

## 6. Android Gradle — флейворы, подпись, pre-build хук секретов

`android/app/build.gradle.kts` — несущие блоки. Конвенции проекта: `compileSdk 36`, `minSdk 26`, Java 17, `applicationId` по флейвору (`com.cyphernetlabs.noxapp` для prod, `com.cyphernetlabs.noxapp.stage` для stage).

```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    // id("com.google.gms.google-services")  // only if/when Firebase is wired
}

android {
    namespace = "com.cyphernetlabs.noxapp"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // applicationId is set per-flavor below; this is the package base.
        minSdk = 26
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    flavorDimensions += "app"
    productFlavors {
        create("stage") {
            dimension = "app"
            applicationId = "com.cyphernetlabs.noxapp.stage"
            resValue("string", "app_name", "NOX Stage")
        }
        create("prod") {
            dimension = "app"
            applicationId = "com.cyphernetlabs.noxapp"
            resValue("string", "app_name", "NOX")
        }
    }

    signingConfigs {
        create("flavorSigning") {
            if (activeKeystoreProperties.containsKey("storeFile")) {
                storeFile = file(activeKeystoreProperties["storeFile"] as String)
                storePassword = activeKeystoreProperties["storePassword"] as String
                keyAlias = activeKeystoreProperties["keyAlias"] as String
                keyPassword = activeKeystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        val flavorSigning = signingConfigs.getByName("flavorSigning")
        listOf(getByName("debug"), getByName("release")).forEach { buildType ->
            buildType.isMinifyEnabled = true
            buildType.proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            buildType.signingConfig = flavorSigning
        }
    }
}
```

Два поддерживающих механизма в этом же файле:

### 6.1 Детект активного флейвора (до того как `android {}` вычислится)

Парсим запрошенный флейвор из `gradle.startParameter.taskRequests` (регекс `(Stage|Prod)`), по умолчанию `stage`, и выбираем соответствующий keystore `.properties` для signing config.

```kotlin
// Determine the active flavor from the Gradle task graph (e.g. assembleProdRelease).
val activeFlavor: String = run {
    val taskNames = gradle.startParameter.taskRequests
        .flatMap { it.args }
        .joinToString(" ")
    Regex("(Stage|Prod)").find(taskNames)?.value?.lowercase() ?: "stage"
}

// Select the matching keystore .properties for the signing config.
val activeKeystoreProperties = java.util.Properties().apply {
    val propsFile = rootProject.file("${activeFlavor}_keystore.properties")
    if (propsFile.exists()) {
        propsFile.inputStream().use { load(it) }
    }
}
```

### 6.2 Pre-build хук расшифровки секретов

В `afterEvaluate` регистрируем `Exec`-задачу на флейвор, которая вызывает mise-decrypt, и привязываем её как зависимость `pre<Flavor><BuildType>Build` — так секреты (keystore + Firebase-конфиг) присутствуют до того, как запустится Flutter-сборка.

```kotlin
afterEvaluate {
    listOf("Stage", "Prod").forEach { flavorCap ->
        val flavor = flavorCap.lowercase()
        val decryptTask = tasks.register<Exec>("decryptSecrets$flavorCap") {
            workingDir = rootProject.projectDir.parentFile  // lib/
            commandLine("mise", "run", "secrets:decrypt:$flavor")
        }
        listOf("Debug", "Release").forEach { buildType ->
            tasks.matching { it.name == "pre$flavorCap${buildType}Build" }
                .configureEach { dependsOn(decryptTask) }
        }
    }
}
```

> **`--dart-define` не потребляется Gradle.** Флейвор + конфиг достигают Dart на этапе `flutter build`. Gradle обрабатывает только выбор keystore + хук расшифровки. Не пытайтесь читать `dart-define`-переменные в Gradle.

---

## 7. iOS — xcconfig, schemes, fastlane

- **Per-flavor xcconfig.** `ios/Flutter/Stage.xcconfig` и `ios/Flutter/Prod.xcconfig` задают `PRODUCT_BUNDLE_IDENTIFIER` (`com.cyphernetlabs.noxapp.stage` / `com.cyphernetlabs.noxapp`), `DISPLAY_NAME` (`NOX Stage` / `NOX`) и любые нативные значения (например, OAuth reverse-client-id), которые нужны нативной части iOS — через xcconfig-подстановку, а не копированием plist.

  ```
  // ios/Flutter/Stage.xcconfig
  #include "Generated.xcconfig"
  PRODUCT_BUNDLE_IDENTIFIER = com.cyphernetlabs.noxapp.stage
  DISPLAY_NAME = NOX Stage

  // ios/Flutter/Prod.xcconfig
  #include "Generated.xcconfig"
  PRODUCT_BUNDLE_IDENTIFIER = com.cyphernetlabs.noxapp
  DISPLAY_NAME = NOX
  ```

- **Per-flavor schemes.** Создайте схемы `stage` и `prod` в Xcode (Product → Scheme → Manage Schemes), каждая указывает на свою конфигурацию build settings, привязанную к соответствующему xcconfig. `flutter build ipa --flavor stage` подбирает схему `stage`.
- **Firebase plist по флейвору.** Если/когда подключается Firebase: `secrets:decrypt:<flavor>` материализует `ios/Runner/Firebase/Stage/GoogleService-Info.plist` (и Prod), а Run Script Build Phase копирует нужный по активной схеме.
- **Распространение через fastlane.** Лейны (TestFlight / Firebase App Distribution) вызываются из mise-задач `build:ios:*` с `--export-options-plist=...`. Fastlane — заметка-заглушка на будущее: когда появится Apple Developer аккаунт (см. `docs/predeploy/external-services-setup.md`), добавьте `ios/fastlane/Fastfile` с лейнами `stage` (App Distribution) и `prod` (TestFlight/App Store), вызываемыми после соответствующего `build:ios:*`.

---

## 7a. Идентичность desktop (macOS / Windows / Linux)

В этой итерации desktop-таргеты несут **только prod-идентичность** на нативном уровне (одна нативная конфигурация на платформу). Отдельная нативная `.stage`-идентичность (и, соответственно, упаковка двух раздельных артефактов) — **на будущее** (§11a). Stage на desktop виден исключительно через `app.flavor` в Dart (`--dart-define-from-file=config/stage.json`), нативная конфигурация при этом не меняется.

- **macOS.** В `macos/Runner/Configs/AppInfo.xcconfig` (и Xcode build settings) prod-идентичность: `PRODUCT_BUNDLE_IDENTIFIER = com.cyphernetlabs.noxapp` + `PRODUCT_NAME = NOX`. Отдельная `.stage`-идентичность (`com.cyphernetlabs.noxapp.stage`) → упаковка **на будущее** (§11a).
- **Windows.** В `windows/runner/CMakeLists.txt` — `BINARY_NAME = NOX`; в `windows/runner/Runner.rc` блок `VERSIONINFO` несёт `CompanyName = "Cyphernet Labs"` и `ProductName = "NOX"`, плюс зафиксированный закоммиченный GUID приложения (стабильный между сборками). Отдельная `.stage`-идентичность → упаковка **на будущее** (§11a).
- **Linux.** В `linux/CMakeLists.txt` — `APPLICATION_ID = com.cyphernetlabs.noxapp`; имя бинарника и `Name` в `.desktop`-файле — `NOX`. Отдельная `.stage`-идентичность → упаковка **на будущее** (§11a).

---

## 8. CI — GitHub Actions

Два workflow. Первый (`ci.yml`) — гейт: format-check → **один** прогон кодогена → analyze → test. Второй (`compile-check.yml`) — per-platform debug smoke-сборки. Оба пинят Flutter `3.44.1` через `subosito/flutter-action`.

> **Один пакет — один прогон.** Пакет один, поэтому `pub get`, кодоген и тесты — **единственный** прогон каждого шага. Не раскладывайте их на три каталога (`data → domain → root`) и не воспроизводите трёх-этапный порядок.

### 8.1 `.github/workflows/ci.yml` — analyze & test

**Триггеры:** push и pull_request в `develop` и `main`.
**Порядок шагов:** checkout → install Flutter → cache pub → `pub get` → `build_runner` (один прогон) → format-check (140) → `analyze` → `test`.

```yaml
name: NOX CI

on:
  push:
    branches: [develop, main]
    paths:
      - "lib/**"
  pull_request:
    branches: [develop, main]
    paths:
      - "lib/**"

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

defaults:
  run:
    working-directory: lib

jobs:
  analyze-and-test:
    runs-on: ubuntu-latest
    timeout-minutes: 25
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install Flutter 3.44.1
        uses: subosito/flutter-action@v2
        with:
          flutter-version: 3.44.1
          channel: stable
          cache: true

      - name: Cache pub-cache
        uses: actions/cache@v4
        with:
          path: ~/.pub-cache
          key: pub-cache-${{ runner.os }}-${{ hashFiles('lib/pubspec.lock') }}

      - name: Install dependencies
        run: flutter pub get

      - name: Regenerate codegen (single build_runner run)
        run: dart run build_runner build --delete-conflicting-outputs

      - name: Verify formatting (line length 140)
        run: |
          find lib test \
            -type f -name "*.dart" \
            ! -name "*.freezed.dart" \
            ! -name "*.g.dart" \
            ! -name "*.config.dart" \
            ! -name "*.mocks.dart" \
            ! -path "lib/design/gen/*" \
            -print0 | xargs -0 dart format --output=none --set-exit-if-changed --line-length=140

      - name: Static analysis
        run: flutter analyze

      - name: Run tests
        run: flutter test
```

Замечания:
- CI использует `subosito/flutter-action` напрямую (не FVM), но **версия совпадает с `.fvmrc`** (`3.44.1`), поэтому поведение идентично.
- Format-check валит сборку, если хоть один in-scope файл не отформатирован на 140; правьте локально через `fvm dart format -l 140 <пути>` (изменённые файлы) или `make format` (всё дерево — только для воспроизведения CI-гейта).
- Кодоген — **один** `dart run build_runner build --delete-conflicting-outputs` (не data→domain→root; пакет один). `--delete-conflicting-outputs` удаляет устаревшие сгенерированные файлы вместо ошибки при перезаписи.
- `paths:` фильтр ограничивает workflow изменениями под `lib/**` — это удобно для пер-проектного детекта изменений, если NOX когда-либо встроят в более широкую CI-политику (см. ниже §11).

### 8.2 `.github/workflows/compile-check.yml` — per-platform debug smoke-сборки

**Триггеры:** push в `develop`/`main` (с `paths`-фильтром) и ручной `workflow_dispatch`. Пять параллельных джобов собирают приложение в debug под Android, iOS, macOS, Windows и Linux, чтобы поймать слом компиляции на каждой платформе (Windows/Linux — compile-only, launch отложен).

```yaml
name: NOX Compile check

on:
  push:
    branches: [develop, main]
    paths:
      - "lib/**"
  workflow_dispatch:

defaults:
  run:
    working-directory: lib

jobs:
  compile-android:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: 3.44.1
          channel: stable
          cache: true
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      # Debug smoke build (stage flavor) — no secrets required for --debug compile check.
      - run: flutter build apk --debug --flavor stage --dart-define=app.flavor=stage

  compile-ios:
    runs-on: macos-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: 3.44.1
          channel: stable
          cache: true
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      # iOS debug compile check without code signing.
      - run: flutter build ios --debug --no-codesign --flavor stage --dart-define=app.flavor=stage

  compile-macos:
    runs-on: macos-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: 3.44.1
          channel: stable
          cache: true
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      # macOS debug compile check — no secrets, no native --flavor.
      - run: flutter build macos --debug

  compile-windows:
    runs-on: windows-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: 3.44.1
          channel: stable
          cache: true
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      # Windows debug compile check — no secrets, no native --flavor.
      - run: flutter build windows --debug

  compile-linux:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: 3.44.1
          channel: stable
          cache: true
      # GTK toolchain + deps required by the Flutter Linux desktop embedder.
      - run: sudo apt-get update && sudo apt-get install -y ninja-build libgtk-3-dev
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      # Linux debug compile check — no secrets, no native --flavor.
      - run: flutter build linux --debug
```

Замечания:
- Smoke-сборки запускаются в `--debug` и **не требуют секретов** — мы не вызываем decrypt и не используем `--dart-define-from-file`. Это компайл-чек, а не релиз. Для Android stage достаточно `--dart-define=app.flavor=stage`; для iOS — `--no-codesign`. Desktop-джобы (macOS/Windows/Linux) тоже **без секретов** — у них нет нативного `--flavor`, а `--debug` компайл-чек не требует ни decrypt, ни age-ключа.
- Этот compile-check покрывает все 5 целевых платформ (конституция v1.1.0): Android + iOS + macOS + Windows + Linux. Desktop compile-smoke **добавлен**; упаковка/подпись (packaging/signing) — **на будущее** (§11a). Rust/FFI-шагов нет.

**Platform support matrix (minimum OS).** Минимальные версии берутся из дефолтов `flutter create` под Flutter `3.44.1` (источник floor — `flutter create`-дефолты под `3.44.1`). Пиннинг конкретных таргетов и подбор Linux apt-deps — **на будущее**.

| Platform | Minimum OS |
|---|---|
| Windows | Windows 10 (Flutter 3.44 floor) |
| macOS | macOS 10.15+ (`flutter create` default) |
| Linux | GTK3 runtime |

### 8.3 Локальное зеркало CI

Прогоните ту же последовательность локально перед пушем, чтобы поймать падения CI заранее:

```bash
make generate     # 1. pub get + single build_runner run
make format       # 2. format-check at 140 (CI gate; правит всё дерево)
make analyze      # 3. flutter analyze
make test         # 4. flutter test
```

Это зеркалит `ci.yml` шаг-в-шаг. Обёртка `.claude/commands/check-build` (см. `12-dev-commands.md`) оборачивает шаги 1–3.

---

## 9. Релизный поток — CalVer + shifted-epoch

Версия в `pubspec.yaml::version` — **закоммиченное** значение в формате CalVer + сдвинутый epoch, выровненное с авторитетной политикой репозитория `docs/operations/versioning-strategy.md`.

```
version: YY.M.D+SHIFTED_EPOCH
```

- `YY` — две последние цифры года; `M` — месяц без ведущего нуля; `D` — день без ведущего нуля (CalVer, как в `docs/operations/versioning-strategy.md` §1; пример: `26.6.7`).
- `SHIFTED_EPOCH` — build number: `UNIX_TIMESTAMP - 1577836800`, где `1577836800` = `2020-01-01 00:00:00 UTC` (`BUILD_EPOCH_BASE`). Сдвиг даёт ~60 лет запаса под потолок `versionCode` Play Store (2.1B) — headroom до ~2086.

```bash
# Compute the shifted-epoch build number (matches docs/operations/versioning-strategy.md §2).
BUILD_NUMBER=$(( $(date -u +%s) - 1577836800 ))
echo "version: $(date -u +%y.%-m.%-d)+${BUILD_NUMBER}"
# e.g. -> version: 26.6.7+202979472
```

> **Канонический формат — `YY.M.D`.** Месяц/день без ведущего нуля (не `YY.MM.DD`), см. `docs/operations/versioning-strategy.md` §1. Авторитетная политика версионирования репозитория — единый источник истины; следуйте ей.

**Каналы не меняют строку версии.** Никаких суффиксов `-rc.N` / `-dev.N` / `-stage.N` в `version`. Stage и prod собирают один и тот же артефакт; различие — это git-тэг + флейвор, а не версия. Имя артефакта (см. `versioning-strategy.md` §9): `nox_app_<version>_<build>.<ext>` — например `nox_app_26.5.10_200429805.apk` / `.aab` / `.ipa`.

**Git-тэги** (канонический формат `<project>-v<version>` + суффикс канала для мобильного проекта): `nox_app-v26.6.7+202979472-stage` / `nox_app-v26.6.7+202979472-prod`. Гейт: если тэг указывает на коммит, где `pubspec.yaml::version` ≠ версии в тэге — build обязан фейлиться (`versioning-strategy.md` §6).

**Релизные entrypoints** (тонкие обёртки, композят mise-задачи):
- `make release-prepare` — вычисляет `YY.M.D+SHIFTED_EPOCH`, записывает в `pubspec.yaml::version`, коммитит, тэгает, пушит (ветка-aware). Канал-suffix тэга задаётся аргументом.
- `make release-stage` / `release-prod` — tag-driven: выбирают тэг, собирают на нём через `build:*` mise-задачи, восстанавливают HEAD на выходе.

> **Версия — всегда закоммиченное значение.** CI может писать `pubspec.yaml::version`, но **только** через коммит — никогда runtime-инъекцией вида `flutter build --build-number=$GITHUB_RUN_NUMBER` (`versioning-strategy.md` §1). API-версионирование (например `/api/v1/` — пример, бэкенд/протокол NOX ещё не выбран; заменить на реальный контракт) — отдельная ось от версии артефакта.

---

## 10. `.gitignore` — дополнения

```gitignore
# FVM local SDK symlink/cache (.fvmrc stays committed)
.fvm/flutter_sdk

# Decrypted secret artifacts (regenerated by secrets:decrypt)
.secrets-runtime/

# Decrypted native config (materialized by secrets:decrypt)
android/app/src/stage/google-services.json
android/app/src/prod/google-services.json
ios/Runner/Firebase/**/GoogleService-Info.plist
android/*_keystore.jks
android/*_keystore.properties
```

> Никогда не коммитьте `.secrets-runtime/`, расшифрованные `google-services.json` / `GoogleService-Info.plist` или keystores. Они материализуются `secrets:decrypt:<flavor>` из зашифрованного источника истины и должны быть восстановимы в любой момент.

---

## 11. Интеграция в CI/CD

Проект NOX может онбордиться в более широкую GitHub Actions / CI-CD-политику (см. `docs/operations/ci_cd_strategy.md` §8.3 — пер-проектный чек-лист активации). Ключевые точки сопряжения:

- **Детект изменений.** Корневой `ci.yml` использует `dorny/paths-filter@v3` для пер-проектных условных джобов; агрегатный `CI summary` — единственная required-проверка для branch protection. Workflow выше (`NOX CI`) фильтрует по `paths: lib/**` — это согласуется с детект-паттерном (но **не** переносите фильтр в `on.push.paths` корневого детектора).
- **One-dispatch релизная модель.** Релизы запускаются единственным `workflow_dispatch` (`release-stage.yml` / `release-production.yml`), которые делают bump → PR → auto-merge → tag → CD. Тэг — единственный CD-триггер. NOX CD (`nox_app-cd-{stage,prod}.yml`) пока **отложен** до появления Apple Developer / Google Play аккаунтов (`docs/predeploy/external-services-setup.md`); мобильный feature-branch flow с `branch_slug` в суффиксе тэга описан в `ci_cd_strategy.md` §13 и реактивируется при активации проекта.
- **Аутентификация.** Релизные workflow используют fine-grained PAT (`BUMP_PAT`), а не `GITHUB_TOKEN` — последний не триггерит downstream-workflow на push тэга.
- **Секреты CI.** Расшифровка секретов в CI требует `SOPS_AGE_KEY_CI`; приватный age-ключ команды кладётся в секреты репо через `./scripts/ci_cd/setup-github-secrets.sh`. Для smoke-сборок (`--debug`) ключ не нужен — они не расшифровывают секреты. Desktop (Win/Linux/macOS) в скелете не потребляет реальных секретов → пропускает `secrets:decrypt`, не нуждается в age-ключе; когда у desktop появятся секреты, на него расширяется та же схема SOPS+age+mise (именование задач — см. §4).
- **Никаких автономных merge/deploy/commit.** Открывайте PR и пушьте в feature-ветку, но **не** мёрджите PR, **не** деплойте в cloud и **не** коммитьте без явного запроса владельца в текущей сессии.

---

## 11a. Упаковка и подпись desktop (на будущее)

`TODO(blueprint-desktop-packaging)` — **без реализации** в этой итерации; скелет даёт только `--debug` compile-smoke (§8.2) и `build:<desktop>:<flavor>` без упаковки (§4). Когда desktop-дистрибуция активируется, по платформам:

- **Windows.** MSIX-пакет + подпись инсталлятора code-signing-сертификатом (EV/OV).
- **macOS.** DMG + `codesign` + нотаризация через `xcrun notarytool` + hardened runtime.
- **Linux.** AppImage и/или `.deb`.

Блокер тот же, что у мобильного CD (§11): нет аккаунтов/сертификатов для подписи (Apple Developer / code-signing cert) — пока они не заведены (`docs/predeploy/external-services-setup.md`), упаковка и подпись desktop остаются на будущее, параллельно отложенному мобильному CD.

> `TODO(blueprint-desktop-window)` — скелет поставляет **дефолтное окно** Flutter desktop-раннера (single-window, без `window_manager`, нативный chrome/title bar). Полировка **на будущее**: `window_manager` для задания начального размера `1440x900` (канонический размер из корпуса) + `minimumSize 640x600` + кастомный unified title bar.

---

## Чеклист

- [ ] `.fvmrc` коммитит `flutter: 3.44.1`; `fvm install` проходит.
- [ ] `pubspec.yaml` объявляет `sdk: '>=3.12.0 <4.0.0'` и `flutter: 3.44.1`.
- [ ] `.mise.toml` пинит `sops 3.9` / `age 1.2` + граф decrypt→build; `SOPS_AGE_KEY_FILE` указывает на приватный ключ; `FLUTTER` резолвится через `.fvm/flutter_sdk`.
- [ ] `.sops.yaml` содержит creation rule + командный публичный age-ключ.
- [ ] `secrets/stage.enc.yaml` и `secrets/prod.enc.yaml` зашифрованы (закоммичены).
- [ ] Decrypt-задачи атомарны (`.tmp` + `mv`) и пишут `dart-define.json` + нативные конфиги.
- [ ] `Makefile` оборачивает mise-задачи + dev-workflow; `generate` — один прогон `build_runner`; `format` помечен как CI-гейт.
- [ ] Gradle: dimension `app` (`stage`/`prod`), per-flavor `applicationId` (`com.cyphernetlabs.noxapp[.stage]`), детект активного флейвора, выбор keystore, decrypt-хук на `pre<Flavor><BuildType>Build`; `compileSdk 36`, `minSdk 26`, Java 17.
- [ ] iOS: `Stage.xcconfig` / `Prod.xcconfig` + схемы `stage`/`prod`; заметка про fastlane на будущее.
- [ ] `.github/workflows/ci.yml`: format-check → один кодоген → analyze → test; `subosito/flutter-action` `3.44.1`; `paths: lib/**`.
- [ ] `.github/workflows/compile-check.yml`: debug smoke-сборки Android + iOS (без секретов, iOS `--no-codesign`) — desktop-таргеты в строке ниже.
- [ ] compile-check покрывает все 5 таргетов (debug compile-only): `compile-macos`/`compile-windows`/`compile-linux` (`--debug`, без секретов; Linux ставит `ninja-build libgtk-3-dev`).
- [ ] Desktop-сборки получают флейвор только через `config/<flavor>.json` (без secrets-decrypt / без age-ключа).
- [ ] Упаковка/подпись desktop задокументированы как «на будущее» (§11a).
- [ ] `version` в `pubspec.yaml` — закоммиченный `YY.M.D+SHIFTED_EPOCH` (epoch base `1577836800`), выровнен с `docs/operations/versioning-strategy.md`.
- [ ] `.gitignore` исключает `.secrets-runtime/`, `.fvm/flutter_sdk`, расшифрованные нативные конфиги и keystores.
- [ ] Проект онборжен в CI/CD-политику (`ci_cd_strategy.md` §8.3); CD отложен до Apple/Play аккаунтов.
- [ ] Локальное зеркало CI (`make generate && make format && make analyze && make test`) проходит до пуша.
