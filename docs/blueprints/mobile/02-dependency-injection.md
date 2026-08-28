# 02 — Внедрение зависимостей и bootstrap

> **Назначение:** задать единственно верный способ собрать DI-контейнер приложения NOX — один `get_it` + `injectable` поверх **одного** Dart-пакета `nox_app`, плюс детерминированную последовательность запуска (`main.dart`), флейворы, конфигурацию, локальную БД и обязательное логирование. **Когда читать:** при первичной настройке проекта, при добавлении нового репозитория / DAO / маппера / API, при отладке «почему `getIt<T>()` бросает на резолве», при правке последовательности bootstrap или флейворов. **Связанные документы:** [00-architecture-overview.md](00-architecture-overview.md) (границы слоёв и направление зависимостей), [01-stack-and-tooling.md](01-stack-and-tooling.md) (версии пакетов, FVM, build_runner), [03-domain-layer.md](03-domain-layer.md) (контракты репозиториев, `RepositoryResult`, `LogRepository`-интерфейс), [04-data-layer.md](04-data-layer.md) (`AppDatabase`, DAO, мапперы, impl-репозиториев, `LoggerLogRepository`), [06-theming.md](06-theming.md) (`AppRootBloc`, `themeMode`), [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md) (`dart-define-from-file`, SOPS, флейворные сборки на всех пяти платформах: iOS/Android/Windows/Linux/macOS), [10-code-templates.md](10-code-templates.md) (готовые регистрационные сниппеты), [12-dev-commands.md](12-dev-commands.md) (команды перегенерации).

---

## 1. Базовый принцип: один пакет, один контейнер, один генератор

В этом блюпринте слои — это **папки внутри одного `lib/`**, а не отдельные Dart-пакеты. Поэтому DI устроен **одноуровнево**:

- **один** `pubspec.yaml`,
- **один** прогон `build_runner`,
- **одна** функция `configureDependencies(String env)`, помеченная `@InjectableInit`,
- **один** сгенерированный файл `configure_dependencies.config.dart`,
- **один** глобальный контейнер `GetIt.instance`.

> ⚠️ **Правило блюпринта: трёхпакетной DI-схемы у нас нет.** Запрещён каскад из трёх функций (`configureDependencies` → `configureDomainDependencies` → `configureDataDependencies`) с тремя `@InjectableInit` (`$initGetIt` / `$initDomainGetIt` / `$initDataGetIt`) и тремя `.config.dart`. Пути вида `domain/lib/src/...`, `data/lib/src/...`, path-зависимости в `pubspec.yaml` и любой цикл `domain ↔ data` запрещены. Все пути — `lib/domain/...`, `lib/data/...`, `lib/di/...`. Импорты — всегда полные: `package:nox_app/...`.

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

Ты **никогда** не пишешь `getIt.registerLazySingleton<T>(...)` руками для аннотированных классов — это делает генератор. Сторонние синглтоны, которые генератор вывести из аннотации на классе не может, объявлены декларативно в `@module`-классе `RegisterModule` (`lib/di/register_module.dart`): `FlutterSecureStorage` (`@lazySingleton`), `SharedPreferences` (`@preResolve` — async-резолв, который ждёт `getIt.allReady()`, см. §10) и env-ключевой `@Named('isTestEnvironment') bool`. Полностью ручных вызовов регистрации в теле `configureDependencies` сегодня нет (см. §3).

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

В **фактическом коде** файл минимален — единственный (и обязательно **await**-нутый) вызов генератора, никаких ручных регистраций:

```dart
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.config.dart';

final getIt = GetIt.instance;

/// Single DI entry point for the whole package. `env` selects the registration
/// environment (Environment.dev / .prod / .test).
@InjectableInit(initializerName: r'$initGetIt')
Future<void> configureDependencies(String env) async {
  // Awaited: with a `@preResolve` dependency (SharedPreferences) the generated
  // `$initGetIt` is async, so registration only completes once it is awaited.
  await getIt.$initGetIt(environment: env);
}
```

> **Фактическое состояние vs целевой паттерн.** Тело — только `await getIt.$initGetIt(environment: env)`; всё остальное аннотационно-управляемо (включая выбор `AppDatabase` по окружению, §5, и сторонние синглтоны через `@module RegisterModule`, §2). Из-за `@preResolve`-`SharedPreferences` в `RegisterModule` сгенерированный `$initGetIt` **асинхронный** — без `await` контейнер уедет в `runApp` недособранным. Ниже — целевая форма для того редкого случая, который `@module` не покрывает: ручная регистрация с рантайм-веткой по окружению. `PackageInfo` намеренно **вне DI** — `AppVersionTextWidget` зовёт `PackageInfo.fromPlatform()` прямо из `FutureBuilder`, так что этой ветки в коде нет.

Целевая форма (прескриптивный паттерн, **в коде отсутствует** — добавляется при появлении первого потребителя, которому нужна ручная env-ветка):

