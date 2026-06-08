# 02 — Внедрение зависимостей и bootstrap

> **Назначение:** задать единственно верный способ собрать DI-контейнер приложения Speech AI Mobile — один `get_it` + `injectable` поверх **одного** Dart-пакета `speech_ai_mobile`, плюс детерминированную последовательность запуска (`main.dart`), флейворы, конфигурацию, локальную БД и обязательное логирование. **Когда читать:** при первичной настройке проекта, при добавлении нового репозитория / DAO / маппера / API, при отладке «почему `getIt<T>()` бросает на резолве», при правке последовательности bootstrap или флейворов. **Связанные документы:** [00-architecture-overview.md](00-architecture-overview.md) (границы слоёв и направление зависимостей), [01-stack-and-tooling.md](01-stack-and-tooling.md) (версии пакетов, FVM, build_runner), [03-domain-layer.md](03-domain-layer.md) (контракты репозиториев, `RepositoryResult`, `LogRepository`-интерфейс), [04-data-layer.md](04-data-layer.md) (`AppDatabase`, DAO, мапперы, impl-репозиториев, `LogRepositoryImpl`), [06-theming.md](06-theming.md) (`AppRootBloc`, `themeMode`), [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md) (`dart-define-from-file`, SOPS, флейворные сборки Android/iOS), [10-code-templates.md](10-code-templates.md) (готовые регистрационные сниппеты), [12-dev-commands.md](12-dev-commands.md) (команды перегенерации).

---

## 1. Базовый принцип: один пакет, один контейнер, один генератор

В этом блюпринте слои — это **папки внутри одного `lib/`**, а не отдельные Dart-пакеты. Поэтому DI устроен **одноуровнево**:

- **один** `pubspec.yaml`,
- **один** прогон `build_runner`,
- **одна** функция `configureDependencies(String env)`, помеченная `@InjectableInit`,
- **один** сгенерированный файл `configure_dependencies.config.dart`,
- **один** глобальный контейнер `GetIt.instance`.

> ⚠️ **Это сознательно переписывает трёхпакетную схему из исходников.** В `migration_v1` DI был каскадом из трёх функций (`configureDependencies` → `configureDomainDependencies` → `configureDataDependencies`) с тремя `@InjectableInit` (`$initGetIt` / `$initDomainGetIt` / `$initDataGetIt`) и тремя `.config.dart`. **У нас этого нет.** Пути вида `domain/lib/src/...`, `data/lib/src/...`, path-зависимости в `pubspec.yaml` и любой цикл `domain ↔ data` запрещены. Все пути переписаны на `lib/domain/...`, `lib/data/...`, `lib/di/...`. Импорты — всегда полные: `package:speech_ai_mobile/...`.

Направление зависимостей (см. [00-architecture-overview.md](00-architecture-overview.md)) обеспечивается **дисциплиной импортов**, а не границами пакетов:

```
presentation ──► domain ◄── data
                   ▲
                   └── domain не импортирует ничего из data/presentation
```

DI-контейнер при этом плоский: и `presentation`, и `data` регистрируются в одном `GetIt.instance`. `@LazySingleton(as: Interface)` связывает impl из `lib/data/...` с контрактом из `lib/domain/...` — это единственная «точка склейки», и она однонаправленна (impl знает интерфейс, интерфейс не знает impl).

---

## 2. Инструменты: `injectable` + `get_it`

- **`get_it`** — service locator (рантайм-контейнер). Резолв: `getIt<T>()`.
- **`injectable`** — кодогенератор: сканирует аннотации `@injectable` / `@lazySingleton` / `@LazySingleton(...)` / `@Singleton(...)` и эмитит вызовы регистрации в `configure_dependencies.config.dart`.
- **`injectable_generator`** + **`build_runner`** — dev-зависимости, производящие сгенерированный код.

