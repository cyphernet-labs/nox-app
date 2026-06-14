# 09 — Сборка, секреты и CI

> **Назначение:** превратить скелет `nox_app` в воспроизводимо собираемый и публикуемый проект с **нулём секретов в репозитории**. Описывает production-grade инфраструктуру: FVM (пин SDK), mise (пины инструментов + граф задач), SOPS + age (шифрованные секреты), Android Gradle flavors, iOS xcconfig/schemes, нативную идентичность desktop, тонкий Makefile, релизный поток (CalVer + shifted-epoch) и GitHub Actions CI. NOX — **отдельный standalone-репозиторий**: своя SOPS+age-схема, свой `.mise.toml`, свои `ci.yml` + `compile-check.yml` (никакого монорепо/корневого экспортёра/reusable-workflow).
> **Когда читать:** когда вы развернули дерево исходников (см. `11-scaffolding-plan.md`) и нужно сделать его собираемым/тестируемым на машине и в CI; перед первой сборкой stage/prod артефакта; при онбординге проекта NOX в более широкую CI/CD-политику.
> **Связанные документы:** `01-stack-and-tooling.md` (версии инструментов, `analysis_options.yaml`, `build.yaml`), `02-dependency-injection.md` (`configureDependencies(String env)` + флейворная изоляция), `08-conventions-and-constitution.md` (правило line-length 140, политика форматирования), `12-dev-commands.md` (обёртки `.claude/commands` / `Makefile`-цели вокруг этих задач), `11-scaffolding-plan.md` (порядок раскатки файлов).

---

## 0. Ментальная модель

Этот документ описывает **один Dart-пакет** `nox_app` (слои — это папки `lib/data`, `lib/domain`, `lib/presentation`, `lib/di`, `lib/general`, `lib/design`, `lib/resource`; см. `00-architecture-overview.md`). Из этого следуют ключевые правила:

1. **Один `pubspec.yaml`, один прогон `build_runner`.** Нет порядка «data → domain → root»: кодогенерация — это **единственный** прогон `build_runner build` в корне пакета. Кодоген не раскладывается на три каталога — он схлопнут в один шаг.
2. **Flutter пинится через FVM (локально) / `.fvmrc` (в CI).** Локально и в скриптах/Makefile никогда не вызываем голый `flutter`/`dart` — только `fvm flutter` / `fvm dart`. В CI SDK провижит `subosito/flutter-action` по версии `3.44.1` (совпадает с `.fvmrc`) и далее вызывает `flutter`/`dart` **напрямую** (без `fvm`). Версия в `.fvmrc` — единственный источник истины везде, поэтому поведение идентично.
3. **Сгенерированные файлы не редактируются и не форматируются вручную.** `*.freezed.dart`, `*.config.dart`, `lib/design/gen/**` (а также `*.g.dart` / `*.mocks.dart`, если они появятся) производятся `build_runner` и исключены из форматирования и анализа (они gitignored, см. §10). Доменные/BLoC-типы по конвенции имеют только `*.freezed.dart` (никаких `*.g.dart` — JSON живёт в entity-слое; см. `03-domain-layer.md`, `04-data-layer.md`).
4. **Компайл-таймовая изоляция флейворов.** Флейвор приходит в Dart через `--dart-define=app.flavor=<flavor>` (или, как в скелете, через `--dart-define-from-file=config/<flavor>.json`) и читается `AppFlavor.getFlavor()` из `String.fromEnvironment('app.flavor')`; пустое/неизвестное значение → **`prod`** (безопасный дефолт). Маппинг `prod → Environment.prod`, `stage → Environment.dev` (см. `02-dependency-injection.md`, `lib/main.dart`). Секреты (когда появятся) приходят через `--dart-define-from-file=...`. На desktop (Windows/Linux/macOS) **нет** нативного `--flavor` (Flutter не поддерживает product flavors для desktop-таргетов): stage/prod выбирается через `--dart-define-from-file=config/<flavor>.json` — закоммиченный, secret-free файл, несущий только `app.flavor`. В текущем скелете этот же `config/<flavor>.json`-механизм используется **единообразно на всех пяти платформах** (нативные mobile-флейворы ещё не заведены, см. §6/§7).

Поток сборки — одной картинкой (целевая форма с секретами):

```
secrets/<flavor>.enc.yaml   (SOPS+age encrypted, committed)
        │  mise run secrets:decrypt:<flavor>
        ▼
.secrets-runtime/<flavor>.dart-define.json   (gitignored, atomic tmp+mv write)
        │  fvm flutter build --dart-define=app.flavor=<flavor>
        │                    --dart-define-from-file=.secrets-runtime/<flavor>.dart-define.json
        ▼
String.fromEnvironment('API_URL') / AppFlavor.getFlavor() / configureDependencies(env)
```

> **Состояние скелета (Feature-001).** Поток выше — **целевая** форма. На сегодня в репозитории **нет** ни `secrets/`-бандлов, ни `secrets:decrypt`-задач, ни age-ключа: флейвор инжектится только закоммиченным `config/<flavor>.json` (`{"app.flavor": "stage|prod"}`), а сборки идут в `--debug` на всех пяти платформах (см. §4, §8). SOPS+age-конвейер ниже описан как конвенция, которая включается с первой реальной потребностью в секретах (бэкенд/протокол NOX ещё не выбран).

---

## 1. FVM — пин Flutter SDK