```dart
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:nox_app/di/configure_dependencies.config.dart';

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
      appName: 'NOX',
      packageName: 'com.cyphernetlabs.noxapp',
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

- `await getIt.$initGetIt(environment: env)` — единственный вызов генератора. `environment` фильтрует регистрации: попадают только классы, чей `env`-список содержит переданную строку.
- `configure_dependencies.config.dart` — **сгенерирован**. Никогда не редактируется руками, исключён из анализа и форматирования (как `*.g.dart` / `*.freezed.dart`), см. [08-conventions-and-constitution.md](08-conventions-and-constitution.md).
- `PackageInfo` (в целевой форме) — пример значимой ручной регистрации: на устройстве async-резолв с `preResolve: true`, под тестом — синхронный мок до запуска чего-либо. В коде его нет: `getIt<PackageInfo>()` нигде не резолвится, версия читается напрямую в `AppVersionTextWidget`. Async-pre-resolve при этом уже реальный — `@preResolve`-`SharedPreferences` из `RegisterModule`, поэтому `getIt.allReady()` в `main.dart` делает настоящую работу (см. §10).
- Никакой ручной регистрации `AppDatabase` здесь нет — она декларативна (§5). Рантайм-`if`-ветки для выбора БД быть не должно.

### 3.1 DI-окружения (`Environment.dev` / `prod` / `test`)

`injectable` поставляет три строковые константы окружения:

| Константа | Смысл |
|---|---|
| `Environment.dev` | локальные debug-сборки (флейвор `stage`) |
| `Environment.prod` | release-сборки (флейвор `prod`) |
| `Environment.test` | прогоны `flutter_test` |

Только классы, чей `env`-список содержит переданную строку, регистрируются. Это и есть механизм подмены реализаций по окружению. Сегодня env-скоуп реально разделяет две абстракции: `AppDatabase` (§5) и `ConnectivityService` (`ConnectivityServiceImpl` для `[dev, prod]`, `MockConnectivityService` для `[test]` — плагину нужен platform channel, которого под `flutter_test` нет). Любой новый сервис поверх платформенного плагина обязан следовать той же схеме, иначе widget/BLoC-тесты падают на резолве.

> **Маппинг флейвор → окружение** (см. §7 и §8): флейвор `prod` → `Environment.prod`; флейвор `stage` → `Environment.dev`. Окружений всего три, кастомных (вроде `CustomEnvironment.ipc`) **нет** — у клиента NOX нет IPC/изолятов.

---

## 4. `@InjectableInit` и сгенерированный `.config.dart`

`@InjectableInit(initializerName: r'$initGetIt')` помечает функцию, тело которой генератор заполнит через одноимённый extension-метод. После прогона build_runner рядом появляется `lib/di/configure_dependencies.config.dart`, содержащий:

- extension на `GetIt`, экспонирующий `$initGetIt(...)`;
- по одному вызову `gh.lazySingleton<T>(...)` / `gh.singleton<T>(...)` / `gh.factory<T>(...)` / `gh.singletonAsync<T>(...)` на каждый аннотированный класс, **отфильтрованному по строке `environment`** (env-скоупленные регистрации оборачиваются в `registerFor: {...}`).

`.config.dart` **не редактируется руками** — это артефакт, наравне с `*.g.dart`. Перегенерация — `build_runner build --delete-conflicting-outputs` (см. [12-dev-commands.md](12-dev-commands.md)).

---

## 5. Env-скоупленная `AppDatabase` (декларативный подход)

Локальное хранилище (Sembast) выбирается **по окружению декларативно**: три провайдера, каждый со своим `env`-списком. Генератор зарегистрирует ровно один из них под интерфейс `AppDatabase`. Никакой рантайм-`if`-ветки в `configureDependencies` (правило блюпринта: БД не регистрируется через `if (env == Environment.test)`).

Интерфейс и все три реализации живут в **одном** файле `lib/data/local/app_database.dart` (подробно — в [04-data-layer.md](04-data-layer.md)); здесь — только DI-аспект. Фактический интерфейс — два метода:

```dart
// lib/data/local/app_database.dart
abstract class AppDatabase {
  Future<Database> get db;

  Future<void> clearEntireDatabase();
}
```

> `AppDatabase` несёт ровно эти две операции (`db`-геттер + `clearEntireDatabase()`, удаляющий файл БД и сбрасывающий кэш-инстанс). Логаут-fan-out **не** оркестрируется через `AppDatabase`: `cleanData()` есть у каждого DAO (`ChatDao`, `MessageDao`, `SyncDao`, `ItemDao`), а вызывает их `AuthRepositoryImpl.logout` через репозитории — сначала `SyncRepository.clear()` (курсор идёт первым), затем `ChatRepository.clean()` и `MessageRepository.clean()`. Файл БД при этом не удаляется. См. [04-data-layer.md](04-data-layer.md) §6.

```dart
// lib/data/local/app_database.dart (same file, dev provider)
import 'package:injectable/injectable.dart';
import 'package:sembast/sembast_io.dart';

@LazySingleton(as: AppDatabase, env: [Environment.dev])
class AppDatabaseDev implements AppDatabase {
  // databaseFactoryIo — on-disk, getApplicationDocumentsDirectory()
}
```

```dart
// lib/data/local/app_database.dart (same file, prod provider)
import 'package:injectable/injectable.dart';
import 'package:sembast/sembast_io.dart';

@LazySingleton(as: AppDatabase, env: [Environment.prod])
class AppDatabaseProd implements AppDatabase {
  // databaseFactoryIo — on-disk, getApplicationDocumentsDirectory()
}
```

```dart
// lib/data/local/app_database.dart (same file, test provider)
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

> Почему декларативно, а не `if`: генератор сам подставит верный провайдер по `environment`, контейнер остаётся плоским и предсказуемым, а тест автоматически получает in-memory БД без ручных свопов. `Dev`/`Prod` намеренно разделены (а не схлопнуты в один «не-test»): это уже даёт per-env различия без правки `configureDependencies` — каждый провайдер открывает свой файл (`app.db` для prod, `app_dev.db` для dev, `app_test.db` in-memory для test) и оставляет точку для будущих расширений (путь, шифрование).

