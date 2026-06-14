# Контракт: DI и app-bootstrap

> **Источник:** блюпринт `docs/blueprints/mobile/02-dependency-injection.md` (§3, §10) + `05-presentation-layer.md` §6.3; требование FR-006. Один Dart-пакет `nox_app` → один контейнер → один генератор.

## 1. Единая точка входа DI

Ровно **одна** функция с `@InjectableInit` на весь пакет; имя инициализатора — `$initGetIt` (никаких `$initDomainGetIt` / `$initDataGetIt`).

```dart
// lib/di/configure_dependencies.dart
final getIt = GetIt.instance;

@InjectableInit(initializerName: r'$initGetIt')
Future<void> configureDependencies(String env) async {
  getIt.$initGetIt(environment: env); // единственный вызов генератора
  // + ручные регистрации, которые генератор не выводит (PackageInfo: async на устройстве, mock под test)
}
```

Правила контракта:

- **Сигнатура фиксирована:** `Future<void> configureDependencies(String env)`. `env` — строка DI-окружения (`Environment.dev` / `Environment.prod` / `Environment.test`), которой генератор фильтрует регистрации.
- **`configure_dependencies.config.dart` — сгенерирован**, не правится руками, исключён из анализа/форматирования (как `*.g.dart` / `*.freezed.dart`).
- **Контейнер плоский:** и `presentation`, и `data` регистрируются в одном `GetIt.instance`; точка склейки — `@LazySingleton(as: Interface)` (impl из `lib/data` ↔ контракт из `lib/domain`), однонаправленна.
- Единственная значимая **ручная** регистрация — `PackageInfo`: вне теста `factoryAsync(..., preResolve: true)`, под тестом `setMockInitialValues(...)`.

## 2. Маппинг flavor → DI-окружение

Окружений ровно три; кастомных нет. Маппинг — единственная точка превращения флейвора в окружение:

| Flavor (`app.flavor`) | DI-окружение |
|---|---|
| `prod` | `Environment.prod` |
| `stage` | `Environment.dev` |
| (тесты) | `Environment.test` |

`AppFlavor.getFlavor()` читает `String.fromEnvironment('app.flavor')`; пустое/неизвестное значение → `prod` (безопасный дефолт). См. `build-flavors.md`.

## 3. Последовательность `main.dart`

`main.dart` обёрнут в `runZonedGuarded`; точный порядок (FR-006):

```
WidgetsFlutterBinding.ensureInitialized()
  → flavor = AppFlavor.getFlavor()
  → env = flavor == AppFlavorType.prod ? Environment.prod : Environment.dev
  → await configureDependencies(env)        // (+ setPreferredOrientations параллельно)
  → await getIt.allReady()                   // дожидается preResolve:true (PackageInfo)
  → await getIt<AppConfigRepository>().initialize(flavorType: flavor)
  → runApp(const AppRoot())
```

- **`runZonedGuarded`** — внешний safety-net: всё непойманное над деревом виджетов уходит через единый `LogRepository` (если DI поднят); **никакого сырого `print`/`debugPrint`** (FR-011).
- **`getIt.allReady()`** обязателен — без него async-`preResolve`-регистрации (`PackageInfo`) бросят «not ready».
- `AppConfigRepository.initialize(flavorType:)` поднимает флейвор-зависимый конфиг **после** готового контейнера. Контракт самого `AppConfigRepository` (источник токена, `apiUrl` и т. п.) — **пример/TBD** (бэкенд NOX не выбран, см. `14`); в скелете он несёт только флейвор.
- **Отдельного BLoC-observer'а нет:** ошибки репозиториев логируются в `BaseRepositoryHelper.execute`, ошибки handler'ов BLoC — в `BaseBloc.executeLogic`.

## 4. Desktop-замечание

Последовательность bootstrap **идентична** на всех пяти платформах. Desktop-специфика касается только источника флейвора (`--dart-define-from-file`, см. `build-flavors.md`) и пропуска secrets-decrypt; сама форма `configureDependencies(env)` / `main.dart` не меняется. Push-`Firebase.initializeApp()` (mobile-only, до `runApp`) на десктопе **не вызывается** — push = disabled/no-op (пример/TBD, см. `15`).

## Чеклист

- [ ] Один `@InjectableInit(initializerName: r'$initGetIt')` → `getIt.$initGetIt(environment: env)`; `.config.dart` не правится руками.
- [ ] `configureDependencies(String env)` — единственная DI-точка входа; контейнер плоский.
- [ ] Маппинг `prod → Environment.prod`, `stage → Environment.dev`, тесты → `Environment.test`.
- [ ] `main.dart`: `runZonedGuarded` → `configureDependencies(env)` → `getIt.allReady()` → `AppConfigRepository.initialize(flavorType:)` → `runApp(AppRoot)`.
- [ ] Ни одного `print`/`debugPrint` в `lib/`; uncaught → `LogRepository`.