`.fvmrc` в корне репозитория, закоммичен. Единственный источник истины для версии SDK.

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
brew install fvm   # or see https://fvm.app
fvm install        # reads .fvmrc, installs Flutter 3.44.1
```

`.fvm/flutter_sdk` (локальный симлинк/кэш) — gitignored; `.fvmrc` — закоммичен. Все скрипты ниже предполагают, что `fvm` есть в `PATH`, и проверяют это.

> **Согласование с FVM.** NOX использует **полноценный FVM CLI** (`fvm install`), потому что у проекта своя сборочная инфраструктура и mise-задачи. `.fvmrc` — единственный источник истины для версии SDK; не подменяйте его вручную созданным симлинком `.fvm/flutter_sdk` в обход CLI.

---

## 2. Концепция секретов

- Одна командная пара ключей **age**. Публичный ключ закоммичен в `.sops.yaml`; приватный распространяется out-of-band (менеджер паролей / 1Password) в `~/.config/sops/age/keys.txt`.
- `mise` пинит версии `sops`/`age` и владеет графом задач decrypt → build.
- `Makefile` — человеко-дружелюбная поверхность; реальная логика живёт в `.mise.toml`.
- Зашифрованные бандлы `secrets/<flavor>.enc.yaml` коммитятся; расшифрованные артефакты (`*.dart-define.json`, нативные `google-services.json` / `GoogleService-Info.plist`, keystores) — **никогда** (см. §10 `.gitignore`).

> **Согласование с бэкендом NOX.** Когда у бэкенда NOX появится свой набор секретов (например, `secrets/{dev,stage,production}.enc.yaml` + задачи `mise run secrets:*`), мобильный/клиентский проект использует **тот же стек инструментов** (SOPS+age+mise), но со своим набором флейворных файлов `secrets/<flavor>.enc.yaml` и своими decrypt-в-`dart-define`-задачами. Разные схемы потребления (backend → `.env`-файлы; клиент → `dart-define`-JSON + нативные конфиги) не смешивайте — это разные наборы задач. **NOX — отдельный standalone-репозиторий: своя age-пара, свой `.sops.yaml`, свой `.mise.toml`** (никакого корневого монорепо-экспортёра / consumer-таргета).

> **Состояние скелета.** Сегодня `secrets/`-директории в репозитории **нет**, decrypt-задачи не заведены, age-ключ не требуется. Весь раздел ниже — конвенция, активируемая с первой реальной потребностью в секретах.

> **Desktop (Win/Linux/macOS) в скелете не потребляет реальных секретов** → пропускает `secrets:decrypt`, не нуждается в age-ключе. Когда у desktop появятся секреты, на него расширяется та же схема SOPS+age+mise (именование задач — см. §4).

---

## 3. `.sops.yaml`

```yaml
creation_rules:
  - path_regex: ^secrets/.*\.enc\.yaml$
    age: age1examplepublickeyreplaceme0000000000000000000000000000000   # TBD: real team public age key
```

Каждый `secrets/**/*.enc.yaml` автоматически шифруется на командный публичный age-ключ при `sops edit`. Замените `age1example...` на реальный командный публичный ключ (в коде сегодня стоит именно placeholder-значение — см. комментарий `# TBD: real team public age key`).

---

## 4. `.mise.toml` — пины инструментов + граф задач

`.mise.toml` пинит `sops 3.9` / `age 1.2`, указывает путь к приватному age-ключу (`SOPS_AGE_KEY_FILE`) и резолвит Flutter через FVM-симлинк (`FLUTTER`). Это структурный TOML-файл — ключи на английском.

> **Skeleton carve-out (Feature-001).** В реальном `.mise.toml` сегодня **нет** ни одной `secrets:*`-задачи и ни одного `secrets:decrypt`: сборочная матрица единообразна по всем пяти платформам и идёт в `--debug` с флейвором из `config/<flavor>.json`. Дословный комментарий-шапка из актуального `.mise.toml`:
>
> ```toml
> # --- Builds: flavor injected uniformly from a committed config file
> #     (--dart-define-from-file=config/<flavor>.json) on all five platforms.
> #     SKELETON CARVE-OUT: native mobile flavors (distinct stage applicationId/bundle id,
> #     signing) are deferred until a real per-flavor native need (blueprint 09 §6/§7,
> #     same stance as desktop §7a) — the skeleton has no per-flavor native difference yet.
> #     NO secrets:decrypt (no age key); all --debug (release/packaging = FUTURE, §11a).
> ```
>
> Фактический build-таск каждой из десяти комбинаций `<platform>:<flavor>`:
>
> ```toml
> [tasks."build:android:stage"]
> run = "$FLUTTER build apk --debug --dart-define-from-file=config/stage.json"
> # … аналогично android:prod, ios:{stage,prod} (+ --no-codesign), macos/windows/linux:{stage,prod}
> ```
>
> Целевая форма (с decrypt + obfuscate + release) описана ниже как конвенция; она включается с появлением секретов и релизной упаковки.

Целевая форма `.mise.toml` (пины + граф «decrypt → build»):

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