> **Локальная БД — Sembast (OQ-1 закрыт).** Env-scoping (dev/prod/test) ортогонален платформе: фабрика выбирается по **платформе** внутри impl — `databaseFactoryIo` (mobile/desktop), `databaseFactoryMemory` (test); web у NOX **вне скоупа** (пять целей: iOS/Android/Windows/Linux/macOS), и если он когда-нибудь появится — это `databaseFactoryWeb` из `sembast_web`. Абстракция `AppDatabase` и весь DAO/репозиторный слой при этом не меняются — один подход на все платформы. См. [04-data-layer.md](04-data-layer.md) §6.

---

## 6. Паттерны регистрации (аннотации)

Три-четыре аннотации покрывают почти всё. Полные тела классов — в [04-data-layer.md](04-data-layer.md) / [10-code-templates.md](10-code-templates.md); здесь — только аннотации и их семантика.

### 6.1 DAO и мапперы — `@lazySingleton` (без `env`)

DAO и мапперы окружение-независимы: DAO зависит от env-скоупленной `AppDatabase` транзитивно, поэтому собственный `env`-список им не нужен.

```dart
// lib/data/local/item/item_dao.dart
import 'package:injectable/injectable.dart';
import 'package:sembast/sembast.dart';

@lazySingleton
class ItemDao {
  ItemDao(this._appDatabase);

  final AppDatabase _appDatabase;
  final _store = stringMapStoreFactory.store('items');

  // watch (onSnapshots) / getData / getById / saveData / upsert / removeById / cleanData ...
}
```

> `ItemDao` — референсная реактивная кэш-первичная (cache-first) ветка (`watch()` по `onSnapshots`). Он **намеренно заморожен вместе со всем verification-слайсом `Item`**: в network-only `Item`-репозиторий (§6.2) он не подключён и в продакшн-коде не резолвится (единственная ссылка — его собственный тест). Живые cache-first DAO продуктовых фич — `ChatDao`, `MessageDao` и `SyncDao` (`lib/data/local/chat/`, `lib/data/local/sync/`), зарегистрированные тем же `@lazySingleton` без `env`. Полное тело — в [04-data-layer.md](04-data-layer.md) §6.

```dart
// lib/data/mapper/item/item_mapper.dart
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/item/item_entity.dart';
import 'package:nox_app/data/mapper/base_mapper.dart';
import 'package:nox_app/domain/model/item/item_model.dart';

@lazySingleton
class ItemMapper extends BaseMapper<ItemEntity, ItemModel, dynamic, dynamic> {
  @override
  ItemModel toModel({required ItemEntity entity, dynamic Function(dynamic entity)? ad}) => ItemModel(/* ... */);

  @override
  ItemEntity toEntity({required ItemModel model, dynamic Function(dynamic entity)? ad}) => ItemEntity(/* ... */);
}
```

> `ItemMapper extends BaseMapper<ItemEntity, ItemModel, dynamic, dynamic>` — 4-параметрическая форма (`AdResult`/`AdParam` = `dynamic` для простых мапперов). У `ItemMapper` **нет конструкторных зависимостей** (no-arg ctor): коэрция `String↔enum` / `String↔DateTime` выполняется инлайн в `toModel`/`toEntity` (например `ItemStatus.values.firstWhere(...)`), без инъектируемого конвертера. Когда маппер действительно зависит от другого маппера/конвертера — предпочитай конструкторную инъекцию lookup'ам `getIt<T>()` в теле методов. Полное тело и `BaseMapper`-контракт — в [04-data-layer.md](04-data-layer.md) §4.

### 6.2 Реализация репозитория — `@LazySingleton(as: Interface, env: [...])`

Impl регистрируется **под доменным контрактом** (`as:`) и **обязан** перечислить все рантайм-окружения, потому что транзитивно использует env-скоупленную `AppDatabase`.

```dart
// lib/data/repository/item/item_repository_impl.dart
import 'package:injectable/injectable.dart';
import 'package:nox_app/domain/repository/item/item_repository.dart';

@LazySingleton(as: ItemRepository, env: [Environment.dev, Environment.prod, Environment.test])
class ItemRepositoryImpl with BaseRepositoryHelper implements ItemRepository {
  ItemRepositoryImpl(this._itemMapper, this._itemRemote);

  final ItemMapper _itemMapper;
  final ItemRemoteDataSource _itemRemote;

  // getItems (paginated, network-only) / clean ...
}
```

> `Item`-репозиторий **network-only** (carve-out для серверных пагинированных списков, см. [04-data-layer.md](04-data-layer.md)): он инъектит `ItemMapper` + **`ItemRemoteDataSource`** (интерфейс сетевого источника, feature 016), а **не** `ItemDao` и не конкретный API-класс, и экспонирует только `getItems(...)` + `clean()`. Это verification-слайс, **намеренно замороженный**: его wire-обёртка `ItemsEntity{items, page, page_size, total}` и путь `v1/items` внутри `GetItemsApi` — пример offset-пагинации, а не канон NOX. Продуктовый канон другой: репозиторий сворачивает ответ в `PageMetadata(hasMore:, nextPage:)` — **поля `total` в `PageMetadata` нет вовсе**, сервер тоталов на провод не отдаёт. `nextPage` вычисляется на клиенте и **только на paged-пути** (чаты: `page`/`page_size` → `{chats, has_more}`, формула `hasMore ? entity.page + 1 : null`); курсорный путь сообщений (`before_seq`/`limit` → `{messages, has_more}`) оставляет `nextPage` равным `null` и двигается по `before_seq`. Продуктовые репозитории (чаты/сообщения) — cache-first поверх `ChatDao`/`MessageDao`, см. [04-data-layer.md](04-data-layer.md). Логирование — через миксин `BaseRepositoryHelper` (отдельного поля `LogRepository` в репозитории нет).