Ты **никогда** не пишешь `getIt.registerLazySingleton<T>(...)` руками для аннотированных классов — это делает генератор. Руками регистрируются только те немногие вещи, которые генератор вывести не может (см. §6 — `PackageInfo`).

Версии пакетов — единственный источник истины — закреплены в [01-stack-and-tooling.md](01-stack-and-tooling.md). Сводка DI-релевантных пакетов (сверять с 01, не дублировать самостоятельно):

```yaml
dependencies:
  get_it: ^9.2.1
  injectable: ^3.0.0
  package_info_plus: ^10.1.0

dev_dependencies:
  build_runner: ^2.15.0
  injectable_generator: ^3.0.2
```

---

## 3. Точка входа DI — `lib/di/configure_dependencies.dart`

Единственная функция с `@InjectableInit`. Имя инициализатора — `$initGetIt` (одно на весь проект, никаких `$initDomainGetIt` / `$initDataGetIt`).

```dart
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:speech_ai_mobile/di/configure_dependencies.config.dart';

final getIt = GetIt.instance;

@InjectableInit(initializerName: r'$initGetIt')
Future<void> configureDependencies(String env) async {
  // 1) Generated registrations for everything annotated across lib/data + lib/presentation,
  //    filtered by the environment string. AppDatabase is selected declaratively here too
  //    (see §5 — three env-scoped providers), so no runtime if-branch.
  getIt.$initGetIt(environment: env);

  // 2) Manual registrations the generator cannot infer (PackageInfo: async on device,
  //    mock under test). Everything else is annotation-driven.
  if (env == Environment.test) {
    PackageInfo.setMockInitialValues(
      appName: 'Speech AI',
      packageName: 'app.speechai.mobile',
      version: '0.0.1',
      buildNumber: '1',
      buildSignature: '',
      installerStore: '',
    );
  } else {
    await GetItHelper(getIt).factoryAsync<PackageInfo>(
      () => PackageInfo.fromPlatform(),
      preResolve: true,
    );
  }
}
```

Ключевые моменты:

- `getIt.$initGetIt(environment: env)` — единственный вызов генератора. `environment` фильтрует регистрации: попадают только классы, чей `env`-список содержит переданную строку.
- `configure_dependencies.config.dart` — **сгенерирован**. Никогда не редактируется руками, исключён из анализа и форматирования (как `*.g.dart` / `*.freezed.dart`), см. [08-conventions-and-constitution.md](08-conventions-and-constitution.md).
- `PackageInfo` (см. §6) — единственная значимая ручная регистрация: на устройстве это async-резолв с `preResolve: true`, под тестом — синхронный мок до запуска чего-либо.
- Никакой ручной регистрации `AppDatabase` здесь нет — она декларативна (§5). Это умышленно отличается от рантайм-`if`-ветки в `migration` (BASE).

### 3.1 DI-окружения (`Environment.dev` / `prod` / `test`)

`injectable` поставляет три строковые константы окружения:

| Константа | Смысл |
|---|---|
| `Environment.dev` | локальные debug-сборки (флейвор `stage`) |
| `Environment.prod` | release-сборки (флейвор `prod`) |
| `Environment.test` | прогоны `flutter_test` |

Только классы, чей `env`-список содержит переданную строку, регистрируются. Это и есть механизм подмены реализаций по окружению — прежде всего env-скоупленной БД (§5).

> **Маппинг флейвор → окружение** (см. §7 и §8): флейвор `prod` → `Environment.prod`; флейвор `stage` → `Environment.dev`. Окружений всего три, кастомных (вроде `CustomEnvironment.ipc` из исходников) **нет** — у мобильного приложения нет IPC/изолятов.

---

## 4. `@InjectableInit` и сгенерированный `.config.dart`

`@InjectableInit(initializerName: r'$initGetIt')` помечает функцию, тело которой генератор заполнит через одноимённый extension-метод. После прогона build_runner рядом появляется `lib/di/configure_dependencies.config.dart`, содержащий:

- extension на `GetIt`, экспонирующий `$initGetIt(...)`;
- по одному вызову `gh.lazySingleton<T>(...)` / `gh.singleton<T>(...)` / `gh.factory<T>(...)` / `gh.singletonAsync<T>(...)` на каждый аннотированный класс, **отфильтрованному по строке `environment`** (env-скоупленные регистрации оборачиваются в `registerFor: {...}`).

`.config.dart` **не редактируется руками** — это артефакт, наравне с `*.g.dart`. Перегенерация — `build_runner build --delete-conflicting-outputs` (см. [12-dev-commands.md](12-dev-commands.md)).

---

## 5. Env-скоупленная `AppDatabase` (декларативный подход)

Локальное хранилище (Sembast) выбирается **по окружению декларативно**: три провайдера, каждый со своим `env`-списком. Генератор зарегистрирует ровно один из них под интерфейс `AppDatabase`. Никакой рантайм-`if`-ветки в `configureDependencies` (это умышленно заменяет подход BASE, где БД регистрировалась через `if (env == Environment.test)`).

Интерфейс и реализации живут в `lib/data/local/` (подробно — в [04-data-layer.md](04-data-layer.md)); здесь — только DI-аспект:

```dart
// lib/data/local/app_database.dart
abstract class AppDatabase {
  Future<Database> get db;
  Future<void> deleteDatabase();
  Future<void> cleanDatabase(); // fans out to every DAO's cleanData() on logout
}
```

```dart
// lib/data/local/app_database_dev.dart
import 'package:injectable/injectable.dart';
import 'package:sembast/sembast_io.dart';

@LazySingleton(as: AppDatabase, env: [Environment.dev])
class AppDatabaseDev implements AppDatabase {
  // databaseFactoryIo — on-disk, getApplicationDocumentsDirectory()
}
```

```dart
// lib/data/local/app_database_prod.dart
import 'package:injectable/injectable.dart';
import 'package:sembast/sembast_io.dart';

@LazySingleton(as: AppDatabase, env: [Environment.prod])
class AppDatabaseProd implements AppDatabase {
  // databaseFactoryIo — on-disk, getApplicationDocumentsDirectory()
}
```

```dart
// lib/data/local/app_database_test.dart
import 'package:injectable/injectable.dart';
import 'package:sembast/sembast_memory.dart';

@LazySingleton(as: AppDatabase, env: [Environment.test])
class AppDatabaseTest implements AppDatabase {
  // databaseFactoryMemory — in-memory, throwaway per test run
}
```

| Провайдер | `env` | Sembast factory |
|---|---|---|
| `AppDatabaseDev` | `[Environment.dev]` | `databaseFactoryIo` (on-disk) |
| `AppDatabaseProd` | `[Environment.prod]` | `databaseFactoryIo` (on-disk) |
| `AppDatabaseTest` | `[Environment.test]` | `databaseFactoryMemory` (in-memory) |

> Почему декларативно, а не `if`: генератор сам подставит верный провайдер по `environment`, контейнер остаётся плоским и предсказуемым, а тест автоматически получает in-memory БД без ручных свопов. `Dev`/`Prod` намеренно разделены (а не схлопнуты в один «не-test»): это оставляет точку для будущих per-env различий (имя файла, путь, шифрование) без правки `configureDependencies`.

> **Локальная БД — Sembast (OQ-1 закрыт).** Env-scoping (dev/prod/test) ортогонален платформе: фабрика выбирается по **платформе** внутри impl — `databaseFactoryIo` (mobile/desktop), `databaseFactoryMemory` (test), а на **web** (будущий клиент) — `databaseFactoryWeb` из `sembast_web`. Абстракция `AppDatabase` и весь DAO/репозиторный слой при этом не меняются — один подход на все платформы. См. [04-data-layer.md](04-data-layer.md) §6.

---

## 6. Паттерны регистрации (аннотации)