# --- mobile build matrix (each depends on the matching decrypt) -------------
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
# Desktop has no native --flavor; stage/prod selected via config/<flavor>.json.
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
- `--obfuscate --split-debug-info=build/symbols` включён для релизных сборок (символы для дешифровки стек-трейсов в observability-бэкенде — см. `OBSERVABILITY_DSN` в env-наборе; **конкретный observability-вендор не зафиксирован**, DSN env-gated в `prod`/`stage`; см. `17-analytics.md` про vendor-neutral / opt-in модель).
- `jq '{ ... }'` явно перечисляет только те ключи, которые должны попасть в `dart-define` — это allowlist, а не «весь YAML». Набор ключей (`API_URL`, `SUPPORT_EMAIL`, `OBSERVABILITY_DSN`) — **пример** (бэкенд/протокол NOX ещё не выбран; замените на реальный контракт). Добавляя новую переменную в `dart-define`, расширьте этот список **в обоих** флейворах.

### 4.1 dart-define-контракт — состояние и TBD

Единственный закоммиченный dart-define-ключ сегодня — **`app.flavor`** (`config/<flavor>.json` несёт только его). Его читает `AppFlavor.getFlavor()` через `String.fromEnvironment('app.flavor')`; пустое/неизвестное значение → `prod` (безопасный дефолт). Скелетный конфиг-объект — это плоский value-object **`AppConfig`** (`lib/domain/model/app_config/app_config.dart`), который сегодня несёт **только** `flavor`:

```dart
class AppConfig {
  const AppConfig({required this.flavor});
  final AppFlavorType flavor; // TODAY carries ONLY flavor
}
```

`AppConfig` создаётся не через конструкторную инъекцию, а **императивно при бутстрапе**: `AppConfigRepositoryImpl.initialize(flavorType:)` собирает значение, а читается оно через `AppConfigRepository.config`. Контракт репозитория:

```dart
abstract class AppConfigRepository {
  Future<void> initialize({required AppFlavorType flavorType});
  AppConfig get config;
}

@LazySingleton(as: AppConfigRepository, env: [Environment.dev, Environment.prod, Environment.test])
class AppConfigRepositoryImpl implements AppConfigRepository {
  AppConfig? _config;
  @override
  Future<void> initialize({required AppFlavorType flavorType}) async {
    _config = AppConfig(flavor: flavorType);
  }
  @override
  AppConfig get config => _config ?? (throw StateError('AppConfigRepository.initialize was not called'));
}
```

Скелет vs целевой: **скелетный `AppConfig` несёт только `flavor`**. Никаких полей, читающих `API_URL` / signature-key (`apiSignatureKey`) / observability-DSN, в коде сегодня **нет** — это **целевые поля `AppConfig` (пример/TBD)**, которые добавляются, когда выберут бэкенд/протокол NOX. Файл помечен комментарием «token source / apiUrl / security headers are example/TBD (backend not chosen)».

**Секрето-несущий набор dart-define-ключей — пример/TBD** (бэкенд/протокол NOX ещё не выбран). Иллюстративный allowlist (`API_URL`, `SUPPORT_EMAIL`, `OBSERVABILITY_DSN`) из §4 — это **пример** будущего контракта, а не зафиксированный набор. Когда контракт появится, добавьте соответствующие целевые поля в `AppConfig` (и заполняйте их в `AppConfigRepositoryImpl.initialize(...)`) и расширьте `jq`-allowlist синхронно.

> **Пустой ключ = выключенная фича, а не ошибка.** Когда секрето-несущие ключи появятся, пустое значение должно означать no-op, а не падение: `dev` без observability-DSN ⇒ `OBSERVABILITY_DSN=''` ⇒ телеметрия молчит (см. `17-analytics.md` — аналитика по умолчанию **выключена** до согласия пользователя). Флейвор передаётся **отдельным** ключом `app.flavor` (не из секретов).

---

## 5. `Makefile` — тонкая обёртка

`Makefile` — человеко-дружелюбная поверхность над dev-workflow и mise-задачами. Реальная логика секретов/сборок живёт в `.mise.toml`; dev-команды делегируют в `fvm`.

> **Состояние скелета.** Актуальный `Makefile` несёт desktop-build-обёртки (делегируют в `mise run build:<platform>:<flavor>`) и dev-helpers: `deps` (`fvm flutter pub get`), `generate` (один прогон `build_runner`), `format` (`fvm dart format -l 140 lib test` — **mutating**, по `lib test`), `analyze`, `test`, и композитную цель `gate: generate format analyze test`. Цели `secrets-*` и отдельного `format-check` в нём **пока нет** — они вводятся вместе с секретами/CD (ниже).

Целевая форма `Makefile` (рекомендуемая конвенция; добавляет `format`/`format-check`-сплит + secrets-обёртки):