> **Сетевые источники — та же аннотация, и это точка флипа на реальный бэкенд.** Каждый `*RemoteDataSource` — доменно-нейтральный интерфейс в `lib/data/remote/datasource/`, а реализация регистрируется под ним: сегодня это моки `MockChatRemoteDataSource` / `MockMessageRemoteDataSource` / `MockItemRemoteDataSource` из `datasource/mock/`, связанные как `@LazySingleton(as: <X>RemoteDataSource, env: [Environment.dev, Environment.prod, Environment.test])` (`prod` включён, потому что prod-флейвор поднимает `Environment.prod`, а реальной реализации ещё нет). Бэкенд выбран и стадия 1 сервера уже смёржена (Go-сервер `noxd` в `client_backend/`, контракт v0), поэтому флип — не гипотеза, а запланированная фаза 028 из трёх шагов: добавить `Real*RemoteDataSource` для `[Environment.prod]`, сузить мок до `[dev, test]`, прогнать `make generate`. Репозитории, DAO, мапперы и UI при этом не меняются — см. `specs/016-remote-datasource-seam/contracts/di-binding.md`.

> ⚠️ **`env`-список — load-bearing (foot-gun!).** Если его опустить, impl зарегистрируется в *нулевом* числе окружений, и `getIt<ItemRepository>()` **бросит на резолве** в рантайме (а не на компиляции — об ошибке узнаешь только при первом обращении). Для **каждого** репозитория всегда указывай полный список `[Environment.dev, Environment.prod, Environment.test]`. Это самая частая причина «зарегистрировал, но не резолвится».

### 6.3 Шпаргалка по аннотациям

| Аннотация | Для чего | `env`-список |
|---|---|---|
| `@lazySingleton` | DAO, мапперы, конвертеры, helper'ы, API-классы | нет (все окружения) |
| `@LazySingleton(as: Interface, env: [...])` | реализации репозиториев | **обязателен** `[dev, prod, test]` |
| `@LazySingleton(as: <X>RemoteDataSource, env: [...])` | сетевые источники: мок сейчас, `Real*` при флипе (фаза 028) | мок `[dev, prod, test]`; после флипа `Real*` → `[prod]`, мок → `[dev, test]` |
| `@LazySingleton(as: AppDatabase, env: [<one>])` | env-скоупленные провайдеры БД | **по одному** env на провайдер |
| `@LazySingleton(as: AppConfigRepository, env: [...])` | конфиг-репозиторий флейвора (`AppConfigRepositoryImpl`) | `[dev, prod, test]` (см. §7) |
| `@injectable` | per-resolution фабрики (новый инстанс на каждый `get`) | опционально |

> `LoggerLogRepository` регистрируется как `@LazySingleton(as: LogRepository)` (см. §9) — без `env`-списка, доступен во всех окружениях, включая `test`. Аналогично `AppConfigRepositoryImpl` зарегистрирован под всеми тремя окружениями (`env: [dev, prod, test]`) — он не зависит от внешнего конфиг-источника и нужен под тестом тоже.

### 6.4 BLoC и DI

BLoC'и **не** регистрируются в контейнере декларативной аннотацией для прямого `getIt`-резолва ради скоупа экрана — они короткоживущие и создаются на уровне виджета. Внутри `BlocProvider(create: ...)` BLoC резолвит свои зависимости через `getIt<T>()` **напрямую** — кроме тех кросс-каттинговых синглтонов, у которых уже есть глобальный алиас (§8): `logRepository`, `authRepository`, `chatRepository` и т. п. зовутся через алиас. Подробнее — [05-presentation-layer.md](05-presentation-layer.md).

---

## 7. Конфигурация и флейворы (изоляция на этапе компиляции)

Флейвор резолвится **на этапе компиляции** из `String.fromEnvironment('app.flavor')`. Никакого рантайм-переключения. Флейвор-специфичные значения приходят через `--dart-define-from-file` (см. [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md)) и читаются через `String.fromEnvironment`.

### 7.1 `AppFlavorType` — `lib/domain/model/app_config/app_flavor_type.dart`

```dart
enum AppFlavorType { prod, stage }
```

### 7.2 `AppFlavor` — `lib/domain/model/app_config/app_flavor.dart`

```dart
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';

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

### 7.3 Конфиг-модель и конфиг-репозиторий — `lib/domain/model/app_config/` + `lib/data/repository/app_config/`

**Фактический код.** Доменная модель `AppConfig` пока минимальна — флейвор плюс **nullable `apiUrl`**; `AppConfigRepositoryImpl` строит её в `initialize(...)`, оставляя `apiUrl` равным `null` (приложение работает на моках и реальных запросов не строит), и дополнительно держит хендшейк-лимиты (`ServerLimits`, дефолты контракта до живого hello) и read-only-доступ к токену. Собственных `const String.fromEnvironment`-геттеров конфига ещё нет, и это **не** из-за неопределённости с сервером: бэкенд и провод **выбраны** (Go-сервер `noxd` в `client_backend/`, контракт v0, транспорт — WebSocket поверх `wss:443` с пиннингом ключа). Per-флейворный URL приезжает вместе с транспортом (фаза 027), а источник токена — со стадией 2 контракта (аутентификация; стадия 1 сервера работает без неё).

```dart
// lib/domain/model/app_config/app_config.dart
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';