Три-четыре аннотации покрывают почти всё. Полные тела классов — в [04-data-layer.md](04-data-layer.md) / [10-code-templates.md](10-code-templates.md); здесь — только аннотации и их семантика.

### 6.1 DAO и мапперы — `@lazySingleton` (без `env`)

DAO и мапперы окружение-независимы: DAO зависит от env-скоупленной `AppDatabase` транзитивно, поэтому собственный `env`-список им не нужен.

```dart
// lib/data/dao/item_dao.dart
import 'package:injectable/injectable.dart';
import 'package:sembast/sembast.dart';

@lazySingleton
class ItemDao {
  ItemDao(this._appDatabase);

  final AppDatabase _appDatabase;
  final _store = stringMapStoreFactory.store('items');

  // create / fetch / list / watch (onSnapshots) / delete / cleanData ...
}
```

```dart
// lib/data/mapper/item_mapper.dart
import 'package:injectable/injectable.dart';
import 'package:speech_ai_mobile/domain/model/item/item_model.dart';

@lazySingleton
class ItemMapper {
  ItemMapper(this._statusConverter);

  final ItemStatusConverter _statusConverter;

  ItemModel toModel({required ItemEntity entity}) => ItemModel(/* ... */);
  ItemEntity toEntity({required ItemModel model}) => ItemEntity(/* ... */);
}
```

> Предпочитай конструкторную инъекцию (`ItemMapper(this._statusConverter)`) lookup'ам `getIt<T>()` в теле методов — зависимости становятся явными и тестируемыми.

### 6.2 Реализация репозитория — `@LazySingleton(as: Interface, env: [...])`

Impl регистрируется **под доменным контрактом** (`as:`) и **обязан** перечислить все рантайм-окружения, потому что транзитивно использует env-скоупленную `AppDatabase`.

```dart
// lib/data/repository/item_repository_impl.dart
import 'package:injectable/injectable.dart';
import 'package:speech_ai_mobile/domain/repository/item_repository.dart';

@LazySingleton(
  as: ItemRepository,
  env: [Environment.dev, Environment.prod, Environment.test],
)
class ItemRepositoryImpl with BaseRepositoryHelper implements ItemRepository {
  ItemRepositoryImpl(this._dao, this._mapper);

  final ItemDao _dao;
  final ItemMapper _mapper;

  // fetchItem / watchItems / getItems (paginated, network-only) / createItem / clean ...
}
```

> ⚠️ **`env`-список — load-bearing (foot-gun!).** Если его опустить, impl зарегистрируется в *нулевом* числе окружений, и `getIt<ItemRepository>()` **бросит на резолве** в рантайме (а не на компиляции — об ошибке узнаешь только при первом обращении). Для **каждого** репозитория всегда указывай полный список `[Environment.dev, Environment.prod, Environment.test]`. Это самая частая причина «зарегистрировал, но не резолвится».

### 6.3 Шпаргалка по аннотациям

| Аннотация | Для чего | `env`-список |
|---|---|---|
| `@lazySingleton` | DAO, мапперы, конвертеры, helper'ы, API-классы | нет (все окружения) |
| `@LazySingleton(as: Interface, env: [...])` | реализации репозиториев | **обязателен** `[dev, prod, test]` |
| `@LazySingleton(as: AppDatabase, env: [<one>])` | env-скоупленные провайдеры БД | **по одному** env на провайдер |
| `@Singleton(env: [Environment.prod, Environment.dev], as: AppConfigModel)` | конфиг-модель флейвора | без `test` (см. §7) |
| `@injectable` | per-resolution фабрики (новый инстанс на каждый `get`) | опционально |

> `LogRepositoryImpl` регистрируется как `@LazySingleton(as: LogRepository)` (см. §9) — без `env`-списка, доступен во всех окружениях, включая `test`.

### 6.4 BLoC и DI