```makefile
.DEFAULT_GOAL := help

help: ## Show all targets
	@awk 'BEGIN {FS=":.*?## "} /^[a-zA-Z0-9_.-]+:.*?## / {printf "  \033[36m%-28s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# --- Dev workflow -----------------------------------------------------------
deps: ## Resolve pub dependencies
	fvm flutter pub get

generate: ## Regenerate code (freezed, injectable, assets) — SINGLE build_runner run
	fvm dart run build_runner build --delete-conflicting-outputs

analyze: ## flutter analyze
	fvm flutter analyze

test: ## Run all tests, or one via `make test FILE=<path>`
	fvm flutter test $(FILE)

format: ## Mutating — format the tree in-place (local convenience). NOT a CI gate.
	fvm dart format -l 140 lib test

format-check: ## Non-mutating CI gate — fails if anything is unformatted; writes nothing
	fvm dart format --output=none --set-exit-if-changed -l 140 $$(git ls-files lib test | grep '\.dart$$')

gate: ## Local CI mirror — generate + format-check + analyze + test
	$(MAKE) generate && $(MAKE) format-check && $(MAKE) analyze && $(MAKE) test

# --- Builds — delegate to mise (logic lives in .mise.toml) -------------------
build-android-stage: ## Stage APK
	mise run build:android:stage
build-android-prod: ## Prod AAB
	mise run build:android:prod
build-ios-stage: ## Stage IPA
	mise run build:ios:stage
build-ios-prod: ## Prod IPA
	mise run build:ios:prod
build-macos-stage: ## Stage macOS app
	mise run build:macos:stage
build-windows-stage: ## Stage Windows app
	mise run build:windows:stage
build-linux-stage: ## Stage Linux app
	mise run build:linux:stage

# --- Secrets (future; introduced with the first real secret need) -----------
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

> **`format` vs `format-check` (разделение ролей).** `make format` — **mutating**: форматирует `lib test` in-place, удобно локально. `make format-check` — **non-mutating CI-гейт** (`--output=none --set-exit-if-changed`): ничего не пишет, только валит сборку при расхождении; именно его дёргает CI (см. §8.1) и локальное зеркало (§8.3). Скелетный `Makefile` сегодня несёт только единый mutating `format` (по `lib test`) — `format-check` рекомендуется добавить как отдельную цель. По репозиторному правилу форматирования (`08-conventions-and-constitution.md`) после правок форматируйте **только изменённые в текущей задаче файлы**: `fvm dart format -l 140 <явные пути>` — это отдельная операция, не равная ни `format`, ни `format-check`. Никогда не запускайте `make format` (всё дерево/`lib test`) как финальный шаг рабочей задачи — он зашумит diff (включая регенерированные `*.freezed.dart` / `*.config.dart`).

---

## 6. Android Gradle — флейворы, подпись, pre-build хук секретов

> **Skeleton carve-out (Feature-001):** в текущем скелете нативные Android-флейворы **НЕ заведены** — флейвор инжектится через `--dart-define-from-file=config/<flavor>.json` (как desktop, §7a), потому что per-flavor нативной разницы пока нет. Фактический `android/app/build.gradle.kts` не содержит `productFlavors`, `signingConfigs.flavorSigning`, `afterEvaluate`-хука; `namespace = "com.cyphernetlabs.nox_app"` (с подчёркиванием), `applicationId = "com.cyphernetlabs.noxapp"`, `compileSdk = flutter.compileSdkVersion` / `minSdk = flutter.minSdkVersion` (дефолты Flutter, не хардкод), отдельный блок `kotlin { compilerOptions { jvmTarget = JVM_17 } }`, `compileOptions` Java 17, релиз подписывается **debug-ключами** (`signingConfig = signingConfigs.getByName("debug")`), `AndroidManifest android:label="NOX"`. Блок `productFlavors` + signing + хук ниже вводятся с первой реальной per-flavor нативной потребностью (раздельная подпись / Firebase / идентичность).

> **Расхождение идентификаторов (минорное, флагнуто).** Сейчас `namespace = com.cyphernetlabs.nox_app` (с подчёркиванием) при `applicationId = com.cyphernetlabs.noxapp` (без подчёркивания). Канонический app id — `com.cyphernetlabs.noxapp`(+`.stage`); подчёркивание в namespace — артефакт дефолтного `flutter create` (technical-имя), при заведении флейворов его стоит выровнять. Это не «тихая правка в доках», а зафиксированное расхождение.

Целевая форма (`android/app/build.gradle.kts`) — несущие блоки. Конвенции проекта: `compileSdk 36`, `minSdk 26`, Java 17, `applicationId` по флейвору (`com.cyphernetlabs.noxapp` для prod, `com.cyphernetlabs.noxapp.stage` для stage).

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
            workingDir = rootProject.projectDir.parentFile  // repo root (android/ -> ..)
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

> **Skeleton carve-out (Feature-001):** в скелете iOS-флейворы (xcconfig / schemes ниже) **НЕ заведены** — флейвор идёт через `--dart-define-from-file=config/<flavor>.json` (как desktop, §7a). `ios/Runner/Info.plist` использует `$(PRODUCT_BUNDLE_IDENTIFIER)`; отдельных `Stage.xcconfig` / `Prod.xcconfig` пока нет. Нативная настройка ниже вводится с первой реальной per-flavor нативной потребностью.

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
- **Распространение через fastlane.** Лейны (TestFlight / Firebase App Distribution) вызываются из mise-задач `build:ios:*` с `--export-options-plist=...`. Fastlane — заметка-заглушка на будущее: когда появится Apple Developer аккаунт, добавьте `ios/fastlane/Fastfile` с лейнами `stage` (App Distribution) и `prod` (TestFlight/App Store), вызываемыми после соответствующего `build:ios:*`.

---

## 7a. Идентичность desktop (macOS / Windows / Linux)

В этой итерации desktop-таргеты несут **только prod-идентичность** на нативном уровне (одна нативная конфигурация на платформу). Отдельная нативная `.stage`-идентичность (и, соответственно, упаковка двух раздельных артефактов) — **на будущее** (§11a). Stage на desktop виден исключительно через `app.flavor` в Dart (`--dart-define-from-file=config/stage.json`), нативная конфигурация при этом не меняется.

- **macOS.** В `macos/Runner/Configs/AppInfo.xcconfig` prod-идентичность: `PRODUCT_BUNDLE_IDENTIFIER = com.cyphernetlabs.noxapp` + `PRODUCT_NAME = NOX` (подтверждено кодом). Отдельная `.stage`-идентичность (`com.cyphernetlabs.noxapp.stage`) → упаковка **на будущее** (§11a).
- **Windows.** В `windows/CMakeLists.txt` — `BINARY_NAME = "nox_app"` (technical-имя бинарника); в `windows/runner/Runner.rc` блок `VERSIONINFO` несёт `CompanyName = "Cyphernet Labs"`, `ProductName = "NOX"`, `FileDescription = "NOX"`, `InternalName = "nox_app"`. Закоммиченный стабильный GUID приложения (между сборками) — **на будущее** (в текущем `Runner.rc` отдельного app-GUID нет). Отдельная `.stage`-идентичность → упаковка **на будущее** (§11a).
- **Linux.** В `linux/CMakeLists.txt` — `APPLICATION_ID = "com.cyphernetlabs.noxapp"`, `BINARY_NAME = "nox_app"` (technical-имя). `Name` в `.desktop`-файле — `NOX`; сам `.desktop`-файл — **на будущее** (генерируется при упаковке, §11a). Отдельная `.stage`-идентичность → упаковка **на будущее** (§11a).

> **Имя бинарника vs ProductName.** На Windows/Linux `BINARY_NAME`/`InternalName` = `nox_app` (технический идентификатор), а пользовательское `ProductName`/`PRODUCT_NAME` = `NOX` (all caps). Это намеренное разделение: технический артефакт — `nox_app`, отображаемое имя — `NOX`.

---

## 8. CI — GitHub Actions

NOX владеет **двумя standalone-workflow** (никакого монорепо/корневого `ci.yml`/reusable-workflow): `ci.yml` — гейт (format-check → **один** прогон кодогена → analyze → test) и `compile-check.yml` — пять per-platform debug smoke-сборок. Оба пинят Flutter `3.44.1` через `subosito/flutter-action` и триггерятся на ветках `develop` и `master`.

> **Один пакет — один прогон.** Пакет один, поэтому `pub get`, кодоген и тесты — **единственный** прогон каждого шага. Не раскладывайте их на три каталога (`data → domain → root`) и не воспроизводите трёх-этапный порядок.

### 8.1 `.github/workflows/ci.yml` — gate (analyze & test)

Соответствует фактическому коду: **один** джоб `gate` на `macos-latest`, триггеры на `[develop, master]`, format-check по `git ls-files lib test`, **без** `defaults.run.working-directory`.

```yaml
name: NOX CI