/// Flavor-dependent runtime config. Carries the flavor and a nullable [apiUrl]
/// (`null` means no real requests are built this phase — the contract-v0 endpoint
/// lands with the transport, feature 027). The token source is wired via
/// [AppConfigRepository] (stage-2 auth; stage 1 runs without it).
class AppConfig {
  const AppConfig({required this.flavor, this.apiUrl});

  final AppFlavorType flavor;

  final String? apiUrl;
}
```

```dart
// lib/data/repository/app_config/app_config_repository_impl.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/domain/model/app_config/app_config.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';
import 'package:nox_app/domain/model/app_config/server_limits.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';

@LazySingleton(as: AppConfigRepository, env: [Environment.dev, Environment.prod, Environment.test])
class AppConfigRepositoryImpl implements AppConfigRepository {
  AppConfigRepositoryImpl(this._secureStorage, @Named('isTestEnvironment') this._isTestEnvironment);

  final FlutterSecureStorage _secureStorage;
  final bool _isTestEnvironment;

  AppConfig? _config;

  /// Handshake limits: contract defaults until the transport (027) stores a live hello.
  ServerLimits _limits = ServerLimits.contractDefaults;

  static const String _kAuthIdToken = 'auth_id_token';

  @override
  Future<void> initialize({required AppFlavorType flavorType}) async {
    // apiUrl stays null while the app runs on mocks; the per-flavor URL lands
    // with the transport (027), the token bootstrap with stage-2 auth.
    _config = AppConfig(flavor: flavorType);
  }

  @override
  AppConfig get config => _config ?? (throw StateError('AppConfigRepository.initialize was not called'));

  @override
  Future<String?> getUserAuthIdToken() async {
    // Trimmed so a blank/whitespace-only stored value reads as absent (null).
    final token = (await _secureStorage.read(key: _kAuthIdToken))?.trim();
    return (token == null || token.isEmpty) ? null : token;
  }

  // limits / updateLimits(ServerLimits) / isTestEnvironment ...
}
```

> `AppConfigRepositoryImpl` зарегистрирован под всеми тремя окружениями (`env: [dev, prod, test]`). Конструкторные зависимости у него есть — `FlutterSecureStorage` и env-ключевой `@Named('isTestEnvironment') bool`, оба из `RegisterModule` (§2), — но внешнего конфиг-источника среди них нет: флейвор задаётся вызовом `initialize(flavorType:)` из `main.dart` (§10). До вызова `initialize` геттер `config` бросает `StateError`. Под тестом репозиторий резолвится без ручных моков (обе зависимости приходят из `RegisterModule`, а secure storage подменён in-memory-бэкендом из `flutter_test_config.dart`) — отдельной test-конфиг-модели регистрировать не нужно.

**Целевая форма (набор полей — пример/TBD).** Сервер и провод зафиксированы (Go-сервер `noxd`, контракт v0), а вот **per-флейворный payload сборки — ещё нет**. Когда приедут транспорт (фаза 027) и стадия 2 (аутентификация), тот же тип `AppConfig` обрастёт дополнительными полями (реальный `apiUrl` вместо `null`, источник токена, материал пиннинга и т. п.), а `AppConfigRepositoryImpl.initialize(...)` будет заполнять их из dart-define-payload'а (`const String.fromEnvironment`). **Per-flavor-подкласса нет** — все различия приходят из payload'а флейвора. Тип-носитель — **`AppConfig`** (плоский value-object), а не отдельная «конфиг-модель»; контракт чтения остаётся прежним (`AppConfigRepository.config`). Имена полей ниже — **пример/TBD** (заменить на реальные ключи сборки, когда они будут зафиксированы); сегодня `AppConfig` несёт `flavor` и `apiUrl`, причём `apiUrl` пока всегда `null`.

```dart
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';

/// Flavor-dependent runtime config. TODAY this carries `flavor` plus a nullable
/// `apiUrl` (see the shipped code above). The fields below are example/TBD build
/// keys, added once the per-flavor payload is fixed — they are NOT shipped yet.
class AppConfig {
  const AppConfig({
    required this.flavor,
    this.apiUrl,
    // ── example/TBD target fields (per-flavor build payload not fixed yet) ──
    // required this.apiSignatureKey,
    // required this.backendProjectId,
    // required this.supportEmail,
  });

  final AppFlavorType flavor;

  final String? apiUrl;

  // ── example/TBD target fields (per-flavor build payload not fixed yet) ──
  // final String apiSignatureKey; // example/TBD (request signing key)
  // final String backendProjectId;// example/TBD
  // final String supportEmail;    // example/TBD
}
```

```dart
import 'package:injectable/injectable.dart';
import 'package:nox_app/domain/model/app_config/app_config.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';

@LazySingleton(as: AppConfigRepository, env: [Environment.dev, Environment.prod, Environment.test])
class AppConfigRepositoryImpl implements AppConfigRepository {
  // Shipped ctor deps stay as-is (secure storage + the isTestEnvironment flag) — see above.

  AppConfig? _config;