BLoC'и **не** регистрируются в контейнере декларативной аннотацией для прямого `getIt`-резолва ради скоупа экрана — они короткоживущие и создаются на уровне виджета. Внутри `BlocProvider(create: ...)` BLoC резолвит свои зависимости через `getIt<T>()` **напрямую** (а не через глобальные алиасы — §8). Подробнее — [05-presentation-layer.md](05-presentation-layer.md).

---

## 7. Конфигурация и флейворы (изоляция на этапе компиляции)

Флейвор резолвится **на этапе компиляции** из `String.fromEnvironment('app.flavor')`. Никакого рантайм-переключения. Флейвор-специфичные значения приходят через `--dart-define-from-file` (см. [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md)) и читаются через `String.fromEnvironment`.

### 7.1 `AppFlavorType` — `lib/domain/model/app_config/app_flavor_type.dart`

```dart
enum AppFlavorType { prod, stage }
```

### 7.2 `AppFlavor` — `lib/domain/model/app_config/app_flavor.dart`

```dart
import 'package:speech_ai_mobile/domain/model/app_config/app_flavor_type.dart';

class AppFlavor {
  static const String _flavor = String.fromEnvironment('app.flavor');

  static AppFlavorType getFlavor() {
    switch (_flavor) {
      case 'stage':
        return AppFlavorType.stage;
      case 'prod':
      default:
        return AppFlavorType.prod;
    }
  }
}
```

> `default` → `prod` — намеренно: при пустом / неизвестном `app.flavor` приложение деградирует в самый безопасный (production) профиль, а не в stage.

### 7.3 `AppConfigModel` — `lib/domain/model/app_config/app_config_model.dart`

Абстрактный интерфейс + **одна** реализация, читающая каждое значение через `const String.fromEnvironment`. **Per-flavor-подкласса нет** — все различия приходят из dart-define-payload'а. Реализация регистрируется для `prod` и `dev` (не для `test` — под тестом значения мокаются явно или не нужны).

```dart
import 'package:injectable/injectable.dart';

abstract class AppConfigModel {
  String get apiUrl;
  String get apiSignatureKey;
  String get appwriteProjectId;
  String get supportEmail;
  // ... one getter per config value the app needs ...
}

@Singleton(env: [Environment.prod, Environment.dev], as: AppConfigModel)
final class AppConfigModelImpl implements AppConfigModel {
  @override
  String get apiUrl => const String.fromEnvironment('API_URL', defaultValue: '');

  @override
  String get apiSignatureKey => const String.fromEnvironment('API_SIGNATURE_KEY', defaultValue: '');

  @override
  String get appwriteProjectId => const String.fromEnvironment('APPWRITE_PROJECT_ID', defaultValue: '');

  @override
  String get supportEmail => const String.fromEnvironment('SUPPORT_EMAIL', defaultValue: '');
  // ... remaining getters follow the same const String.fromEnvironment pattern ...
}
```

> Enum- и list-типизированные значения парсятся из строкового env (например `FIRST_PARTY_HOSTS`, разбиваемый по `,`; короткий код, маппящийся в enum). Парсинг — внутри геттера, наружу торчит уже типизированное значение.
>
> Первый реальный набор значений (`API_URL`, `API_SIGNATURE_KEY`, `APPWRITE_PROJECT_ID` и т. д.) для stage/prod описан в [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md): источник истины — зашифрованные секреты (SOPS+age+mise), которые `dart-define-from-file` материализует в `.env.<flavor>.json` на этапе сборки.

---

## 8. Глобальные алиасы — `lib/di/global_aliases.dart`

Вручную поддерживаемые top-level **геттеры**, оборачивающие `getIt<T>()` для часто используемых синглтонов. Применяются внутри реализаций репозиториев и API-классов, чтобы не писать `getIt<...>()` каждый раз.