on:
  push:
    branches: [develop, master]
    paths: ['lib/**', 'test/**', 'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'build.yaml']
  pull_request:
    paths: ['lib/**', 'test/**', 'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'build.yaml']

jobs:
  gate:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.44.1'
          channel: stable
          cache: true
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      - name: Format check (lib + test only; docs/ and generated excluded)
        run: dart format -l 140 --set-exit-if-changed $(git ls-files lib test | grep '\.dart$')
      - run: flutter analyze
      - run: flutter test
```

Замечания:
- CI использует `subosito/flutter-action` напрямую (не FVM), но **версия совпадает с `.fvmrc`** (`3.44.1`), поэтому поведение идентично.
- Format-check — **non-mutating** (`dart format -l 140 --set-exit-if-changed`) по списку `git ls-files lib test | grep '\.dart$'`. Это берёт только трекаемые `.dart`-файлы под `lib`/`test`; сгенерированные `*.freezed.dart`/`*.config.dart`/`*.g.dart`/`lib/design/gen/**` gitignored (§10) и в список не попадают. Правьте локально через `fvm dart format -l 140 <пути>` (изменённые файлы) или `make format-check` (тот же гейт).
- Кодоген — **один** `dart run build_runner build --delete-conflicting-outputs` (не data→domain→root; пакет один). `--delete-conflicting-outputs` удаляет устаревшие сгенерированные файлы вместо ошибки при перезаписи. Кодоген обязателен **перед** format-check/analyze/test: генераты gitignored, без него `analyze`/`test` упадут на отсутствующих файлах.
- `paths:` фильтр ограничивает workflow изменениями под `lib/`, `test/`, `pubspec.*`, `analysis_options.yaml`, `build.yaml` — это удобно для пер-проектного детекта изменений, если NOX когда-либо встроят в более широкую CI-политику (см. §11).

### 8.2 `.github/workflows/compile-check.yml` — per-platform debug smoke-сборки

Соответствует фактическому коду: **пять** параллельных джобов (Android, iOS, macOS, Windows, Linux), триггеры на `[develop, master]` + `workflow_dispatch`, **каждый** джоб передаёт `--dart-define-from-file=config/stage.json`. Launch-verify сегодня: macOS + iOS + Android; Windows/Linux — compile-only (launch — отслеживаемый follow-up). Packaging/signing — **на будущее** (§11a).

```yaml
name: NOX Compile check

# Five per-platform debug smoke builds (no secrets). Launch-verify today: macOS + iOS
# + Android; Windows/Linux are compile-only (launch is a tracked follow-up). Desktop
# flavor comes from config/<flavor>.json (no native --flavor). Packaging/signing: FUTURE.

on:
  push:
    branches: [develop, master]
    paths: ['lib/**', 'pubspec.yaml', 'pubspec.lock']
  workflow_dispatch:

jobs:
  compile-android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.44.1', channel: stable, cache: true }
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      - run: flutter build apk --debug --dart-define-from-file=config/stage.json

  compile-ios:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.44.1', channel: stable, cache: true }
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      - run: flutter build ios --debug --no-codesign --dart-define-from-file=config/stage.json

  compile-macos:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.44.1', channel: stable, cache: true }
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      - run: flutter build macos --debug --dart-define-from-file=config/stage.json

  compile-windows:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.44.1', channel: stable, cache: true }
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      - run: flutter build windows --debug --dart-define-from-file=config/stage.json

  compile-linux:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: sudo apt-get update && sudo apt-get install -y ninja-build libgtk-3-dev libsecret-1-dev libjsoncpp-dev
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.44.1', channel: stable, cache: true }
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      - run: flutter build linux --debug --dart-define-from-file=config/stage.json
```

Замечания:
- Smoke-сборки запускаются в `--debug` и **не требуют секретов** — мы не вызываем decrypt и не используем секрето-несущий `--dart-define-from-file`. Это компайл-чек, а не релиз. Все пять джобов единообразно передают `--dart-define-from-file=config/stage.json` (только `app.flavor=stage`); iOS добавляет `--no-codesign`; Linux ставит `ninja-build libgtk-3-dev libsecret-1-dev libjsoncpp-dev` (GTK-тулчейн для desktop-эмбеддера + **build-time** зависимости плагина `flutter_secure_storage_linux`: его `CMakeLists.txt` делает `pkg_check_modules` на `libsecret-1`/`jsoncpp`, иначе `flutter build linux` падает на конфигурации CMake — `required packages were not found: libsecret-1`).
- Этот compile-check покрывает все **5 целевых платформ** (конституция v1.1.0): Android + iOS + macOS + Windows + Linux. Desktop compile-smoke **включён**; упаковка/подпись (packaging/signing) — **на будущее** (§11a). Никаких desktop/Rust/FFI-шагов сверх этого нет.

**Platform support matrix (minimum OS).** Минимальные версии берутся из дефолтов `flutter create` под Flutter `3.44.1`. Пиннинг конкретных таргетов и подбор Linux apt-deps — **на будущее**.

| Platform | Minimum OS |
|---|---|
| Windows | Windows 10 (Flutter 3.44 floor) |
| macOS | macOS 10.15+ (`flutter create` default) |
| Linux | GTK3 runtime |

### 8.3 Локальное зеркало CI

Прогоните ту же последовательность локально перед пушем, чтобы поймать падения CI заранее:

```bash
make generate       # 1. build_runner (single run)
make format-check   # 2. non-mutating format-check at 140 (same gate as CI)
make analyze        # 3. flutter analyze
make test           # 4. flutter test
```

Это зеркалит джоб `gate` из `ci.yml` (CI дёргает **non-mutating** format-check, не mutating `format`). Композитная цель `make gate` (целевая форма, см. §5) прогоняет всю последовательность одной командой. **Важно:** скелетный `make gate` сегодня — это `gate: generate format analyze test` и использует **mutating** `format` (по `lib test`), а не `format-check` — то есть он пока **не** зеркалит non-mutating гейт CI (то же расхождение зафиксировано в §5). Чтобы воспроизвести CI точно, прогоняйте `make format-check` явно (последовательность из четырёх шагов выше), пока `gate` не переведут на `format-check`. Обёртка `.claude/commands/check-build` (см. `12-dev-commands.md`) оборачивает шаги 1–3.

---

## 9. Релизный поток — CalVer + shifted-epoch

Версия в `pubspec.yaml::version` — **закоммиченное** значение в формате CalVer + сдвинутый epoch.

```
version: YY.M.D+SHIFTED_EPOCH
```

- `YY` — две последние цифры года; `M` — месяц без ведущего нуля; `D` — день без ведущего нуля (CalVer; пример: `26.6.7`).
- `SHIFTED_EPOCH` — build number: `UNIX_TIMESTAMP - 1577836800`, где `1577836800` = `2020-01-01 00:00:00 UTC` (`BUILD_EPOCH_BASE`). Сдвиг даёт ~60 лет запаса под потолок `versionCode` Play Store (2.1B) — headroom до ~2086.

```bash
# Compute the shifted-epoch build number.
BUILD_NUMBER=$(( $(date -u +%s) - 1577836800 ))
echo "version: $(date -u +%y.%-m.%-d)+${BUILD_NUMBER}"
# e.g. -> version: 26.6.7+202979472
```

> **Канонический формат — `YY.M.D`.** Месяц/день без ведущего нуля (не `YY.MM.DD`).

> **Состояние скелета.** Закоммиченная версия в `pubspec.yaml` сегодня — **placeholder `26.1.1+0`** (не настоящий shifted-epoch). Реальный `YY.M.D+SHIFTED_EPOCH` записывается при первом релизе. Комментарий-кросс-реф в `pubspec.yaml` указывает на канонический дом блюпринта — `docs/blueprints/mobile/09-build-and-secrets-infra.md` §9.

**Каналы не меняют строку версии.** Никаких суффиксов `-rc.N` / `-dev.N` / `-stage.N` в `version`. Stage и prod собирают один и тот же артефакт; различие — это git-тэг + флейвор, а не версия. Имя артефакта: `nox_app_<version>_<build>.<ext>` — например `nox_app_26.5.10_200429805.apk` / `.aab` / `.ipa`.

**Git-тэги** (канонический формат `<project>-v<version>` + суффикс канала): `nox_app-v26.6.7+202979472-stage` / `nox_app-v26.6.7+202979472-prod`. Гейт: если тэг указывает на коммит, где `pubspec.yaml::version` ≠ версии в тэге — build обязан фейлиться.

**Релизы — только one-dispatch (никаких локальных `make`-обёрток релиза).** Релиз запускается единственным `workflow_dispatch` в GitHub Actions — `release-stage.yml` / `release-production.yml`: bump `pubspec.yaml::version` → PR → auto-merge → tag → CD. **Тэг — единственный CD-триггер.** Локальные `make`-таргеты релиза (prepare / stage / prod), которые сами коммитят/тэгают/пушат, **не вводятся** — они дублируют и обходят one-dispatch-модель, которой управляет владелец (риск автономного релиза). Никаких `make release-*` целей и никаких `script_*.sh`-релизных скриптов.

> **NOX CD отложен.** `nox_app-cd-{stage,prod}.yml` пока **не активирован** — до появления Apple Developer / Google Play аккаунтов и desktop-сертификатов. Версионирование (`pubspec.yaml::version`, CalVer + shifted-epoch выше) и тэг-формат готовы; CD активируется при онбординге дистрибуции. До этого локально собирают через `mise run build:<platform>:<flavor>` (§4) / `make build-*` для проверки, без публикации.

> **Версия — всегда закоммиченное значение.** CI может писать `pubspec.yaml::version`, но **только** через коммит — никогда runtime-инъекцией вида `flutter build --build-number=$GITHUB_RUN_NUMBER`. API-версионирование (например `/api/v1/` — **пример**, бэкенд/протокол NOX ещё не выбран; заменить на реальный контракт) — отдельная ось от версии артефакта.

---

## 10. `.gitignore` — дополнения

Фактический NOX-блок в `.gitignore` (секреты-runtime + декрипты + Generated):

```gitignore
# --- NOX blueprint additions (09 §10) ---
.secrets-runtime/
.fvm/flutter_sdk
**/*.enc.yaml.dec
android/**/google-services.json
ios/Runner/Firebase/**/GoogleService-Info.plist
**/*_keystore.jks
**/*_keystore.properties

# --- Generated (codegen-first; regenerate via build_runner) ---
*.g.dart
*.freezed.dart
*.config.dart
lib/design/gen/
```

> Никогда не коммитьте `.secrets-runtime/`, локально расшифрованные `*.enc.yaml.dec`, `google-services.json` / `GoogleService-Info.plist` или keystores. Они материализуются `secrets:decrypt:<flavor>` из зашифрованного источника истины и должны быть восстановимы в любой момент. Сгенерированные файлы (`*.g.dart` / `*.freezed.dart` / `*.config.dart` / `lib/design/gen/`) восстанавливаются `build_runner` (см. §0, §8). `.fvmrc` (пин SDK) — **коммитится**; кэш/симлинк `.fvm/flutter_sdk` — нет.

---

## 11. Интеграция в CI/CD

Проект NOX — **standalone-репозиторий** со своими `ci.yml` + `compile-check.yml` (§8). При желании он может онбордиться в более широкую GitHub Actions / CI-CD-политику. Ключевые точки сопряжения:

- **Детект изменений (опционально).** Если NOX когда-либо встроят в монорепо, пер-проектный детект изменений делают `dorny/paths-filter@v3` (job-level `if`) с агрегатным `CI summary` как единственной required-проверкой; путь-фильтр держат **внутри** workflow (job-level), не сужая `on:`-триггер. Сегодня это не применяется — у NOX свои standalone-workflow с `paths:`-фильтром в собственном `on:`.
- **One-dispatch релизная модель.** Релизы запускаются единственным `workflow_dispatch` (`release-stage.yml` / `release-production.yml`): bump → PR → auto-merge → tag → CD. Тэг — единственный CD-триггер. NOX CD (`nox_app-cd-{stage,prod}.yml`) пока **отложен** до появления Apple Developer / Google Play аккаунтов и desktop-сертификатов.
- **Аутентификация.** Релизные workflow используют fine-grained PAT (например `RELEASE_BUMP_PAT`), а не `GITHUB_TOKEN` — последний не триггерит downstream-workflow на push тэга. Конкретные имя/org/scope PAT — TBD (привязывается при настройке CD).
- **Секреты CI.** Когда decrypt появится, расшифровка секретов в CI потребует `SOPS_AGE_KEY_CI` (репо-секрет с приватным age-ключом команды). Для smoke-сборок (`--debug`) ключ не нужен — они не расшифровывают секреты. Desktop (Win/Linux/macOS) в скелете не потребляет реальных секретов → пропускает `secrets:decrypt`, не нуждается в age-ключе; когда у desktop появятся секреты, на него расширяется та же схема SOPS+age+mise (именование задач — см. §4).
- **Никаких автономных merge/deploy/commit.** Открывайте PR и пушьте в feature-ветку, но **не** мёрджите PR, **не** деплойте в cloud и **не** коммитьте без явного запроса владельца в текущей сессии.

---

## 11a. Упаковка и подпись desktop (на будущее)

`TODO(blueprint-desktop-packaging)` — **без реализации** в этой итерации; скелет даёт только `--debug` compile-smoke (§8.2) и `build:<desktop>:<flavor>` без упаковки (§4). Когда desktop-дистрибуция активируется, по платформам:

- **Windows.** MSIX-пакет + подпись инсталлятора code-signing-сертификатом (EV/OV).
- **macOS.** DMG + `codesign` + нотаризация через `xcrun notarytool` + hardened runtime.
- **Linux.** AppImage и/или `.deb`.

Блокер тот же, что у мобильного/desktop CD (§11): нет аккаунтов/сертификатов для подписи (Apple Developer / code-signing cert) — пока они не заведены, упаковка и подпись desktop остаются на будущее, параллельно отложенному CD.

> `TODO(blueprint-desktop-window)` — скелет поставляет **дефолтное окно** Flutter desktop-раннера (single-window, без `window_manager`, нативный chrome/title bar). Полировка **на будущее**: `window_manager` для задания начального размера `1440x900` (канонический размер из корпуса) + `minimumSize 640x600` + кастомный unified title bar.

---

## Чеклист

- [ ] `.fvmrc` (в корне репозитория) коммитит `flutter: 3.44.1`; `fvm install` проходит.
- [ ] `pubspec.yaml` объявляет `sdk: '>=3.12.0 <4.0.0'` и `flutter: 3.44.1`; `version` = закоммиченный `YY.M.D+SHIFTED_EPOCH` (в скелете placeholder `26.1.1+0`).
- [ ] `config/stage.json` / `config/prod.json` несут только `{"app.flavor": "..."}`; используются единообразно на всех пяти платформах в скелете (desktop — постоянно).
- [ ] `.mise.toml` пинит `sops 3.9` / `age 1.2`, `SOPS_AGE_KEY_FILE` → приватный ключ, `FLUTTER` → `.fvm/flutter_sdk`; скелетные `build:<platform>:<flavor>` = `$FLUTTER build … --debug --dart-define-from-file=config/<flavor>.json` (10 комбинаций; **нет** `secrets:*`).
- [ ] `.sops.yaml` содержит creation rule + (placeholder) командный публичный age-ключ; `secrets/` и decrypt-задачи — конвенция на будущее (бэкенд не выбран).
- [ ] Decrypt-задачи (когда появятся) атомарны (`.tmp` + `mv`), пишут `dart-define.json` (jq-allowlist, vendor-neutral `OBSERVABILITY_DSN`) + нативные конфиги; набор ключей — пример/TBD.
- [ ] `Makefile`: `deps`/`generate`/`format`/`analyze`/`test` + композитный `gate`; рекомендованный сплит `format` (mutating) vs `format-check` (non-mutating CI-гейт); build-обёртки делегируют в `mise run build:*`; **нет** `make release-*`.
- [ ] Gradle (target): dimension `app` (`stage`/`prod`), per-flavor `applicationId` (`com.cyphernetlabs.noxapp[.stage]`), детект флейвора, выбор keystore, secrets-хук на `pre<Flavor><BuildType>Build`. Скелет: флейворов/подписи/хука нет, namespace `com.cyphernetlabs.nox_app` (underscore) vs applicationId `com.cyphernetlabs.noxapp`, compile/minSdk из `flutter.*`, label `NOX`, release на debug-ключах.
- [ ] iOS (target): `Stage.xcconfig` / `Prod.xcconfig` + схемы `stage`/`prod`; Firebase plist через `secrets:decrypt`; fastlane на будущее. Скелет: флейворы не заведены.
- [ ] Desktop-идентичность (§7a): macOS `PRODUCT_NAME=NOX` + bundle id `com.cyphernetlabs.noxapp`; Windows `ProductName "NOX"` / `BINARY_NAME "nox_app"`; Linux `APPLICATION_ID com.cyphernetlabs.noxapp` / `BINARY_NAME nox_app`; только prod-идентичность.
- [ ] `.github/workflows/ci.yml`: один джоб `gate` на `macos-latest`, ветки `[develop, master]`, pub get → один кодоген → non-mutating format-check (`git ls-files lib test`) → analyze → test; `subosito/flutter-action` `3.44.1`; без `working-directory`.
- [ ] `.github/workflows/compile-check.yml`: пять джобов (Android/iOS/macOS/Windows/Linux), ветки `[develop, master]` + `workflow_dispatch`, каждый `--dart-define-from-file=config/stage.json` (iOS `--no-codesign`; Linux ставит `ninja-build libgtk-3-dev`); все 5 целевых платформ (конституция v1.1.0).
- [ ] Релизы — one-dispatch (`release-stage.yml`/`release-production.yml`); **нет** `make release-*` / `script_*.sh`; CD (`nox_app-cd-{stage,prod}.yml`) отложен до Apple/Play/desktop-сертификатов.
- [ ] `.gitignore` исключает `.secrets-runtime/`, `.fvm/flutter_sdk`, `**/*.enc.yaml.dec`, расшифрованные нативные конфиги/keystores и Generated-блок (`*.g.dart`/`*.freezed.dart`/`*.config.dart`/`lib/design/gen/`).
- [ ] Упаковка/подпись desktop задокументированы как «на будущее» (§11a); compile-smoke для desktop — есть (§8.2).
- [ ] Локальное зеркало CI (`make generate && make format-check && make analyze && make test`, или `make gate`) проходит до пуша.
```