  @override
  Future<void> initialize({required AppFlavorType flavorType}) async {
    _config = AppConfig(
      flavor: flavorType,
      // ── example/TBD: read each target field from the dart-define payload once the per-flavor build keys are fixed ──
      // apiUrl: const String.fromEnvironment('API_URL', defaultValue: ''), // today: left null (mocks)
      // apiSignatureKey: const String.fromEnvironment('API_SIGNATURE_KEY', defaultValue: ''),
      // backendProjectId: const String.fromEnvironment('BACKEND_PROJECT_ID', defaultValue: ''),
      // supportEmail: const String.fromEnvironment('SUPPORT_EMAIL', defaultValue: ''),
    );
  }

  @override
  AppConfig get config => _config ?? (throw StateError('AppConfigRepository.initialize was not called'));
}
```

> Enum- и list-типизированные значения парсятся из строкового env (например `FIRST_PARTY_HOSTS`, разбиваемый по `,`; короткий код, маппящийся в enum) **внутри `initialize`**, а в `AppConfig` кладётся уже типизированное значение. Регистрация и контракт неизменны: `@LazySingleton(as: AppConfigRepository, env: [dev, prod, test])`, чтение через `AppConfigRepository.config` — добавляются только новые поля `AppConfig`.
>
> Реальный набор значений (`API_URL`, `API_SIGNATURE_KEY`, идентификатор проекта бэкенда и т. д. — **имена ключей пример/TBD**: сервер и контракт v0 зафиксированы, а per-флейворный набор dart-define-ключей ещё нет) для stage/prod описан в [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md): источник истины — зашифрованные секреты (SOPS+age+mise), которые `dart-define-from-file` материализует в `.env.<flavor>.json` на этапе сборки.

---

## 8. Глобальные алиасы — `lib/di/global_aliases.dart`

Вручную поддерживаемые top-level **геттеры**, оборачивающие `getIt<T>()` для часто используемых синглтонов. Применяются внутри реализаций репозиториев и API-классов, чтобы не писать `getIt<...>()` каждый раз. Сегодня их **десять** — алиасы добавляются по мере того, как синглтон становится «горячим» (часто резолвится), а не заранее:

```dart
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/app/app_state_repository.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/item/item_repository.dart';
import 'package:nox_app/domain/repository/log_repository.dart';
import 'package:nox_app/domain/repository/qr/camera_permission_service.dart';
import 'package:nox_app/domain/repository/settings/settings_repository.dart';
import 'package:nox_app/domain/service/notification_permission_service.dart';
import 'package:nox_app/domain/service/qr_image_decode_service.dart';

/// Convenience getters over the DI container.
/// Cross-cutting
LogRepository get logRepository => getIt<LogRepository>();

/// Repositories
ItemRepository get itemRepository => getIt<ItemRepository>();
SettingsRepository get settingsRepository => getIt<SettingsRepository>();
ChatRepository get chatRepository => getIt<ChatRepository>();

/// App-state spine
AppStateRepository get appStateRepository => getIt<AppStateRepository>();
AuthRepository get authRepository => getIt<AuthRepository>();
SessionRepository get sessionRepository => getIt<SessionRepository>();

/// QR scan (2.2) — permission service resolved by the scanner widget.
CameraPermissionService get cameraPermissionService => getIt<CameraPermissionService>();

/// Notifications (7.2) — OS notification-permission service resolved by the screen.
NotificationPermissionService get notificationPermissionService => getIt<NotificationPermissionService>();

/// QR sign-in from a picked image (2.1, Windows/Linux) — resolved by the Login screen.
QrImageDecodeService get qrImageDecodeService => getIt<QrImageDecodeService>();
```

> `itemRepository` остаётся в списке от verification-слайса `Item` (замороженного) — продуктовый код его не резолвит.

Правила:

- **Геттеры, не `final`-поля.** Резолв происходит лениво, после сборки контейнера, а не на этапе импорта (иначе — обращение к незаполненному `GetIt`).
- **Алиасы — для кросс-каттинговых синглтонов и «горячих» репозиториев.** Их зовут и реализации репозиториев / API-классов, и presentation (сегодня — 12 файлов в `lib/presentation/`, из них шесть BLoC'ов: например `LoginBloc` берёт `authRepository`). Всё, у чего алиаса нет (мапперы, DAO, API-классы, конфиг-репозиторий, узкие сервисы фичи), BLoC резолвит через `getIt<T>()` напрямую (см. §6.4 и [05-presentation-layer.md](05-presentation-layer.md)).
- Добавляй алиас только когда тип резолвится из многих мест; всё остальное (мапперы, DAO, API-классы, конфиг-репозиторий) резолвится напрямую `getIt<T>()`, пока не станет «горячим».

---

## 9. Обязательное логирование — `LogRepository` (единый канал)

В `lib/` **запрещён** сырой `print` / `debugPrint`. Весь вывод идёт через единственный канал — `LogRepository` (интерфейс в `lib/domain/repository/`, реализация в `lib/data/repository/`). Это требование архитектурного свода блюпринта (см. [08-conventions-and-constitution.md](08-conventions-and-constitution.md)) и предусловие `BaseRepositoryHelper.execute<T>()`, который **всегда** логирует через `LogRepository` (см. [04-data-layer.md](04-data-layer.md)).

### 9.1 Интерфейс — `lib/domain/repository/log_repository.dart`

```dart
/// Single logging channel for the whole app. Raw print/debugPrint is banned
/// in lib/ (FR-011); everything goes through this interface.
abstract class LogRepository {
  void debug({Object? target, required String message});