```dart
import 'package:speech_ai_mobile/di/configure_dependencies.dart';
import 'package:speech_ai_mobile/domain/repository/log_repository.dart';
import 'package:speech_ai_mobile/domain/repository/app_config/app_config_repository.dart';
import 'package:speech_ai_mobile/domain/repository/item_repository.dart';

/// repositories
LogRepository get logRepository => getIt<LogRepository>();
AppConfigRepository get configRepository => getIt<AppConfigRepository>();
ItemRepository get itemRepository => getIt<ItemRepository>();

/// mappers
ItemMapper get itemMapper => getIt<ItemMapper>();

/// daos
ItemDao get itemDao => getIt<ItemDao>();

/// apis
GetItemApi get getItemApi => getIt<GetItemApi>();
GetItemsApi get getItemsApi => getIt<GetItemsApi>();
```

Правила:

- **Геттеры, не `final`-поля.** Резолв происходит лениво, после сборки контейнера, а не на этапе импорта (иначе — обращение к незаполненному `GetIt`).
- **Алиасы — для repo / mapper / dao / api.** BLoC'и их **не** используют — BLoC резолвит зависимости через `getIt<T>()` напрямую (см. §6.4 и [05-presentation-layer.md](05-presentation-layer.md)).
- Имя алиаса повторяет смысл: `getItemsApi` (множественное — потому что листинг), `getItemApi` (единичный fetch).

---

## 9. Обязательное логирование — `LogRepository` (единый канал)

В `lib/` **запрещён** сырой `print` / `debugPrint`. Весь вывод идёт через единственный канал — `LogRepository` (интерфейс в `lib/domain/repository/`, реализация в `lib/data/repository/`). Это требование Конституции (см. [08-conventions-and-constitution.md](08-conventions-and-constitution.md)) и предусловие `BaseRepositoryHelper.execute<T>()`, который **всегда** логирует через `LogRepository` (см. [04-data-layer.md](04-data-layer.md)).

### 9.1 Интерфейс — `lib/domain/repository/log_repository.dart`

```dart
abstract class LogRepository {
  void debug({String? target, required String message});

  void error({String? target, required Object error, StackTrace? stackTrace});
}
```

### 9.2 Реализация — `lib/data/repository/log_repository_impl.dart`

```dart
import 'package:injectable/injectable.dart';
import 'package:logger/logger.dart';
import 'package:speech_ai_mobile/domain/repository/log_repository.dart';

@LazySingleton(as: LogRepository)
class LogRepositoryImpl extends LogRepository {
  final _logger = Logger();

  @override
  void debug({String? target, required String message}) {
    _logger.d('${target ?? ''}: $message', time: DateTime.now());
  }

  @override
  void error({String? target, required Object error, StackTrace? stackTrace}) {
    final name = target ?? '';
    _logger.e('$name: $error', error: error, stackTrace: stackTrace, time: DateTime.now());
    // forward to your observability backend here (Sentry / RUM),
    // tagging with {'target': name, 'error.type': error.runtimeType.toString()}.
  }
}
```

Конвенции:

- Реализации репозиториев и API обращаются к логгеру через глобальный алиас `logRepository` (§8).
- Любое перехваченное-и-проглоченное исключение **обязано** нести инлайн-комментарий, почему это безопасно.
- `LogRepositoryImpl` зарегистрирован без `env`-списка → доступен во всех окружениях (включая `test`), что позволяет `BaseRepositoryHelper` логировать и под тестом.

---

## 10. `main.dart` — последовательность запуска

Точный порядок: привязка Flutter → `runZonedGuarded` → резолв флейвора → `await configureDependencies(env)` → `await getIt.allReady()` → инициализация конфиг-репозитория → `runApp(AppRoot())`. Маппинг флейвор → окружение: `prod` → `Environment.prod`, `stage` → `Environment.dev`.

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:speech_ai_mobile/di/configure_dependencies.dart';
import 'package:speech_ai_mobile/domain/model/app_config/app_flavor.dart';
import 'package:speech_ai_mobile/domain/model/app_config/app_flavor_type.dart';
import 'package:speech_ai_mobile/domain/repository/app_config/app_config_repository.dart';
import 'package:speech_ai_mobile/domain/repository/log_repository.dart';
import 'package:speech_ai_mobile/presentation/app/app_root.dart';

