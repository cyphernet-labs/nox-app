# 14 — Сеть и авторизация

> **Назначение:** зафиксировать сетевой слой приложения NOX — как поднимается HTTP-клиент (`ApiClient` на Dio), откуда он берёт `baseUrl` и токен (`AppConfigRepository`), и как это стыкуется с REST-слоем из [04-data-layer.md](04-data-layer.md) (`RequestBuilder` → API-класс → `ResponseEntity<T>`). Базовая часть (§1–3) — **канон-паттерн блюпринта**: один Dio с одним auth-`InterceptorsWrapper`, читающим `getUserAuthIdToken` → `Bearer`. У NOX **один** (ещё не выбранный) бэкенд — второго хоста нет. Поверх этого §4 описывает **возможную адаптацию под бэкенд NOX** в виде размеченного примера: собственная токен-модель (короткий access-JWT + opaque refresh) И подписанные запросы (HMAC-SHA256 + security-заголовки + replay-окно + build-gate). §4 даёт **структуру** интерсепторов, а конкретный контракт подписи/токенов помечен как пример (бэкенд/протокол NOX ещё не выбран — заменить на реальную схему авторизации, когда определят).
> **Когда читать:** перед поднятием `lib/data/remote/` (Dio-клиент, auth-interceptor), перед подключением `AppConfigRepository` к `ApiClient` и `main.dart`, и обязательно — перед реализацией auth-флоу (login / refresh / logout) и security-pipeline'а клиента.
> **Связанные документы:** [03-domain-layer.md](03-domain-layer.md) (`RepositoryResult`, `RepositoryException`), [04-data-layer.md](04-data-layer.md) (`ApiClient`/`BaseApiRepository`/`RequestBuilder`/`ResponseEntity`/`EntityConverter`, `BaseRepositoryHelper`), [02-dependency-injection.md](02-dependency-injection.md) (`AppFlavorType`, `AppConfig`, `configureDependencies`, bootstrap `main.dart`), [13-deep-links.md](13-deep-links.md) (входные web-deep-link ссылки — какие пути могут обходить подпись; конкретный набор зависит от ещё не выбранного бэкенда/протокола NOX), [01-stack-and-tooling.md](01-stack-and-tooling.md) (`dio`, `flutter_secure_storage`), [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md) (`apiUrl`/`apiSignatureKey` per флейвор из зашифрованных секретов — пример TBD-полей конфига, бэкенд ещё не выбран).

---

## 0. Назначение, когда читать, связанные

Этот документ — единственный дом сетевого контракта клиента. Он отвечает на три вопроса:

1. **Как поднят HTTP-клиент** — `ApiClient.initBase()` (Dio + interceptor'ы), `BaseApiRepository` как база API-классов. §1.
2. **Откуда `baseUrl` и токен** — `AppConfigRepository` (флейвор-резолвед конфиг + источник bearer-токена). Эта зависимость раньше фигурировала в [04-data-layer.md](04-data-layer.md) как используемая, но не определённая — здесь её контракт фиксируется. §2.
3. **Как это стыкуется с REST-слоем** — `RequestBuilder` / `RequestBuilderHelper` и envelope `ResponseEntity<T>` / `EntityConverter<E>` (полные шаблоны — в [04-data-layer.md](04-data-layer.md), здесь — краткий мост). §3.

§4 — **обязательная до релиза** адаптация под реальный бэкенд NOX, приведённая как **размеченный пример** схемы авторизации (HMAC-подпись + security-заголовки + собственная токен-модель с ротацией). Бэкенд/протокол NOX ещё не выбран — конкретный контракт §4 надо заменить на реальную схему авторизации, когда её определят. §5 — сетевое состояние и lifecycle-driven refresh. §6 — чеклист.

> **Единый пакет.** Все пути — `lib/...` внутри одного пакета `nox_app` (worked example, согласован с блюпринтом). Импорты — полные `package:nox_app/...`.
>
> **Скелет Feature-001 vs целевой паттерн.** §1–4 описывают **целевой** сетевой контракт. В скелете Feature-001 он намеренно тоньше: `ApiClient` живёт плоско в `lib/data/remote/api_client.dart` (не `lib/data/remote/api/base/...`) и пока это просто `@lazySingleton`-обёртка над `Dio` с одним полем `final Dio dio;` и 30-сек таймаутами — без `initBase()`-фабрики, без auth-interceptor'а, без `/api/`-base-URL и без §4-security-pipeline'а. Doc-comment самого класса фиксирует это прямо: «Base URL, auth interceptor, HMAC/security headers and the token source are example/TBD (backend & protocol not chosen)». Структура `lib/data/remote/api/base/api_client.dart` + `BaseApiRepository` ниже — это **целевой** REST-каркас (один хост — у NOX один бэкенд); он встанет на место плоского `api_client.dart`, когда определят бэкенд. Единственный сейчас API-класс — `GetItemsApi` (мок, см. §3) — оба этих каркаса обходит.

---

## 1. `ApiClient` (канон-паттерн блюпринта)

Один экземпляр Dio: `initBase()` — основной (и единственный) API, авторизованный одним auth-`InterceptorsWrapper`. У NOX **один** (ещё не выбранный) бэкенд — второго хоста нет. `baseUrl` берётся из `AppConfigRepository.config.apiUrl` (см. §2), к нему добавляется `/api/`. Таймауты — 30 с, `Content-Type: application/json`, `ResponseType.json`.

`lib/data/remote/api/base/api_client.dart` (целевая структура — в скелете это плоский `lib/data/remote/api_client.dart`, см. §0):

```dart
import 'package:dio/dio.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';

class ApiClient {
  static Dio initBase({String? contentType}) {
    final appConfigRepository = getIt<AppConfigRepository>();
    final baseOptions = BaseOptions(
      baseUrl: '${appConfigRepository.config.apiUrl}/api/',
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      contentType: contentType ?? 'application/json',
      responseType: ResponseType.json,
    );
    final dio = Dio(baseOptions);

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await appConfigRepository.getUserAuthIdToken;
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        } else {
          options.headers.remove('Authorization');
        }
        return handler.next(options);
      },
      onResponse: (response, handler) => handler.next(response),
      onError: (e, handler) => handler.next(e),
    ));
    return dio;
  }
}
```

Ключевое в каноне:

- **Один auth-interceptor, читающий токен асинхронно на каждом запросе.** Токен не кешируется в interceptor'е — `await appConfigRepository.getUserAuthIdToken` дёргается per request, поэтому ротация/обновление токена видны сразу. `null`-токен → заголовок `Authorization` **снимается** (не остаётся протухший).
- **`onResponse` / `onError` — пасс-тру.** Это место под debug-логи/трекинг; ошибки **не** перехватываются здесь и **не** мапятся в типизированные исключения — на non-2xx Dio просто бросает `DioException`, который ловится выше (см. §3 и [04-data-layer.md](04-data-layer.md) §5: `DioException → RepositoryException.internal`).
- **Один хост.** У NOX единственный (ещё не выбранный) бэкенд — отдельного второго хоста (search/etc.) нет. `apiUrl` приходит из `AppConfig` (§2), per флейвор.

### `BaseApiRepository`

База всех API-классов отдаёт единственный клиент как геттер — у NOX один хост.

`lib/data/remote/api/base/base_api_repository.dart` (целевой каркас — в скелете Feature-001 файла ещё нет, единственный API-класс `GetItemsApi` его не наследует, см. §3):

```dart
import 'package:dio/dio.dart' as dio;
import 'package:nox_app/data/remote/api/base/api_client.dart';

abstract class BaseApiRepository {
  dio.Dio get baseClient => ApiClient.initBase();
}
```

> Каждый вызов геттера поднимает свежий `Dio` (interceptor'ы навешиваются заново). Это **намеренный** выбор паттерна, а не оплошность: токен читается **из репозитория на лету** при каждом запросе, поэтому отдельный долгоживущий синглтон-Dio не обязателен — ротация/обновление токена видны мгновенно.
>
> **Что значит «один Dio».** Формулировка «один экземпляр Dio» в §1 — буквальна: у NOX один (ещё не выбранный) бэкенд, поэтому один клиент (`baseClient`, авторизованный). Имеется в виду, что клиент **не** singleton-инстанс: свежий `Dio` на каждый вызов геттера остаётся каноном. Если профилирование покажет, что пересборка interceptor'ов на запрос дорога́ (актуально с тяжёлым security-interceptor'ом §4.2 — HMAC + сбор UA), допустимая оптимизация — поднять `baseClient` как `@lazySingleton Dio` и навесить interceptor'ы один раз; токен при этом всё равно читается per request внутри `onRequest`, так что семантика «токен на лету» сохраняется. Это опциональная perf-добавка, а не требование.

---

## 2. `AppConfigRepository` (контракт, от которого зависят `ApiClient` и `main.dart`)

`ApiClient` (§1) и bootstrap в `main.dart` (см. [02-dependency-injection.md](02-dependency-injection.md)) ссылаются на `AppConfigRepository` — в [04-data-layer.md](04-data-layer.md)/[02-dependency-injection.md](02-dependency-injection.md) он упоминается как используемый, но его **контракт нигде не был выписан**. Здесь он фиксируется. Observability у NOX идёт через `LogRepository` (см. [04-data-layer.md](04-data-layer.md)).

> **Скелет Feature-001 vs целевой контракт.** Ниже выписан **целевой** интерфейс `AppConfigRepository` (5 членов). В скелете Feature-001 он намеренно тоньше — содержит только два члена: `Future<void> initialize({required AppFlavorType flavorType})` и `AppConfig get config` ([lib/domain/repository/app_config/app_config_repository.dart](../../../lib/domain/repository/app_config/app_config_repository.dart)). Геттеры `baseApiUrl` / `getUserAuthIdToken` / `isTestEnvironment` появятся вместе с auth-флоу (FR-013, бэкенд ещё не выбран). Сам конфиг — это класс `AppConfig` (`lib/domain/model/app_config/app_config.dart`), несущий **только** `final AppFlavorType flavor`; полей `apiUrl`/`apiSignatureKey` в коде сейчас нет — это пример/TBD-поля самого `AppConfig`, которые добавятся с реальным бэкендом. Doc-comment самих файлов фиксирует это: «Token source / apiUrl are example/TBD».

`lib/domain/repository/app_config/app_config_repository.dart`:

```dart
import 'package:nox_app/domain/model/app_config/app_config.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';

abstract class AppConfigRepository {
  /// Флейвор-резолвед конфиг. Сегодня несёт только `flavor`; поля apiUrl,
  /// apiSignatureKey, … — пример/TBD (бэкенд NOX ещё не выбран).
  AppConfig get config;

  /// Базовый API-URL (синоним config.apiUrl, удобный геттер).
  String get baseApiUrl;

  /// Поднять конфиг под выбранный флейвор.
  /// Вызывается в main.dart после готового DI-контейнера.
  Future<void> initialize({required AppFlavorType flavorType});

  /// Источник bearer-токена для auth-interceptor'а (§1). null → запрос идёт без Authorization.
  Future<String?> get getUserAuthIdToken;

  /// true под test-флейвором/окружением
  /// (например, чтобы отключить часть сетевой логики в тестах).
  bool get isTestEnvironment;
}
```

Реализация — `@LazySingleton(as: AppConfigRepository, env: [Environment.dev, Environment.prod, Environment.test])` (полный env-список: репозиторий нужен во всех окружениях, иначе `getIt<AppConfigRepository>()` в `ApiClient` упадёт под недостающим env).

`lib/data/repository/app_config/app_config_repository_impl.dart` (целевая форма — расширенная; код Feature-001 содержит только `initialize`+`config`, без `BaseRepositoryHelper`):

```dart
@LazySingleton(as: AppConfigRepository, env: [Environment.dev, Environment.prod, Environment.test])
class AppConfigRepositoryImpl implements AppConfigRepository {
  AppConfig? _config;

  @override
  AppConfig get config => _config ?? (throw StateError('AppConfigRepository.initialize was not called'));

  @override
  String get baseApiUrl => config.apiUrl; // apiUrl — пример/TBD-поле AppConfig (бэкенд ещё не выбран)

  @override
  Future<void> initialize({required AppFlavorType flavorType}) async {
    // Собрать флейвор-зависимый AppConfig. Сегодня — только flavor; в целевой
    // форме сюда добавятся apiUrl/apiSignatureKey/… (пример/TBD: прогреть
    // Remote-Config-подобные значения, проверить доступность бэкенда и т.п.,
    // бэкенд/протокол NOX ещё не выбран).
    _config = AppConfig(flavor: flavorType);
  }

  @override
  Future<String?> get getUserAuthIdToken async {
    // §4 (пример схемы): вернуть access-токен из AuthRepository
    // (flutter_secure_storage); null если разлогинен.
    // TODO(backend-tbd): подключить AuthRepository, когда определят схему авторизации NOX.
    return null;
  }

  @override
  bool get isTestEnvironment => false;
}
```

> **Код Feature-001 (факт скелета).** Фактический `AppConfigRepositoryImpl` не подмешивает `BaseRepositoryHelper` (для конфигурации, не ходящей в сеть, он ничего не добавляет), хранит конфиг лениво (`AppConfig? _config`) и собирает его прямо в `initialize` как `_config = AppConfig(flavor: flavorType)`, а на чтение `config` до `initialize` бросает `StateError('AppConfigRepository.initialize was not called')`. Расширенный скелет выше — целевая форма под будущий auth/бэкенд.

Связи:

- **`config` — флейвор-резолвед.** Конфиг — это класс `AppConfig` (`lib/domain/model/app_config/app_config.dart`), который сегодня несёт **только** `flavor`; его производит `AppConfigRepositoryImpl.initialize()` и читают через `AppConfigRepository.config` (`@LazySingleton(as: AppConfigRepository, env:[dev,prod,test])`, см. [02-dependency-injection.md](02-dependency-injection.md)). Целевые поля `AppConfig` — `apiUrl` (+`apiSignatureKey`/…) per флейвор (prod/stage) — пример/TBD-набор; бэкенд ещё не выбран. Значения придут из зашифрованных секретов через `dart-define-from-file` ([09-build-and-secrets-infra.md](09-build-and-secrets-infra.md)). `ApiClient` (§1) читает `apiUrl` отсюда.
- **`initialize(flavorType:)`** вызывается в `main.dart` **после** `getIt.allReady()` (контейнер уже собран) — см. bootstrap-последовательность в [02-dependency-injection.md](02-dependency-injection.md) §«main.dart» и [05-presentation-layer.md](05-presentation-layer.md). Это место «поднять конфиг/observability после готового DI».
- **`getUserAuthIdToken`** — единственная точка, откуда auth-interceptor берёт токен. Под NOX её бэкендит `AuthRepository` поверх `flutter_secure_storage` (§4, пример схемы — бэкенд/протокол ещё не выбран).
- Резолв везде через `getIt<AppConfigRepository>()` **напрямую** — конфиг-репозиторий **не** алиасится в `global_aliases.dart` (там ровно два алиаса — `logRepository`/`itemRepository`; см. [02-dependency-injection.md](02-dependency-injection.md) §8).

---

## 3. REST-слой: `RequestBuilder` / `RequestBuilderHelper` + envelope (мост к 04)

Полные шаблоны REST-слоя — в [04-data-layer.md](04-data-layer.md) §7. Здесь — короткий мост, чтобы §1–2 замкнулись на реальный путь запроса.

- **`RequestBuilder<T>` / `RequestBuilderHelper<T>`** ([04-data-layer.md](04-data-layer.md) §7в) — `RequestBuilder` превращает доменный конфиг в `body`/`path`/`headers`; `RequestBuilderHelper` (mixin) резолвит конкретный builder из `getIt` и форвардит вызовы, чтобы API-класс не разводил билдеры руками. API-класс расширяет `BaseApiRepository` (§1) и подмешивает `RequestBuilderHelper<TheBuilder>`.
- **Envelope `ResponseEntity<T>` + `EntityConverter<E>`** ([04-data-layer.md](04-data-layer.md) §2–3) — каждый ответ бэкенда обёрнут в единый envelope; `ResponseEntity<T>` — генерик-обёртка, `@EntityConverter()` резолвит `T` в конкретный entity. Конкретная форма envelope ниже — **пример** (бэкенд/протокол NOX ещё не выбран; заменить на реальный контракт, когда определят):

```dart
@freezed
abstract class ResponseEntity<T> with _$ResponseEntity<T> {
  const factory ResponseEntity({
    @Default(false) bool success,
    String? error,
    @EntityConverter() T? data,
  }) = _ResponseEntity<T>;

  factory ResponseEntity.fromJson(Map<String, dynamic> json) => _$ResponseEntityFromJson(json);
}
```

  `EntityConverter<E>` — рукописный реестр типов (`_isType<E, XxxEntity>()`-цепочки `fromJson` + зеркальные `object is XxxEntity` в `toJson`, иначе `throw ArgumentError('No converter found for type $E')`). Каждый entity, ходящий через `ResponseEntity<T>`, обязан быть в **обеих** цепочках. Полный шаблон + правило сопровождения — [04-data-layer.md](04-data-layer.md) §3.

- **Поток запроса:** доменный конфиг → `RequestBuilder` (`path`/`body`/`headers`) → API-класс шлёт через `baseClient` (§1) → `ResponseEntity<T>.fromJson(response.data)` → репозиторий заворачивает в `RepositoryResult` через `BaseRepositoryHelper.execute<T>()`. На non-2xx Dio бросает `DioException` → ветка `execute` мапит его в `RepositoryException.internal` (см. [04-data-layer.md](04-data-layer.md) §5; **нет** `ApiException`/`DaoException` — это правило блюпринта). Конкретный код (`unauthenticated` на 401, `notFound` на 404) — это **явный** `return RepositoryResult.error(...)` внутри callback'а после проверки `response.statusCode`.

> **`BaseMapper`** живёт в `lib/data/mapper/base_mapper.dart` (не `mapper/base/`), см. [04-data-layer.md](04-data-layer.md) §4 — упоминается здесь только чтобы зафиксировать путь, REST-слой его не трогает напрямую.
>
> **Скелет Feature-001: `GetItemsApi` — мок.** Единственный API-класс скелета — `GetItemsApi` ([lib/data/remote/api/item/get_items_api.dart](../../../lib/data/remote/api/item/get_items_api.dart)) — это `@lazySingleton`-**мок**: он **не** наследует `BaseApiRepository` и **не** использует `RequestBuilder`/`RequestBuilderHelper`, а синхронно собирает и возвращает `ResponseEntity<ItemsEntity>` напрямую (with `Future.delayed`). Целевой REST-каркас (`BaseApiRepository` + `RequestBuilder`) встанет на место мока с первой реальной фичей. Конкретика мока: путь `v1/items` (без ведущего слеша), query-ключи `page`/`page_size`/`search`, пагинация **1-based** (`(config.page - 1) * pageSize`) — пример контракта, бэкенд-специфика помечена TBD.

---

## 4. Адаптация под бэкенд NOX (ОБЯЗАТЕЛЬНО до релиза)

> **Это размеченный пример схемы авторизации, не финальный контракт.** Бэкенд/протокол NOX ещё не выбран — заменить на реальную схему авторизации, когда определят. Ниже приведена **одна возможная** схема: бэкенд требует не просто Bearer-токен, а собственную токен-модель (короткий access-JWT + opaque refresh) И подписанные запросы, по **двум** осям сразу — и токен-модель отдельная, и каждый запрос обязан быть подписан. Главное здесь — **структура интерсепторов**, которую надстраивают над `ApiClient` (§1) и `AppConfigRepository` (§2); её можно переиспользовать под любую финальную схему. **Конкретные** имена заголовков, формат строки подписи, алгоритм HMAC и контракт токен-эндпоинтов — **пример/TBD**: их надо заменить на реальную схему авторизации NOX, когда её определят, и не изобретать схему подписи «на глаз» здесь. Это согласуется с doc-comment'ом самого кода (`ApiClient`): «HMAC/security headers and the token source are example/TBD (backend & protocol not chosen)».

### 4.1 Пример: две оси требований к запросу

(Пример — бэкенд/протокол NOX ещё не выбран; заменить на реальный контракт. Ниже — одна возможная форма требований.)

| Ось | Простой Bearer | Пример: бэкенд NOX |
|---|---|---|
| Идентификация запроса | только `Authorization: Bearer <token>` | `Authorization: Bearer <access_jwt>` **+** HMAC-подпись запроса **+** security-заголовки **+** replay-окно **+** build-gate |
| Токен-модель | один долгоживущий токен | **собственная**: короткий **access-JWT** (~15 мин) + **opaque refresh** (~45 дней) с **ротацией** и **reuse-detection** на refresh |
| Подпись запроса | нет | **обязательна** на (почти) каждом запросе — без неё `403` ещё до исполнения endpoint'а |
| Force-update | нет | невалидный/неполный `x-user-agent` → `403` ДО проверки timestamp/подписи; валидный UA с `buildNumber < min_build_number` → `426 Upgrade Required` (`error.code: upgrade_required`) |

То есть надстраиваем **две** вещи: (a) дополнительные request-интерсепторы (подпись + security-заголовки + timestamp + build-UA), и (b) `getUserAuthIdToken`, бэкенднутый `AuthRepository` поверх `flutter_secure_storage` с refresh→rotate→retry на 401.

### 4.2 (a) Дополнительные request-интерсепторы — HMAC + security-заголовки + timestamp + build-UA

Структура: **отдельный** `InterceptorsWrapper` (или цепочка), навешиваемый в `ApiClient.initBase()` **после** auth-interceptor'а из §1. Он на каждом запросе:

1. ставит `x-request-timestamp` (epoch **ms**, в пределах ±5-мин replay-окна сервера);
2. ставит security-заголовки: `x-trace-id` (uuid per request), `x-device-id` (стабильный id устройства);
3. ставит `x-user-agent` в формате `'{os}/{appVersion}/{buildNumber}/{deviceModel}/{osVersion}/{isPhysical}'` — ровно 6 slash-сегментов; `os` покрывает все 5 целевых платформ (`ios`/`android`/`windows`/`linux`/`macos`, регистр lower-case — точный набор токенов пример/TBD), `buildNumber` — int, `isPhysical` — bool; пример: `ios/1.0.0/100/iPhone14,2/17.0/true`; канон — `UserAgentModel` (`user_agent_model.dart`). Невалидный/неполный UA → `403` ДО проверки timestamp/подписи; валидный UA с `buildNumber < min_build_number` → `426 Upgrade Required` (`error.code: upgrade_required`);
4. вычисляет `x-request-signature = hex(HMAC-SHA256(signing_key, signature_input))` и ставит его последним (когда `body`/`path`/`timestamp` уже финализированы).

В этом примере каждый запрос несёт ровно 5 security-заголовков — `x-request-timestamp`, `x-request-signature`, `x-user-agent`, `x-device-id`, `x-trace-id` (наличие всех проверяется одним «hasAllSecurityHeaders»-гейтом); отсутствие любого → `403` до проверки HMAC. (Точный набор и имена заголовков — пример/TBD.)

#### `UserAgentModel` — определение (источник `x-user-agent`)

Выше `UserAgentModel` цитировался как канон формата — здесь его контракт фиксируется (пример формы — финальный формат `x-user-agent` зависит от ещё не выбранного бэкенда). Модель собирает 6 сегментов значения `x-user-agent`, склеиваемых через `/` строго в этом порядке: `{os}/{appVersion}/{buildNumber}/{deviceModel}/{osVersion}/{isPhysical}`.

| Сегмент | Тип | Источник | Правило |
|---|---|---|---|
| `os` | `String` | вычисляется по платформе (`Platform.isIOS`/`isAndroid`/`isWindows`/`isMacOS`/`isLinux`) | один из 5 целевых: `'ios'`/`'android'`/`'windows'`/`'macos'`/`'linux'`, регистр lower-case (точный набор токенов — пример/TBD) |
| `appVersion` | `String` | `package_info_plus` (`PackageInfo.version`) | semver-строка, напр. `1.0.0` |
| `buildNumber` | `int` | `package_info_plus` (`PackageInfo.buildNumber`) | целое; `buildNumber` ниже `min_build_number` → `426` build-gate (§4.4) |
| `deviceModel` | `String` | плагин device-info (per-OS-ветка: model/computer-name по платформе — точный источник пример/TBD) | напр. `iPhone14,2` |
| `osVersion` | `String` | плагин device-info (per-OS-ветка: версия ОС по платформе — точный источник пример/TBD) | напр. `17.0` |
| `isPhysical` | `bool` | плагин device-info (физическое устройство vs симулятор/эмулятор; на десктопе — `true`/example-TBD) | `true` — реальное устройство, `false` — симулятор/эмулятор |

> `package_info_plus` (пиннится в [01-stack-and-tooling.md](01-stack-and-tooling.md), `^10`) даёт только `appVersion`+`buildNumber`; `deviceModel`+`osVersion`+`isPhysical` приходят из отдельного плагина device-info (конкретный пакет ещё не выбран и в скелете Feature-001 не подключён — пример/TBD; запиннить в [01-stack-and-tooling.md](01-stack-and-tooling.md) при подключении первым консьюмером). На десктопе (Windows/macOS/Linux) такой плагин имеет свои per-OS-ветки; точное соответствие сегментов десктопным полям — пример/TBD, финализируется вместе с бэкендом.

`lib/domain/model/user_agent/user_agent_model.dart` (скелет — Freezed-модель с фабрикой и `toHeaderValue()`):

```dart
@freezed
abstract class UserAgentModel with _$UserAgentModel {
  const UserAgentModel._();

  const factory UserAgentModel({
    required String os,          // 'ios'|'android'|'windows'|'macos'|'linux' (набор — пример/TBD)
    required String appVersion,  // package_info_plus
    required int buildNumber,    // package_info_plus
    required String deviceModel, // плагин device-info (per-OS ветка)
    required String osVersion,   // плагин device-info (per-OS ветка)
    required bool isPhysical,    // плагин device-info (на десктопе — true/example-TBD)
  }) = _UserAgentModel;

  /// Асинхронная сборка из package_info_plus + плагина device-info.
  /// Зовётся ОДИН раз в DI-бутстрапе (см. ниже), не на каждом запросе.
  static Future<UserAgentModel> build() async {
    // os := по 5 платформам: Platform.isIOS/isAndroid/isWindows/isMacOS/isLinux → ios/android/windows/macos/linux
    // appVersion/buildNumber := PackageInfo.fromPlatform()
    // deviceModel/osVersion/isPhysical := плагин device-info — per-OS ветка (ios/android/windows/macos/linux)
    throw UnimplementedError('TODO(backend-tbd): собрать из package_info_plus + плагина device-info (5 платформ)');
  }

  /// Значение заголовка x-user-agent — ровно 6 сегментов через '/'.
  String toHeaderValue() => '$os/$appVersion/$buildNumber/$deviceModel/$osVersion/$isPhysical';
}
```

> **Где кешируется.** `UserAgentModel.build()` — асинхронная и читает плагины, поэтому собирается **один раз при старте** (значения неизменны на сессию) и регистрируется как DI-синглтон (`@lazySingleton` через `@preResolve`-провайдер, либо просто провайдер `DeviceContext`, поднимаемый в бутстрапе после `getIt.allReady()` — см. [02-dependency-injection.md](02-dependency-injection.md)). Security-interceptor (§4.2 п.3) берёт уже готовую строку через `userAgent.toHeaderValue()` синхронно — **не** дёргает `package_info_plus`/плагин device-info на каждом запросе.

#### `x-device-id` — стабильный id устройства

`x-device-id` (§4.2 п.2) — **стабильный** идентификатор устройства: генерируется **один раз** при первом запуске (uuid v4 через пакет `uuid`, [01-stack-and-tooling.md](01-stack-and-tooling.md)) и **сохраняется** в `flutter_secure_storage` под ключом `_device_id`; при последующих запусках читается из storage, не перегенерируется. Тот же id потом уходит и в push-регистрацию — детальный контракт хранения и его роль в дедупе push-токенов см. [15-push-notifications.md](15-push-notifications.md) §6.4.

> **`x-device-id` НЕ участвует в подписи.** Строка подписи — `METHOD\nPATH\nBODY_SHA256\nTIMESTAMP` (ниже); `x-device-id` в неё **не** входит. Поэтому смена/ротация device-id **не** ломает HMAC-подпись — запрос всё равно подписан корректно и проходит security-pipeline. Реальное последствие неправильного/«плавающего» device-id — **не** ошибка авторизации, а **осиротевший push-токен**: при смене id сервер дедупит push-строку по fallback-ключу и создаёт новую строку вместо обновления старой (старая остаётся сиротой), плюс теряется различение устройств. Поэтому id обязан быть стабильным и непустым — см. [15-push-notifications.md](15-push-notifications.md) §6.4.

Пример формы `signature_input` (бэкенд/протокол NOX ещё не выбран — заменить на реальную схему авторизации, когда определят) — конкатенация через `\n`:

```
signature_input = METHOD + "\n" + PATH + "\n" + BODY_SHA256 + "\n" + TIMESTAMP
x-request-signature = hex(HMAC-SHA256(signing_key, signature_input))
```

- **METHOD** — в этом примере **НЕ** uppercase-verb (`GET`/`POST`), а литеральная строка Dart-enum'а (`ApiRequestMethod.get`, `ApiRequestMethod.post`, …). Если финальная схема сохранит такой формат — третьесторонний клиент, пересчитывающий HMAC, обязан воспроизвести **эту** строку, а uppercase-verb упадёт на верификации. (Типичная ловушка такого формата подписи.)
- **PATH** — в этом примере полный путь **с** query (например, `/api/v1/<resource>/?limit=20`). Реальный бэкенд может подписывать путь **с** или **без** query — конкретное правило пример/TBD.
- **BODY_SHA256** — `hex(SHA256(request.bodyBytes))`, то есть hex-SHA-256 **сырых байтов тела, как они уходят на провод**. Конкретно по типу тела:
  - **JSON POST** — тело сериализуется в JSON, кодируется в UTF-8, и хешируются именно эти байты (`hex(SHA256(utf8(json)))`). Хешировать надо **финальный** сериализованный байтовый поток, а не доменный объект.
  - **`multipart/form-data`** — хешируется **всё тело целиком как передаётся**, включая boundary-разделители (а не только полезная нагрузка файла). Источник хеша — итоговый собранный multipart-поток.
  - **GET/DELETE без тела** — `hex(SHA256(""))`, т.е. SHA-256 пустой строки (пустого набора байтов).
- **TIMESTAMP** — значение `x-request-timestamp` (epoch ms как строка).
- **signing_key** — `apiSignatureKey` из `AppConfig` (целевое пример/TBD-поле, per флейвор, из зашифрованных секретов, [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md)).

Скелет (имена/формат — placeholder под сверку):

```dart
// lib/data/remote/api/base/security_interceptor.dart — СТРУКТУРА, не финал.
// TODO(backend-tbd): бэкенд/протокол NOX ещё не выбран — заменить имена заголовков,
// порядок и формат signature_input на реальную схему авторизации NOX.
// Не хардкодить схему «на глаз».
InterceptorsWrapper buildSecurityInterceptor(AppConfigRepository appConfig) {
  return InterceptorsWrapper(
    onRequest: (options, handler) async {
      final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
      options.headers['x-request-timestamp'] = timestamp;
      options.headers['x-trace-id'] = /* uuid v4 per request */ '';
      options.headers['x-device-id'] = /* стабильный device id */ '';
      options.headers['x-user-agent'] = /* 6 slash-сегментов (канон UserAgentModel, os по 5 платформам) */ '';

      final method = /* 'ApiRequestMethod.<verb>' — НЕ uppercase! */ '';
      final path = options.uri.path + (options.uri.hasQuery ? '?${options.uri.query}' : ''); // пример: путь с query
      final bodyBytes = /* сырые байты тела (или пустая строка для GET) */ <int>[];
      final bodyHash = /* hex(sha256(bodyBytes)) */ '';
      final signatureInput = '$method\n$path\n$bodyHash\n$timestamp';
      final signingKey = appConfig.config.apiSignatureKey;
      options.headers['x-request-signature'] = /* hex(HMAC-SHA256(signingKey, signatureInput)) */ '';

      return handler.next(options);
    },
  );
}
```

> **Web-deep-link исключение (пример/TBD).** Если у финальной схемы появятся endpoint'ы, открываемые по входящей web-ссылке в браузере (`requiresWebDeepLink = true`), такие пути HMAC/security-заголовки **не требуют** и не подписываются — их обрабатывает [13-deep-links.md](13-deep-links.md). Учесть при разводке interceptor'а (пропускать подпись для этих путей). Конкретный набор таких endpoint'ов зависит от ещё не выбранного бэкенда/протокола NOX — у NOX идентичность анонимная (ID + label, без email/телефона), поэтому email-verification / password-reset ссылки здесь неприменимы.

### 4.3 (b) `getUserAuthIdToken` поверх `AuthRepository` + refresh→rotate→retry

`AppConfigRepository.getUserAuthIdToken` (§2) под NOX отдаёт **access-JWT** из `AuthRepository`. Структура (пример — бэкенд/протокол NOX ещё не выбран; заменить на реальную схему авторизации, когда определят):

- **`AuthRepository`** хранит пару `access` + `refresh` в **`flutter_secure_storage`** ([01-stack-and-tooling.md](01-stack-and-tooling.md)); контракт — `RepositoryResult`-форма ([03-domain-layer.md](03-domain-layer.md)), как у остального слоя данных. Десктоп-бэкенд хранилища refresh-токена под будущий auth-флоу — Keychain (macOS) / DPAPI/wincreds (Windows) / libsecret (Linux), см. ниже «Secure storage — desktop backends & local wipe».
- **`getUserAuthIdToken`** возвращает текущий access-JWT (или `null`, если разлогинен → запрос идёт без `Authorization`, §1).
- **refresh-on-401**: отдельный response-interceptor (или обёртка в `AuthRepository`): при `401` (token expired) — дёрнуть refresh-эндпоинт (в примере — `POST /api/v1/auth/token/refresh/`) с `refresh_token` → получить **новую** пару → перезаписать в secure storage → **повторить** исходный запрос. В примере сервер делает **ротацию** refresh-токена и **reuse-detection**: предъявление уже отозванного refresh блэклистит всю сессию — поэтому клиент обязан хранить только **последнюю** выданную пару и не гонять параллельные refresh'и (нужен single-flight lock на refresh, иначе можно сжечь собственную сессию).

Контракт токен-эндпоинта (пример — заменить на реальную схему авторизации NOX, когда определят):

| Поле ответа | Смысл |
|---|---|
| `access_token` | короткий JWT для `Authorization: Bearer` |
| `refresh_token` | opaque-токен для refresh-эндпоинта (в примере — `POST /api/v1/auth/token/refresh/`) |
| `access_token_valid_timestamp` | ISO-8601 UTC — до когда валиден access |
| `refresh_token_valid_timestamp` | ISO-8601 UTC — до когда валиден refresh |

Алгоритм клиента: использовать access до `access_token_valid_timestamp`; на истечении (или на `401 token_expired`) — refresh → rotate → retry. При провале refresh (refresh истёк / блэклистнут) — разлогин → экран входа.

> **Secure storage — desktop backends & local wipe.** `flutter_secure_storage` (`^10`) кросс-платформен и покрывает все 5 целевых платформ (iOS, Android, Windows, Linux, macOS): на macOS — Keychain, на Windows — DPAPI/wincreds, на Linux — libsecret/gnome-keyring (или KWallet). Продуктовое правило «one identity per device» опирается на этот ОС-keystore — он есть на всех 5 платформах. «Full local wipe на Logout» = `secureStorage.deleteAll()` + очистка Sembast/`shared_preferences` — **единый путь без платформенных веток** (один и тот же вызов на всех 5). Linux-нюанс: рабочий keyring (libsecret/gnome-keyring или KWallet) — **рантайм-предусловие** и **known-risk** именно для launch-deferred платформ Windows/Linux (их desktop-запуск отложен; в CI — только compile-smoke на всех трёх десктопах). В скелете Feature-001 secure storage **не подключается** — нет `AuthRepository` (FR-013); этот бэкенд активируется вместе с будущим auth-флоу.

### 4.4 Обработка статусов: 503 «initializing», 429, 426 build-gate

Клиент обязан понимать стартовые/защитные коды сервера (форма — пример; бэкенд/протокол NOX ещё не выбран, заменить на реальный контракт, когда определят). Сами мeханики обработки (где принимается решение о повторе, лимит попыток, раздельные ветки) — переносимы под любую финальную схему:

- **`503 service_unavailable` («initializing»)** — в примере сразу после деплоя на свежую БД сервер отдаёт retryable-503, пока идёт out-of-band provisioning схемы. Это семантически **retryable**, **но** retry **НЕ** делается автоматически внутри interceptor'а — `503 initializing` пробрасывается наверх и **возвращается в `BLoC`** как ошибка. Решение «повторить» (короткий backoff + повтор) принимает уже слой презентации/`BLoC` (например, splash/initialisation-экран показывает спиннер и ретраит), а не сетевой interceptor. Так первый «холодный» запрос не зависает в transparent-retry-цикле, скрытом от UI. (Это согласуется с инвариантом §5.5: решение о повторе принадлежит презентации/`BLoC`.)
- **`429 Too Many Requests`** — в примере превышен per-category rate-limit (auth 10 req/60s и т.п.). Источник retry-инфо зависит от транспорта (пример/TBD): либо HTTP-заголовок `Retry-After`, либо поле `error.details.retry_after` (int, секунды) в JSON body — реальный бэкенд NOX может уметь одно или другое. **Контракт повтора (переносим):** при наличии retry-after-значения — ждать ровно столько секунд перед повтором; при **отсутствии** — экспоненциальный backoff (с потолком **5 минут**). В обоих случаях — **не более 3 попыток на одно пользовательское действие**; после исчерпания попыток ошибка отдаётся в `BLoC`/UI. Не долбить сервер чаще, чем разрешает retry-after.
- **426 build-gate / 403 невалидный UA** — в примере: невалидный/неполный `x-user-agent` → `403` ДО проверки timestamp/подписи; валидный UA с `buildNumber < min_build_number` → `426 Upgrade Required` (`error.code: upgrade_required`): показать force-update-экран, увести в стор. Это РАЗНЫЕ коды — `403` и `426` обрабатываются **отдельными** ветками. Build для гейта берётся из `x-user-agent` (§4.2).

### 4.5 Правила этой схемы (пример)

- **Собственная токен-модель, не внешний identity-провайдер.** В этом примере NOX не использует чужой identity-токен как bearer — токен-модель собственная (§4.3). `AppConfigRepository.getUserAuthIdToken` бэкендит `AuthRepository`, а не сторонний auth-SDK. (Это согласуется с продуктовой моделью NOX: анонимная идентичность ID + label, без телефона/email — никакого внешнего identity-провайдера на клиенте.)
- **Подписанные запросы.** В этом примере без HMAC-подписи запрос отвергается `403` до исполнения — interceptor §4.2 обязателен.

> **FLAG (бэкенд/протокол NOX ещё не выбран).** §4.2–4.3 описывают **структуру** на примере одной схемы. Конкретные имена заголовков, формат `signature_input`, конкретный HMAC-вариант, путь и тело токен-эндпоинта — **не финальны в этом документе**: их надо заменить на реальную схему авторизации NOX, когда её определят (и согласовать с бэкендом). В коде оставить `TODO(backend-tbd)`, как в скелете §4.2.

---

## 5. Сетевое состояние и lifecycle-driven refresh

> **Зачем эта секция.** Сетевой контур из §1–4 (HMAC + custom access/refresh JWT, `ApiClient`-интерсепторы, `401 → refresh`) описывает поведение *в момент запроса*. Здесь добавляются два ортогональных наблюдателя, питающих этот контур контекстом: (1) `ConnectivityRepository` — реактивный поток «онлайн/офлайн» для UX-деградации и (2) app-lifecycle observer, который на возврате приложения из background инициирует превентивную проверку/refresh access-токена. Оба — best-effort слой поверх обязательного контура; ни один не заменяет реактивную обработку ошибок в `ApiClient`.

> **Форма из блюпринта.** Оба слоя следуют уже зафиксированным формам: (1) форма репозитория (`with BaseRepositoryHelper`, `execute(...) → RepositoryResult`, `@LazySingleton(as: Interface)`, `rxdart`-поток) — ровно как `DeepLinkRepositoryImpl`; (2) форма lifecycle-наблюдателя (`WidgetsBindingObserver` → `bloc.add(AppResumed())` с re-entrancy guard) — ровно как app-root-страница блюпринта.

> **Forward-ref.** `AuthBloc` / `AuthRepository.ensureFreshAccessToken()` — часть auth-реализации §4 (обязательна **до релиза**); здесь они уже используются как делегаты. До поднятия auth-флоу observer можно подключать только под connectivity-сигнал.

### 5.1 Принцип: два наблюдателя поверх обязательного контура

Сетевой контур из §1–4 — **единственный источник истины** о реальной доступности API. `connectivity_plus` сигнализирует только наличие сетевого интерфейса (Wi-Fi/cellular поднят), а **не** реальный интернет: туннель может быть поднят, но трафик не ходить (captive portal, DNS-дыра, упавший backend). Поэтому правило разделения ответственности:

| Слой | Источник истины | Что решает |
|---|---|---|
| `ApiClient`-интерсепторы (§1–4) | фактический ответ/ошибка от backend | `401 → refresh`, маппинг `DioException → RepositoryException`, реальная «нет сети» |
| `ConnectivityRepository` (5.2) | состояние сетевого интерфейса ОС | UX-баннер «нет подключения», подавление заведомо-провальных ретраев |
| app-lifecycle observer (5.4) | переход `paused → resumed` | превентивный refresh access-токена до первого запроса после долгого background |

> **Инвариант.** `ConnectivityRepository.watchIsOnline()` НЕ управляет авторизацией и НЕ решает, делать ли запрос — он только красит UX. Финальное решение «запрос провалился» всегда принимает `ApiClient` по фактической `DioException`. Не городить «офлайн-гейт», который блокирует запрос до проверки connectivity — это даёт ложные негативы (интерфейс «none», но VPN/прокси работает) и расходится с источником истины.

### 5.2 `ConnectivityRepository` — доменный контракт

Пакет: `connectivity_plus` (линейка `^6.x`; точную версию пинить в [01-stack-and-tooling.md](01-stack-and-tooling.md)).

`lib/domain/repository/connectivity/connectivity_repository.dart`:

```dart
abstract class ConnectivityRepository {
  /// Реактивный поток текущего состояния сетевого интерфейса.
  /// `true` — хотя бы один не-`none` интерфейс поднят. UX-only (см. инвариант 5.1).
  Stream<bool> watchIsOnline();

  /// Разовый снимок состояния интерфейса на момент вызова.
  Future<RepositoryResult<bool>> isOnline();
}
```

> **Гарантия типов.** Метод-запрос возвращает `RepositoryResult<bool>` (data-XOR-exception, см. [03-domain-layer.md](03-domain-layer.md)) — единый контракт со всеми репозиториями. Поток же отдаёт «голый» `bool`: это горячий UX-сигнал без режима ошибки (отсутствие интерфейса — не исключение, а валидное состояние `false`).

### 5.3 `ConnectivityRepositoryImpl` — реализация

`lib/data/repository/connectivity/connectivity_repository_impl.dart`:

```dart
@LazySingleton(as: ConnectivityRepository)
class ConnectivityRepositoryImpl with BaseRepositoryHelper implements ConnectivityRepository {
  final _connectivity = Connectivity();

  bool _isOnline(List<ConnectivityResult> results) => results.any((r) => r != ConnectivityResult.none);

  @override
  Stream<bool> watchIsOnline() => _connectivity.onConnectivityChanged.map(_isOnline).distinct();

  @override
  Future<RepositoryResult<bool>> isOnline() => execute(() async {
        final results = await _connectivity.checkConnectivity();
        return RepositoryResult.success(data: _isOnline(results));
      });
}
```

`connectivity_plus` отдаёт `List<ConnectivityResult>` (устройство может держать несколько интерфейсов одновременно); правило online = «список содержит хотя бы один не-`none`». `.distinct()` гасит дубли — поток эмитит только при фактической смене online↔offline. Метод `isOnline()` обёрнут в `execute(...)` ради единообразия контракта; платформенная реализация `checkConnectivity()` практически не бросает, поэтому ветка ошибки — формальность (`RepositoryException.unknown` через `BaseRepositoryHelper`). DI — без ручной регистрации: `@LazySingleton(as: ConnectivityRepository)` подхватывается генератором `configureDependencies(env)` ([02-dependency-injection.md](02-dependency-injection.md)).

### 5.4 App-lifecycle observer — превентивный refresh на resume

Когда приложение уходит в background надолго, access-токен может протухнуть к моменту возврата. Реактивный `401 → refresh` из §4 это покроет — но **первый** запрос после resume словит `401`, отыграет refresh-раунд и повторится, добавив задержку к первому экрану. Lifecycle-observer убирает этот лишний раунд: на переходе `paused → resumed` он превентивно дёргает `AuthBloc` сделать проверку/refresh **до** первого пользовательского запроса. Наблюдатель ставится **один раз** на app-root `State` (`_AppRootState`, см. [05-presentation-layer.md](05-presentation-layer.md) §6.2), а не на каждой странице:

`lib/presentation/app/app_root.dart` (фрагмент `_AppRootState`):

Это **дельта поверх существующего** `_AppRootState` (05 §6.2 + 13 §5.1), а не замещающий класс: уже присутствуют `_bloc` (`AppRootBloc`), `_navigatorKey` (= `MaterialApp.navigatorKey`) и `_deepLinkSub` — их жизненный цикл (`_bloc.close()`, `_deepLinkSub?.cancel()` в `dispose`) **сохраняется**; добавляются только `with WidgetsBindingObserver`, connectivity-подписка и lifecycle-хук.

```dart
class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  // late final AppRootBloc _bloc;                 // из 05 §6.2
  // final _navigatorKey = GlobalKey<NavigatorState>(); // из 05 §6.2 (MaterialApp.navigatorKey)
  // StreamSubscription<DeepLink>? _deepLinkSub;    // из 13 §5.1
  late final AuthBloc _authBloc = getIt<AuthBloc>();
  late final ConnectivityRepository _connectivity = getIt<ConnectivityRepository>();
  StreamSubscription<bool>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    // _bloc = AppRootBloc()..add(...);  _deepLinkSub = _deepLinkRepository.watchDeepLink().listen(...);  // 05 §6.2 / 13 §5.1
    WidgetsBinding.instance.addObserver(this);
    _connectivitySub = _connectivity.watchIsOnline().listen(
          (online) => _authBloc.add(ConnectivityChanged(isOnline: online)),
        );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _authBloc.add(const AppResumed()); // ← превентивный refresh access-токена
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
    // _deepLinkSub?.cancel();  _bloc.close();      // СОХРАНИТЬ из 05 §6.2 / 13 §5.1
    super.dispose();
  }
}
```

> **Re-entrancy guard (обязателен).** Хендлер `_onAppResumed` в `AuthBloc` ОБЯЗАН защититься от лавины событий: ОС шлёт `resumed` при каждом дёрганье foreground/background (шторка, переключатель приложений, системный диалог). Без guard'а — двойной/тройной параллельный refresh, гонка ротации refresh-токена и ложное срабатывание reuse-detection на backend (см. §4.3: предъявление уже-ротированного токена блэклистит сессию).

`lib/presentation/app/bloc/auth_bloc.dart` (фрагмент):

```dart
bool _refreshing = false;

Future<void> _onAppResumed(AppResumed event, Emitter<AuthState> emit) async {
  if (_refreshing) return;           // guard: глушим параллельные resume-волны
  if (!_hasValidSession()) return;   // нет сессии — нечего рефрешить, не дёргаем сеть
  _refreshing = true;
  await executeLogic(
    () async {
      await _authRepository.ensureFreshAccessToken(); // делегат контуру §4
    },
    onError: (String? error, dynamic exception, StackTrace stackTrace) {
      logRepository.error(target: 'auth', error: exception, stackTrace: stackTrace);
      // best-effort: тихий провал — реактивный 401→refresh покроет на первом запросе
    },
  );
  _refreshing = false;
}
```

> **Делегирование, не дублирование.** Observer НЕ реализует refresh сам — он только триггерит `AuthRepository.ensureFreshAccessToken()`, чья логика (валидность access-JWT по `exp`, ротация refresh-токена, HMAC-подпись запроса) целиком описана в §4. Observer — лишь *ранний триггер* того же кода, что отрабатывает реактивно на `401`.

### 5.5 Связь с `ApiClient`-интерсепторами и офлайн-деградация

Правила деградации в офлайне (best-effort, **без** очереди-демона):

1. **Не блокировать запрос по connectivity.** Запрос уходит в `ApiClient` всегда; если интерфейса нет — `Dio` бросит `DioException` (`connectionError`/таймаут), `BaseRepositoryHelper.execute` смаппит его в `RepositoryException.internal` ([04-data-layer.md](04-data-layer.md)), презентация покажет понятную ошибку. Это и есть «корректная деградация» — единый путь ошибки, без спец-кейса.
2. **`401 ≠ офлайн`.** Офлайн даёт `connectionError`/таймаут, а не `401`. Поэтому refresh-интерсептор (§4) НЕ должен срабатывать на сетевую ошибку — refresh запускается строго на `401 unauthenticated` от backend. Зацикливание «офлайн → 401 → refresh → офлайн» исключено по построению.
3. **UX-баннер — единственная роль connectivity.** Поток `watchIsOnline()` гасит/показывает баннер и может дизейблить кнопки отправки на экранах; на транспортный слой он не влияет.
4. **Ретраи — реактивные, не по таймеру.** При возврате онлайна не запускать «слив очереди»: пользователь повторяет действие сам (pull-to-refresh / повторный тап). Полноценная offline-очередь — нескоупленная фича (отдельный документ, не этот слой).

> **Итог.** `ConnectivityRepository` и lifecycle-observer — два тонких UX/превентивных слоя поверх обязательного auth-контура; источник истины о доступности API остаётся за `ApiClient` и его интерсепторами (`401 → refresh`, `DioException → ошибка`). Любая логика, которая *решает*, делать ли запрос, на основе connectivity — анти-паттерн в этом проекте.

---

## 6. Чеклист

- [ ] **§5 connectivity/lifecycle:** `ConnectivityRepository` (`watchIsOnline()` UX-only + `isOnline()` → `RepositoryResult`, `@LazySingleton(as:)`, `connectivity_plus`); app-lifecycle observer на `_AppRootState` (`WidgetsBindingObserver`, `resumed → AppResumed` превентивный refresh, **re-entrancy guard** в `AuthBloc`); connectivity НЕ гейтит запрос — источник истины остаётся за `ApiClient`.
- [ ] `ApiClient.initBase()` (целевой) — Dio, `baseUrl = ${config.apiUrl}/api/`, 30-сек таймауты, JSON; **один** auth-`InterceptorsWrapper`, читающий `getUserAuthIdToken` async per request → `Bearer` (null → снять `Authorization`); `onResponse`/`onError` — пасс-тру (debug). В скелете Feature-001 `ApiClient` — плоский `lib/data/remote/api_client.dart`, тонкая `@lazySingleton`-обёртка над `Dio` (одно поле `dio`), без фабрик/interceptor'ов/`/api/` (base URL/auth/HMAC — пример/TBD).
- [ ] **Один хост.** У NOX единственный (ещё не выбранный) бэкенд — отдельного второго хоста (search/etc.) нет; `apiUrl` приходит из `AppConfig`, per флейвор (пример/TBD).
- [ ] `BaseApiRepository` (целевой) отдаёт единственный `baseClient` геттером; API-классы наследуют его. В скелете файла ещё нет — единственный API-класс `GetItemsApi` — мок (`ResponseEntity<ItemsEntity>` напрямую, путь `v1/items`, query `page`/`page_size`/`search`, 1-based), без `BaseApiRepository`/`RequestBuilder`.
- [ ] `AppConfigRepository` — **целевой** контракт: `config` / `baseApiUrl` / `initialize(flavorType:)` / `getUserAuthIdToken` / `isTestEnvironment` в `domain/`; импл — `@LazySingleton(as: AppConfigRepository, env:[dev,prod,test])`; резолв через `getIt<AppConfigRepository>()` напрямую (не алиасится — в `global_aliases.dart` ровно два алиаса). В скелете Feature-001 интерфейс содержит только `initialize`+`config`; импл — без `BaseRepositoryHelper`, конфиг — класс `AppConfig` с единственным полем `flavor`, `StateError` на чтение до `initialize` (остальное — auth-флоу/FR-013).
- [ ] `AppConfig` сегодня несёт **только** `flavor`; целевые поля `apiUrl` (+`apiSignatureKey`) per флейвор ([02-dependency-injection.md](02-dependency-injection.md), [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md)) — пример/TBD, бэкенд ещё не выбран; собирается в `AppConfigRepositoryImpl.initialize(flavorType:)`, который вызывается в `main.dart` после `getIt.allReady()`.
- [ ] REST-мост: `RequestBuilder`/`RequestBuilderHelper` + `ResponseEntity<T>`/`EntityConverter<E>` — по [04-data-layer.md](04-data-layer.md) §2–3, §7; на non-2xx Dio бросает `DioException` → `RepositoryException.internal` через `BaseRepositoryHelper.execute` (нет `ApiException`/`DaoException`); конкретный код (`unauthenticated`/`notFound`) — явный `return RepositoryResult.error(...)` в callback'е.
- [ ] **§4 (до релиза, схема — пример/TBD):** дополнительный security-interceptor — в примере ровно 5 security-заголовков: `x-request-timestamp` (epoch ms, ±5 мин), `x-request-signature`, `x-user-agent`, `x-device-id`, `x-trace-id` (отсутствие любого → `403` до проверки HMAC); `x-user-agent` — 6 slash-сегментов `'{os}/{appVersion}/{buildNumber}/{deviceModel}/{osVersion}/{isPhysical}'` (канон `UserAgentModel`); `x-request-signature` — HMAC-SHA256 по `METHOD\nPATH\nBODY_SHA256\nTIMESTAMP` (METHOD = `ApiRequestMethod.<verb>`, **не** uppercase; PATH — в примере **с** query); пропуск подписи для web-deep-link endpoint'ов.
- [ ] **§4 (до релиза, схема — пример/TBD):** `getUserAuthIdToken` бэкендит `AuthRepository` поверх `flutter_secure_storage` (access-JWT + opaque refresh); refresh→rotate→retry на 401 через refresh-эндпоинт (в примере — `POST /api/v1/auth/token/refresh/`); single-flight lock на refresh (reuse-detection блэклистит сессию); разлогин при провале refresh; десктоп-бэкенды хранилища — Keychain/DPAPI/libsecret, local wipe = `secureStorage.deleteAll()` + Sembast/`shared_preferences` (единый путь, 5 платформ); в скелете Feature-001 не подключено (FR-013).
- [ ] **§4 (до релиза, схема — пример/TBD):** `UserAgentModel` определён (6 сегментов `os`/`appVersion`/`buildNumber`/`deviceModel`/`osVersion`/`isPhysical`; `package_info_plus` → appVersion+buildNumber, плагин device-info → deviceModel+osVersion+isPhysical с per-OS-ветками; `os` по 5 платформам `ios`/`android`/`windows`/`macos`/`linux` — набор пример/TBD; `buildNumber` int, `isPhysical` bool); собирается **один раз** в DI-бутстрапе (синглтон/`DeviceContext`), interceptor берёт готовую строку.
- [ ] **§4 (до релиза, схема — пример/TBD):** `x-device-id` стабильный — генерируется uuid v4 **один раз** на первом запуске, persist в `flutter_secure_storage` (ключ `_device_id`, см. [15-push-notifications.md](15-push-notifications.md) §6.4); **НЕ** входит в `signature_input` (его смена не ломает подпись; последствие неправильного id — осиротевший push-токен, не auth-fail).
- [ ] **§4 (до релиза, схема — пример/TBD):** обработка `503 initializing` — **не** авторетраить в interceptor'е, отдать в `BLoC` (повтор решает презентация); `429` — ждать retry-after-значение (заголовок `Retry-After` или поле `error.details.retry_after` — транспорт пример/TBD), при отсутствии — экспоненциальный backoff (потолок 5 мин), **макс 3 попытки на одно пользовательское действие**; `403` невалидного/неполного UA, `426 upgrade_required` build-gate при `build < min_build_number` (force-update-экран — отдельная ветка от `403`).
- [ ] **FLAG:** точный контракт HMAC (имена заголовков, `signature_input`, алгоритм) и токен-эндпоинта **заменены на реальную схему авторизации NOX** (бэкенд/протокол ещё не выбран) до реализации; в коде — `TODO(backend-tbd)`, не изобретать схему здесь.