  void error({Object? target, required Object error, StackTrace? stackTrace});
}
```

> `target` — `Object?` (не `String?`): на вход принимается произвольный объект-источник, тег формируется из его `runtimeType` (см. `_tag` ниже), так что можно передать `this` из любого класса без ручной строки.

### 9.2 Реализация — `lib/data/repository/log_repository_impl.dart`

Класс реализации называется `LoggerLogRepository` (имя класса ≠ имя файла), реализует интерфейс через `implements` и использует `logger`-пакет с `SimplePrinter(printTime: true)`:

```dart
import 'package:injectable/injectable.dart';
import 'package:logger/logger.dart';
import 'package:nox_app/domain/repository/log_repository.dart';

/// Single logging channel implementation (logger package). No raw print in lib/.
@LazySingleton(as: LogRepository)
class LoggerLogRepository implements LogRepository {
  final Logger _logger = Logger(printer: SimplePrinter(printTime: true));

  @override
  void debug({Object? target, required String message}) {
    _logger.d('${_tag(target)}$message');
  }

  @override
  void error({Object? target, required Object error, StackTrace? stackTrace}) {
    _logger.e('${_tag(target)}$error', error: error, stackTrace: stackTrace);
  }

  String _tag(Object? target) => target == null ? '' : '[${target.runtimeType}] ';
}
```

Конвенции:

- Реализации репозиториев и API обращаются к логгеру через глобальный алиас `logRepository` (§8).
- Любое перехваченное-и-проглоченное исключение **обязано** нести инлайн-комментарий, почему это безопасно.
- `LoggerLogRepository` зарегистрирован без `env`-списка → доступен во всех окружениях (включая `test`), что позволяет `BaseRepositoryHelper` логировать и под тестом.
- Проброс в observability-бэкенд (Sentry / RUM) — точка расширения внутри `error(...)`, помеченная примером/TBD. «Не выбран» здесь — правда, но речь **не** о серверном бэкенде NOX (он выбран: Go-сервер `noxd`, контракт v0): не выбран именно вендор наблюдаемости / crash-репортинга — отдельный открытый вопрос, не зависящий от контракта провода.

---

## 10. `main.dart` — последовательность запуска

Точный порядок: привязка Flutter → `runZonedGuarded` → резолв флейвора → `await configureDependencies(env)` → `await getIt.allReady()` → инициализация конфиг-репозитория → `runApp(AppRoot())`. Маппинг флейвор → окружение: `prod` → `Environment.prod`, `stage` → `Environment.dev`.

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/app_config/app_flavor.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_app/domain/repository/log_repository.dart';
import 'package:nox_app/presentation/app/app_root.dart';

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
      await getIt.allReady(); // resolve every preResolve: true async registration (today: SharedPreferences)

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
4. **`getIt.allReady()`** — блокирует до завершения всех `preResolve: true` async-регистраций. Вызов делает **настоящую** работу: `@preResolve`-`SharedPreferences` из `RegisterModule` (§2) резолвится именно здесь, поэтому без `allReady()` первый же `getIt<SharedPreferences>()` в сессии/настройках бросил бы «not ready». Будущие async-потребители (например `PackageInfo.fromPlatform()` из целевой формы §3) подключаются к тому же вызову и правки `main.dart` не требуют.
5. **`configRepository.initialize(flavorType: flavor)`** — поднимает конфиг/обсёрвабилити-репозиторий (например, инициализация Sentry-сообщений, чтение Remote Config-подобных значений) уже после готового контейнера.
6. **`runApp(AppRoot())`** — корневой виджет. `AppRoot` поднимает `AppRootBloc` (тема: light/dark + `themeMode`) — см. [06-theming.md](06-theming.md).
7. **`runZonedGuarded`** — внешний guard: всё непойманное над деревом виджетов попадает в callback ошибки и роутится через единственный лог-канал.

> **Об ошибках BLoC и логировании.** Отдельного BLoC-обсёрвера в проекте **нет**. Логирование ошибок уже происходит на уровне репозиториев через обязательный `LogRepository` (`BaseRepositoryHelper.execute` всегда логирует — см. [04-data-layer.md](04-data-layer.md)), а ошибки в обработчиках BLoC оборачиваются `BaseBloc.executeLogic` (см. [05-presentation-layer.md](05-presentation-layer.md)) — поэтому отдельный BLoC-обсёрвер не нужен.

> `PackageInfo` (версия/билд приложения) через DI **не** идёт: `AppVersionTextWidget` зовёт `PackageInfo.fromPlatform()` прямо из `FutureBuilder` (§3), так что `getIt.allReady()` его не ждёт. Версионирование — CalVer + сдвинутая эпоха (`YY.M.D+EPOCH`), см. [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md).

---

## 11. Bootstrap под тесты

Тесты переиспользуют **ту же** точку входа `configureDependencies` с `Environment.test`, затем перекрывают конкретные типы моками. Полная обвязка (`flutter_test_config.dart` + `TestsUtils`) — в [08-conventions-and-constitution.md](08-conventions-and-constitution.md) §10 и [11-scaffolding-plan.md](11-scaffolding-plan.md) (шаг 12); эскиз:

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
- `AppConfigRepositoryImpl` зарегистрирован под `test` (`env: [dev, prod, test]`), а обе его конструкторные зависимости приходят из `RegisterModule` (`FlutterSecureStorage` + `@Named('isTestEnvironment')`, под тестом равный `true`) — резолвится без ручных моков (отдельной test-конфиг-модели регистрировать не нужно).
- В **целевой форме** §3 `PackageInfo.setMockInitialValues(...)` сработает в ветке `test` внутри `configureDependencies` — мок версии до запуска чего-либо. В текущем скелете этой ветки ещё нет (она появится с первым потребителем `PackageInfo`).
- `allowReassignment = true` разрешает перекрытие реальных регистраций test-double'ами после прогона цепочки.

---

## 12. Перегенерация DI (build_runner)

При **любом** добавлении/удалении аннотации или изменении сигнатуры конструктора аннотированного класса нужно перегенерировать `configure_dependencies.config.dart`. Поскольку пакет **один**, прогон тоже **один** (никаких трёх per-package прогонов):

```bash
fvm dart run build_runner build --delete-conflicting-outputs
```

Тот же прогон обновляет `*.freezed.dart` (Freezed-модели и BLoC-State/Event) и `*.g.dart` (JSON-сериализация энтити). Команды и удобные обёртки — в [12-dev-commands.md](12-dev-commands.md).

---

## Чеклист

- [ ] Один `lib/di/configure_dependencies.dart` с **единственным** `@InjectableInit(initializerName: r'$initGetIt')`, вызывающим `getIt.$initGetIt(environment: env)` (в скелете тело — только этот вызов).
- [ ] Никаких трёх `configure*Dependencies` / `$initDomainGetIt` / `$initDataGetIt` / path-зависимостей — пакет один, контейнер плоский, импорты `package:nox_app/...`.
- [ ] Окружения только `Environment.dev` / `prod` / `test`; кастомных нет.
- [ ] `AppDatabase` — интерфейс `{ db, clearEntireDatabase() }`, три env-скоупленных провайдера (`AppDatabaseProd`/`Dev`/`Test`), `@LazySingleton(as: AppDatabase, env: [<one>])`, **по одному** env на провайдер; Prod/Dev = `databaseFactoryIo` (mobile/desktop), Test = `databaseFactoryMemory`; per-env файлы `app.db`/`app_dev.db`/`app_test.db`. Никакой рантайм-`if`-ветки.
- [ ] DAO и мапперы — `@lazySingleton` (без `env`); `ItemMapper extends BaseMapper<...,dynamic,dynamic>` без конструкторных зависимостей; пути `lib/data/local/item/` и `lib/data/mapper/item/`.
- [ ] Реализации репозиториев — `@LazySingleton(as: <Feature>Repository, env: [Environment.dev, Environment.prod, Environment.test])`; **env-список не забыт** (иначе резолв бросает в рантайме). `ItemRepositoryImpl(this._itemMapper, this._itemRemote)` — network-only (`getItems` + `clean`), инъектит `ItemRemoteDataSource`, а не `ItemDao`; это **замороженный** verification-слайс, а не канон продуктовых репозиториев (чаты/сообщения — cache-first поверх `ChatDao`/`MessageDao`).
- [ ] `AppFlavorType{prod, stage}` + `AppFlavor.getFlavor()` (compile-time, `String.fromEnvironment('app.flavor')`, `default → prod`).
- [ ] Факт: `AppConfig({required flavor, apiUrl})` (`apiUrl` пока всегда `null`) + `AppConfigRepositoryImpl` `@LazySingleton(as: AppConfigRepository, env: [dev, prod, test])` с двумя конструкторными зависимостями из `RegisterModule` (`FlutterSecureStorage`, `@Named('isTestEnvironment') bool`), строит `AppConfig` в `initialize(flavorType:)`. Доп. поля `AppConfig` (реальный `apiUrl`, источник токена, ключи подписи) с чтением через `const String.fromEnvironment` внутри `initialize` — целевая форма: сервер и контракт v0 зафиксированы, per-флейворные ключи сборки — **пример/TBD** и приезжают с транспортом (027) и стадией 2 (аутентификация); тип-носитель остаётся `AppConfig`, контракт `AppConfigRepository.config` неизменен.
- [ ] `LogRepository` интерфейс (`lib/domain/repository/`, `Object? target`) + `LoggerLogRepository` impl `@LazySingleton(as: LogRepository)` (`lib/data/repository/`, `Logger(printer: SimplePrinter(printTime: true))` + `_tag`); в `lib/` нет сырого `print`/`debugPrint`.
- [ ] `PackageInfo`: в скелете не зарегистрирован; в целевой форме — async `preResolve: true` вне теста, `setMockInitialValues` под тестом (подключается с первым потребителем).
- [ ] `global_aliases.dart` — top-level **геттеры** (не `final`); сегодня их десять (`logRepository`, `itemRepository`, `settingsRepository`, `chatRepository`, `appStateRepository`, `authRepository`, `sessionRepository`, `cameraPermissionService`, `notificationPermissionService`, `qrImageDecodeService`), новые добавляются по мере «разогрева»; всё, у чего алиаса нет, BLoC зовёт через `getIt<T>()` напрямую.
- [ ] `main.dart`: `ensureInitialized` → `runZonedGuarded(...)` → `AppFlavor.getFlavor` → `await configureDependencies(env)` → `await getIt.allReady()` → `getIt<AppConfigRepository>().initialize(flavorType:)` → `runApp(AppRoot)`; маппинг `prod→prod`, `stage→dev`.
- [ ] Один прогон `build_runner build --delete-conflicting-outputs` после любой правки аннотации/конструктора; `.config.dart` никогда не редактируется руками.