void main() {
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // 1) Resolve flavor at compile time, map flavor -> DI environment.
      final flavor = AppFlavor.getFlavor();
      final env = flavor == AppFlavorType.prod ? Environment.prod : Environment.dev;

      // 2) Build the container (+ lock orientation in parallel), then await async pre-resolves.
      await Future.wait<dynamic>([
        configureDependencies(env),
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
      ]);
      await getIt.allReady(); // resolve any preResolve: true async registrations (PackageInfo)

      // 3) Initialize the config/observability repository with the resolved flavor.
      final configRepository = getIt<AppConfigRepository>();
      await configRepository.initialize(flavorType: flavor);

      // 4) Go.
      runApp(const AppRoot());
    },
    (error, stack) {
      // Last-resort guard: anything uncaught above the widget tree lands here.
      // Route through the single log channel if DI is up; never print.
      if (getIt.isRegistered<LogRepository>()) {
        getIt<LogRepository>().error(target: 'main', error: error, stackTrace: stack);
      }
    },
  );
}
```

Разбор шагов:

1. **`WidgetsFlutterBinding.ensureInitialized()`** — обязателен до любого обращения к платформенным каналам (ориентация, `PackageInfo`, `path_provider`).
2. **`AppFlavor.getFlavor()` + маппинг** — единственное место, где флейвор превращается в DI-окружение (`prod` → `Environment.prod`, `stage` → `Environment.dev`).
3. **`Future.wait([configureDependencies(env), setPreferredOrientations(...)])`** — сборка контейнера и блокировка ориентации идут параллельно (независимы).
4. **`getIt.allReady()`** — блокирует до завершения всех `preResolve: true` async-регистраций (например, `PackageInfo.fromPlatform()` из §6). Без него `getIt<PackageInfo>()` мог бы бросить «not ready».
5. **`configRepository.initialize(flavorType: flavor)`** — поднимает конфиг/обсёрвабилити-репозиторий (например, инициализация Sentry-сообщений, чтение Remote Config-подобных значений) уже после готового контейнера.
6. **`runApp(AppRoot())`** — корневой виджет. `AppRoot` поднимает `AppRootBloc` (тема: light/dark + `themeMode`) — см. [06-theming.md](06-theming.md).
7. **`runZonedGuarded`** — внешний guard: всё непойманное над деревом виджетов попадает в callback ошибки и роутится через единственный лог-канал.

> **Об ошибках BLoC и логировании.** Отдельного BLoC-обсёрвера в проекте **нет**. Логирование ошибок уже происходит на уровне репозиториев через обязательный `LogRepository` (`BaseRepositoryHelper.execute` всегда логирует — см. [04-data-layer.md](04-data-layer.md)), а ошибки в обработчиках BLoC оборачиваются `BaseBloc.executeLogic` (см. [05-presentation-layer.md](05-presentation-layer.md)) — поэтому отдельный BLoC-обсёрвер не нужен.

> `PackageInfo` (версия/билд приложения) резолвится здесь же через `getIt.allReady()`. Версионирование — CalVer + сдвинутая эпоха (`YY.M.D+EPOCH`), см. [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md).

---

## 11. Bootstrap под тесты

Тесты переиспользуют **ту же** точку входа `configureDependencies` с `Environment.test`, затем перекрывают конкретные типы моками. Полная обвязка (`flutter_test_config.dart` + утилиты) — в [12-dev-commands.md](12-dev-commands.md); эскиз:

```dart
// test/utils/tests_utils.dart (sketch)
Future<void> initializeMock() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetIt.instance.reset();

  await configureDependencies(Environment.test);
  GetIt.instance.allowReassignment = true;
  await GetIt.instance.allReady();

  // Post-register test doubles over real registrations.
  GetIt.instance.registerSingleton<ItemRepository>(MockItemRepository());
}
```

- `Environment.test` заставляет `$initGetIt` выбрать `AppDatabaseTest` (in-memory) автоматически — без ручного свопа БД.
- `PackageInfo.setMockInitialValues(...)` срабатывает в ветке `test` внутри `configureDependencies` (§3) — мок версии до запуска чего-либо.
- `allowReassignment = true` разрешает перекрытие реальных регистраций test-double'ами после прогона цепочки.

---

## 12. Перегенерация DI (build_runner)

При **любом** добавлении/удалении аннотации или изменении сигнатуры конструктора аннотированного класса нужно перегенерировать `configure_dependencies.config.dart`. Поскольку пакет **один**, прогон тоже **один** (никаких трёх per-package прогонов из исходников):

```bash
fvm dart run build_runner build --delete-conflicting-outputs
```

Тот же прогон обновляет `*.freezed.dart` (Freezed-модели и BLoC-State/Event) и `*.g.dart` (JSON-сериализация энтити). Команды и удобные обёртки — в [12-dev-commands.md](12-dev-commands.md).

---

## Чеклист

- [ ] Один `lib/di/configure_dependencies.dart` с **единственным** `@InjectableInit(initializerName: r'$initGetIt')`, вызывающим `getIt.$initGetIt(environment: env)`.
- [ ] Никаких трёх `configure*Dependencies` / `$initDomainGetIt` / `$initDataGetIt` / path-зависимостей — пакет один, контейнер плоский, импорты `package:speech_ai_mobile/...`.
- [ ] Окружения только `Environment.dev` / `prod` / `test`; кастомных нет.
- [ ] `AppDatabase` — три env-скоупленных провайдера (`AppDatabaseDev`/`Prod`/`Test`), `@LazySingleton(as: AppDatabase, env: [<one>])`, **по одному** env на провайдер; Dev/Prod = `databaseFactoryIo`, Test = `databaseFactoryMemory`. Никакой рантайм-`if`-ветки.
- [ ] DAO и мапперы — `@lazySingleton` (без `env`).
- [ ] Реализации репозиториев — `@LazySingleton(as: <Feature>Repository, env: [Environment.dev, Environment.prod, Environment.test])`; **env-список не забыт** (иначе резолв бросает в рантайме).
- [ ] `AppFlavorType{prod, stage}` + `AppFlavor.getFlavor()` (compile-time, `String.fromEnvironment('app.flavor')`, `default → prod`).
- [ ] `AppConfigModel` интерфейс + **одна** `@Singleton(env: [Environment.prod, Environment.dev], as: AppConfigModel)` реализация, читающая `const String.fromEnvironment` (без per-flavor-подкласса).
- [ ] `LogRepository` интерфейс (`lib/domain/repository/`) + `@LazySingleton(as: LogRepository)` impl (`lib/data/repository/`); в `lib/` нет сырого `print`/`debugPrint`.
- [ ] `PackageInfo`: async `preResolve: true` вне теста, `setMockInitialValues` под тестом.
- [ ] `global_aliases.dart` — top-level **геттеры** (не `final`) для repo/mapper/dao/api; BLoC'и зовут `getIt<T>()` напрямую.
- [ ] `main.dart`: `ensureInitialized` → `runZonedGuarded(...)` → `AppFlavor.getFlavor` → `await configureDependencies(env)` → `await getIt.allReady()` → `configRepository.initialize(flavorType)` → `runApp(AppRoot)`; маппинг `prod→prod`, `stage→dev`.
- [ ] Один прогон `build_runner build --delete-conflicting-outputs` после любой правки аннотации/конструктора; `.config.dart` никогда не редактируется руками.
