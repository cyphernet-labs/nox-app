# 14 — Сеть и авторизация

> **Назначение:** зафиксировать сетевой слой приложения NOX — как поднимается HTTP-клиент (`ApiClient` на Dio), откуда он берёт `baseUrl` и токен (`AppConfigRepository`), и как это стыкуется с REST-слоем из [04-data-layer.md](04-data-layer.md) (`RequestBuilder` → API-класс → `ResponseEntity<T>`). Базовая часть (§1–3) — **канон-паттерн блюпринта**: один Dio с одним auth-`InterceptorsWrapper`, читающим `getUserAuthIdToken()` → `Bearer`. У NOX **один** бэкенд — Go-сервер `noxd` (`client_backend/`, встроенный SQLite), второго хоста нет. Основной транспорт контракта v0 — **WebSocket-конверт поверх wss:443 с пиннингом ключа** (приходит в фазе 027); REST остаётся только под blob-обмен (`file.uploadBegin` → `PUT` → `message.send{attachment:{file_id}}`; `file.downloadBegin` → `GET` с `Range`, одноразовые 10-минутные токены), поэтому §1–3 описывают именно REST-плечо. Поверх этого §4 описывает **возможную схему аутентификации** в виде размеченного примера: собственная токен-модель (короткий access-JWT + opaque refresh) И подписанные запросы (HMAC-SHA256 + security-заголовки + replay-окно + build-gate). §4 даёт **структуру** интерсепторов, а конкретный контракт подписи/токенов помечен как пример: stage 1 контракта v0 работает **без авторизации**, а модель аутентификации/пейринга stage 2 ещё не финализирована — её и надо будет подставить вместо примера.
> **Когда читать:** перед поднятием `lib/data/remote/` (Dio-клиент, auth-interceptor), перед подключением `AppConfigRepository` к `ApiClient` и `main.dart`, и обязательно — перед реализацией auth-флоу (login / refresh / logout) и security-pipeline'а клиента.
> **Связанные документы:** [03-domain-layer.md](03-domain-layer.md) (`RepositoryResult`, `RepositoryException`), [04-data-layer.md](04-data-layer.md) (`ApiClient`/`BaseApiRepository`/`RequestBuilder`/`ResponseEntity`/`EntityConverter`, `BaseRepositoryHelper`), [02-dependency-injection.md](02-dependency-injection.md) (`AppFlavorType`, `AppConfig`, `configureDependencies`, bootstrap `main.dart`), [13-deep-links.md](13-deep-links.md) (входные web-deep-link ссылки — какие пути могут обходить подпись; deep links в приложении не реализованы, конкретный набор таких путей — открытый вопрос), [01-stack-and-tooling.md](01-stack-and-tooling.md) (`dio`, `flutter_secure_storage`), [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md) (`apiUrl` per флейвор из зашифрованных секретов; `apiSignatureKey` — пример/TBD-поле схемы §4).

---

## 0. Назначение, когда читать, связанные

Этот документ — единственный дом сетевого контракта клиента. Он отвечает на три вопроса:

1. **Как поднят HTTP-клиент** — `ApiClient.initBase()` (Dio + interceptor'ы), `BaseApiRepository` как база API-классов. §1.
2. **Откуда `baseUrl` и токен** — `AppConfigRepository` (флейвор-резолвед конфиг + источник bearer-токена). Эта зависимость раньше фигурировала в [04-data-layer.md](04-data-layer.md) как используемая, но не определённая — здесь её контракт фиксируется. §2.
3. **Как это стыкуется с REST-слоем** — `RequestBuilder` / `RequestBuilderHelper` и envelope `ResponseEntity<T>` / `EntityConverter<E>` (полные шаблоны — в [04-data-layer.md](04-data-layer.md), здесь — краткий мост). §3.

§4 — **обязательная до релиза** авторизация, приведённая как **размеченный пример** схемы (HMAC-подпись + security-заголовки + собственная токен-модель с ротацией). Бэкенд и wire-контракт выбраны (Go-сервер `noxd`, контракт v0), но **stage 1 контракта работает без авторизации**, а модель stage 2 (аутентификация/пейринг) ещё не финализирована — конкретный контракт §4 надо заменить на неё, когда её определят. §5 — сетевое состояние и lifecycle-driven refresh. §6 — чеклист.

> **Единый пакет.** Все пути — `lib/...` внутри одного пакета `nox_app` (worked example, согласован с блюпринтом). Импорты — полные `package:nox_app/...`.
>
> **Реальный код vs целевой паттерн.** §1–4 описывают **целевой** сетевой контракт. Реальный `ApiClient` намеренно тоньше: он живёт плоско в `lib/data/remote/api_client.dart` (не `lib/data/remote/api/base/...`), это `@lazySingleton` с конструктором `ApiClient(this._config)` (`AppConfigRepository`), двумя полями (`_config` + `final Dio dio`) и 30-сек таймаутами. `initBase()` у него — **идемпотентный метод экземпляра**, а не статическая фабрика: он ставит `dio.options.baseUrl` из `AppConfig.apiUrl` (когда тот непустой, **без** суффикса `/api/`) и один раз навешивает `AuthInterceptor` (§4-security-pipeline'а нет). Сейчас всё это **инертно**: `apiUrl` равен `null` во всех флейворах, `initBase()` из кода приложения не вызывается (только из тестов), и ни один data source не инжектит `ApiClient` — эта связка приезжает с DI-флипом 016 (фаза 028). Doc-comment самого класса фиксирует это прямо: «Inert while `apiUrl` is null (the contract-v0 transport is a WS envelope arriving with feature 027; REST stays for blob upload/download)». Структура `lib/data/remote/api/base/api_client.dart` + `BaseApiRepository` ниже — это **целевой** REST-каркас (один хост — у NOX один бэкенд). Все четыре сегодняшних API-класса — `GetItemsApi`, `GetChatsApi`, `GetMessagesApi`, `SendMessageApi` (моки, см. §3) — оба этих каркаса обходят.

---

## 1. `ApiClient` (канон-паттерн блюпринта)

Один экземпляр Dio: `initBase()` — основной (и единственный) API, авторизованный одним auth-`InterceptorsWrapper`. У NOX **один** бэкенд (`noxd`) — второго хоста нет. `baseUrl` берётся из `AppConfigRepository.config.apiUrl` (см. §2), к нему добавляется `/api/`. Таймауты — 30 с, `Content-Type: application/json`, `ResponseType.json`.

`lib/data/remote/api/base/api_client.dart` (целевая структура — в реальном коде это плоский `lib/data/remote/api_client.dart` с методом `initBase()` и без суффикса `/api/`, см. §0):

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
        final token = await appConfigRepository.getUserAuthIdToken();
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

- **Один auth-interceptor, читающий токен асинхронно на каждом запросе.** Токен не кешируется в interceptor'е — `await appConfigRepository.getUserAuthIdToken()` дёргается per request, поэтому ротация/обновление токена видны сразу. `null`-токен → заголовок `Authorization` **снимается** (не остаётся протухший). *Реальный `AuthInterceptor` (`lib/data/remote/interceptor/auth_interceptor.dart`) заголовок не снимает, а просто не ставит: `RequestOptions` собирается на каждый запрос заново, протухшему заголовку взяться неоткуда.*
- **`onResponse` / `onError` — пасс-тру.** Это место под debug-логи/трекинг; ошибки **не** перехватываются здесь и **не** мапятся в типизированные исключения — на non-2xx Dio просто бросает `DioException`, который ловится выше (см. §3 и [04-data-layer.md](04-data-layer.md) §5: `DioException` мапится по типу/статусу). *Одно исключение в реальном коде: `AuthInterceptor.onError` на `401` дёргает `authRepository.logout(forced: true)` (ленивый резолв через алиас — рвёт цикл `ApiClient → AuthInterceptor → AuthRepository → repositories`) и **всегда** пробрасывает ошибку дальше — он её не глотает.*
- **Один хост.** У NOX единственный бэкенд (`noxd`, `client_backend/`) — отдельного второго хоста (search/etc.) нет. `apiUrl` приходит из `AppConfig` (§2), per флейвор.

### `BaseApiRepository`

База всех API-классов отдаёт единственный клиент как геттер — у NOX один хост.

`lib/data/remote/api/base/base_api_repository.dart` (целевой каркас — в реальном коде файла ещё нет, ни один из четырёх мок-API-классов его не наследует, см. §3):

```dart
import 'package:dio/dio.dart' as dio;
import 'package:nox_app/data/remote/api/base/api_client.dart';

abstract class BaseApiRepository {
  dio.Dio get baseClient => ApiClient.initBase();
}
```

> Каждый вызов геттера поднимает свежий `Dio` (interceptor'ы навешиваются заново). Это **намеренный** выбор паттерна, а не оплошность: токен читается **из репозитория на лету** при каждом запросе, поэтому отдельный долгоживущий синглтон-Dio не обязателен — ротация/обновление токена видны мгновенно.
>
> **Что значит «один Dio».** Формулировка «один экземпляр Dio» в §1 — буквальна: у NOX один бэкенд, поэтому один клиент (`baseClient`, авторизованный). Имеется в виду, что клиент **не** singleton-инстанс: свежий `Dio` на каждый вызов геттера остаётся каноном. Если профилирование покажет, что пересборка interceptor'ов на запрос дорога́ (актуально с тяжёлым security-interceptor'ом §4.2 — HMAC + сбор UA), допустимая оптимизация — поднять `baseClient` как `@lazySingleton Dio` и навесить interceptor'ы один раз; токен при этом всё равно читается per request внутри `onRequest`, так что семантика «токен на лету» сохраняется. Это опциональная perf-добавка, а не требование.

---

## 2. `AppConfigRepository` (контракт, от которого зависят `ApiClient` и `main.dart`)

`ApiClient` (§1) и bootstrap в `main.dart` (см. [02-dependency-injection.md](02-dependency-injection.md)) ссылаются на `AppConfigRepository` — в [04-data-layer.md](04-data-layer.md)/[02-dependency-injection.md](02-dependency-injection.md) он упоминается как используемый, но его **контракт нигде не был выписан**. Здесь он фиксируется. Observability у NOX идёт через `LogRepository` (см. [04-data-layer.md](04-data-layer.md)).

> **Реальный контракт (6 членов).** Ниже выписан **фактический** интерфейс `AppConfigRepository` ([lib/domain/repository/app_config/app_config_repository.dart](../../../lib/domain/repository/app_config/app_config_repository.dart)). Две поправки к канон-паттерну блюпринта: (1) `getUserAuthIdToken()` — **метод**, а не геттер (он читает secure storage, поэтому вызывается со скобками); (2) отдельного геттера `baseApiUrl` **нет** — `apiUrl` берут через `config.apiUrl`. Сам конфиг — это класс `AppConfig` (`lib/domain/model/app_config/app_config.dart`), несущий `final AppFlavorType flavor` **и** `final String? apiUrl` (`null` во всех флейворах — реальный URL приезжает с транспортом, фаза 027); поля `apiSignatureKey` в коде нет — это пример/TBD-поле схемы §4. Поверх auth-seam'а фичи 019 контракт дорос парой `limits` / `updateLimits(ServerLimits)` — границы полезной нагрузки из `session.hello` (контракт v0 §3, выравнивание по проводу — фаза 025): до фазы 027 отдаются `ServerLimits.contractDefaults` (`maxMessageBytes` 65536, `maxAttachmentBytes` 104857600, `maxFrameBytes` 131072), писателя пока нет.

`lib/domain/repository/app_config/app_config_repository.dart`:

```dart
import 'package:nox_app/domain/model/app_config/app_config.dart';
import 'package:nox_app/domain/model/app_config/server_limits.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';

/// Holds flavor-dependent config, initialized once after the DI container is ready,
/// plus the auth-token source for the transport seam. `apiUrl` stays null until the
/// transport (027); the token writer is stage-2 auth.
abstract class AppConfigRepository {
  Future<void> initialize({required AppFlavorType flavorType});

  AppConfig get config;

  /// The signed-in user's auth token for the `Authorization` header. Read from secure
  /// storage (key `auth_id_token`); null/empty in the mock phase (no writer yet — the
  /// stage-2 sign-in will persist it; stage 1 of the contract runs without auth).
  Future<String?> getUserAuthIdToken();

  /// Server payload bounds from the last session.hello (contract v0 §3), the preflight
  /// seam for the composer/picker. Contract defaults until the transport (027).
  ServerLimits get limits;

  /// Stores the limits of a live handshake (writer arrives with phase 027).
  void updateLimits(ServerLimits limits);

  /// True under the test environment — the future hook for bypassing real auth in tests.
  bool get isTestEnvironment;
}
```

Реализация — `@LazySingleton(as: AppConfigRepository, env: [Environment.dev, Environment.prod, Environment.test])` (полный env-список: репозиторий нужен во всех окружениях, иначе `getIt<AppConfigRepository>()` в `ApiClient` упадёт под недостающим env).

`lib/data/repository/app_config/app_config_repository_impl.dart` (фактическая форма):

```dart
@LazySingleton(as: AppConfigRepository, env: [Environment.dev, Environment.prod, Environment.test])
class AppConfigRepositoryImpl implements AppConfigRepository {
  AppConfigRepositoryImpl(this._secureStorage, @Named('isTestEnvironment') this._isTestEnvironment);

  final FlutterSecureStorage _secureStorage;
  final bool _isTestEnvironment;

  AppConfig? _config;

  /// In-memory handshake limits: contract defaults until the transport (027) stores a
  /// live hello. In-memory is deliberate - a fresh handshake arrives on every connection.
  ServerLimits _limits = ServerLimits.contractDefaults;

  /// Secure-storage key for the (future) auth token. No writer yet — a real sign-in
  /// will persist it (stage-2 auth); read-only plumbing this phase.
  static const String _kAuthIdToken = 'auth_id_token';

  @override
  Future<void> initialize({required AppFlavorType flavorType}) async {
    // apiUrl is a TBD placeholder (null → no real requests); a per-flavor real URL
    // lands with the transport (027).
    _config = AppConfig(flavor: flavorType);
  }

  @override
  AppConfig get config => _config ?? (throw StateError('AppConfigRepository.initialize was not called'));

  @override
  Future<String?> getUserAuthIdToken() async {
    // Trim so a blank/whitespace-only stored value reads as absent (null) rather than
    // producing a malformed `Bearer   ` header.
    final token = (await _secureStorage.read(key: _kAuthIdToken))?.trim();
    return (token == null || token.isEmpty) ? null : token;
  }

  @override
  ServerLimits get limits => _limits;

  @override
  void updateLimits(ServerLimits limits) {
    _limits = limits;
  }

  @override
  bool get isTestEnvironment => _isTestEnvironment;
}
```

> **Факты реализации.** `AppConfigRepositoryImpl` не подмешивает `BaseRepositoryHelper` (для конфигурации, не ходящей в сеть, он ничего не добавляет), хранит конфиг лениво (`AppConfig? _config`) и собирает его прямо в `initialize` как `_config = AppConfig(flavor: flavorType)`, а на чтение `config` до `initialize` бросает `StateError('AppConfigRepository.initialize was not called')`. Токен читается из `flutter_secure_storage` по ключу `auth_id_token` — **писателя пока нет** (его даст sign-in stage 2), поэтому фактически всегда `null` → запрос уходит без `Authorization`. `isTestEnvironment` приходит из DI (`@Named('isTestEnvironment')`, env-keyed в `RegisterModule`), а не захардкожен.

Связи:

- **`config` — флейвор-резолвед.** Конфиг — это класс `AppConfig` (`lib/domain/model/app_config/app_config.dart`), который несёт `flavor` и nullable `apiUrl`; его производит `AppConfigRepositoryImpl.initialize()` и читают через `AppConfigRepository.config` (`@LazySingleton(as: AppConfigRepository, env:[dev,prod,test])`, см. [02-dependency-injection.md](02-dependency-injection.md)). `apiUrl` сегодня `null` во всех флейворах — реальный per-флейвор URL приезжает с транспортом (фаза 027); `apiSignatureKey` — пример/TBD-поле схемы §4, в коде его нет. Значения придут из зашифрованных секретов через `dart-define-from-file` ([09-build-and-secrets-infra.md](09-build-and-secrets-infra.md)). `ApiClient` (§1) читает `apiUrl` отсюда.
- **`initialize(flavorType:)`** вызывается в `main.dart` **после** `getIt.allReady()` (контейнер уже собран) — см. bootstrap-последовательность в [02-dependency-injection.md](02-dependency-injection.md) §«main.dart» и [05-presentation-layer.md](05-presentation-layer.md). Это место «поднять конфиг/observability после готового DI».
- **`getUserAuthIdToken()`** — единственная точка, откуда auth-interceptor берёт токен; сегодня он читает secure storage напрямую (ключ `auth_id_token`, писателя нет). Под целевую схему §4 его бэкендит `AuthRepository` поверх того же `flutter_secure_storage` (пример схемы — модель аутентификации stage 2 ещё не финализирована).
- **`limits` / `updateLimits`** — сюда транспорт (027) кладёт границы из `session.hello`; композер/пикер делают по ним preflight, вместо того чтобы ловить `payload_too_large` на отправке.
- Резолв везде через `getIt<AppConfigRepository>()` **напрямую** — конфиг-репозиторий **не** алиасится в `global_aliases.dart` (там алиасы `logRepository`, `itemRepository`, `settingsRepository`, `chatRepository`, `appStateRepository`, `authRepository`, `sessionRepository` и три сервиса; см. [02-dependency-injection.md](02-dependency-injection.md) §8).

---

## 3. REST-слой: `RequestBuilder` / `RequestBuilderHelper` + envelope (мост к 04)

Полные шаблоны REST-слоя — в [04-data-layer.md](04-data-layer.md) §7. Здесь — короткий мост, чтобы §1–2 замкнулись на реальный путь запроса.

- **`RequestBuilder<T>` / `RequestBuilderHelper<T>`** ([04-data-layer.md](04-data-layer.md) §7в) — `RequestBuilder` превращает доменный конфиг в `body`/`path`/`headers`; `RequestBuilderHelper` (mixin) резолвит конкретный builder из `getIt` и форвардит вызовы, чтобы API-класс не разводил билдеры руками. API-класс расширяет `BaseApiRepository` (§1) и подмешивает `RequestBuilderHelper<TheBuilder>`.
- **Envelope `ResponseEntity<T>` + `EntityConverter<E>`** ([04-data-layer.md](04-data-layer.md) §2–3) — каждый ответ data source'а обёрнут в единый envelope; `ResponseEntity<T>` — генерик-обёртка, `@EntityConverter()` резолвит `T` в конкретный entity. Фактическая форма (`lib/data/entity/base/response_entity.dart`), выровненная по контракту v0: `success` зеркалит проводной `ok`, `error` — объект `{code, message}` из §2.1 контракта:

```dart
@freezed
abstract class ResponseEntity<T> with _$ResponseEntity<T> {
  const factory ResponseEntity({@Default(false) bool success, ErrorWireEntity? error, @EntityConverter() T? data}) = _ResponseEntity<T>;

  factory ResponseEntity.fromJson(Map<String, dynamic> json) => _$ResponseEntityFromJson(json);
}
```

  `ErrorWireEntity` (`lib/data/entity/base/error_wire_entity.dart`) — это ровно `{required String code, required String message}`.

  `EntityConverter<E>` — рукописный реестр типов (`_isType<E, XxxEntity>()`-цепочки `fromJson` + зеркальные `object is XxxEntity` в `toJson`, иначе `throw ArgumentError('No converter found for type $E')`). Каждый entity, ходящий через `ResponseEntity<T>`, обязан быть в **обеих** цепочках. Полный шаблон + правило сопровождения — [04-data-layer.md](04-data-layer.md) §3.

- **Поток запроса:** доменный конфиг → `RequestBuilder` (`path`/`body`/`headers`) → API-класс шлёт через `baseClient` (§1) → `ResponseEntity<T>.fromJson(response.data)` → репозиторий распаковывает через `BaseRepositoryHelper.unwrapEnvelope<T>(response, what)` и заворачивает в `RepositoryResult` через `BaseRepositoryHelper.execute<T>()`. У `execute` **три** catch-ветки (см. [04-data-layer.md](04-data-layer.md) §5; **нет** `ApiException`/`DaoException` — это правило блюпринта): `on BaseRepositoryException` — уже смапленный доменный сбой проходит насквозь и **не** разжижается в `unknown`; `on DioException` — маппинг по типу/статусу (таймауты и `connectionError` → `connection`; 401 → `unauthenticated`; 403 → `authentication`; 404 → `notFound`; остальное → `internal`); catch-all → `unknown`. Конкретный код ошибки приходит **не** из ручной проверки `response.statusCode`, а из `unwrapEnvelope` → `RepositoryException.fromWireCode(error.code)` (`invalid_request`, `name_taken`, `payload_too_large`, `attachment_gone`, `rate_limited`, `unsupported_schema`, …; неизвестный клиенту код деградирует в `internal` по правилу эволюции контракта).

> **`BaseMapper`** живёт в `lib/data/mapper/base_mapper.dart` (не `mapper/base/`), см. [04-data-layer.md](04-data-layer.md) §4 — упоминается здесь только чтобы зафиксировать путь, REST-слой его не трогает напрямую.
>
> **Мок-API-классы.** Ни один из четырёх сегодняшних API-классов не наследует `BaseApiRepository` и не использует `RequestBuilder`/`RequestBuilderHelper`: каждый — `@lazySingleton`-**мок**, собирающий `ResponseEntity<T>` напрямую (через `Future.delayed`). `GetChatsApi` / `GetMessagesApi` / `SendMessageApi` уже отдают **проводные формы контракта v0** (`ChatsWireEntity{chats, has_more}`, `MessageWireEntity`, фича 025); реальная отправка пойдёт командой `message.send` по WS-конверту (фаза 027), а DI-флип на реальные источники — фаза 028.
>
> **`GetItemsApi` — намеренно замороженная верификационная нарезка**, а не продуктовый канон. `GetItemsApi` ([lib/data/remote/api/item/get_items_api.dart](../../../lib/data/remote/api/item/get_items_api.dart)) сохраняет **offset-пример** проводной обёртки `ItemsEntity{items, page, page_size, total}` и путь `v1/items` (без ведущего слеша), query-ключи `page`/`page_size`/`search`, пагинация **1-based** (`(config.page - 1) * pageSize`). Это исторический пример, который специально не трогают; **`total` живёт только в нём**: доменная `PageMetadata` поля `total` не имеет, и `ItemRepositoryImpl` сворачивает ответ в `PageMetadata(hasMore: hasMore, nextPage: hasMore ? entity.page + 1 : null)`. Продуктовые пути — paged (`page`/`page_size` → `{chats, has_more}`) для списка чатов и seq-курсор (`before_seq` + `limit` → `{messages, has_more}`) для истории сообщений.

---

## 4. Авторизация клиента (ОБЯЗАТЕЛЬНО до релиза)

> **Это размеченный пример схемы авторизации, не финальный контракт.** Бэкенд и wire-контракт выбраны (Go-сервер `noxd`, контракт v0), но **stage 1 контракта работает без авторизации**, а модель аутентификации/пейринга stage 2 ещё не финализирована — заменить пример на неё, когда определят. Ниже приведена **одна возможная** схема: сервер требует не просто Bearer-токен, а собственную токен-модель (короткий access-JWT + opaque refresh) И подписанные запросы, по **двум** осям сразу — и токен-модель отдельная, и каждый запрос обязан быть подписан. Главное здесь — **структура интерсепторов**, которую надстраивают над `ApiClient` (§1) и `AppConfigRepository` (§2); её можно переиспользовать под любую финальную схему. **Конкретные** имена заголовков, формат строки подписи, алгоритм HMAC и контракт токен-эндпоинтов — **пример/TBD**: их надо заменить на реальную схему аутентификации stage 2, когда её определят, и не изобретать схему подписи «на глаз» здесь. Сегодня в коде живёт только простой `Bearer` в `AuthInterceptor`, помеченный там как example/TBD-заглушка, и никакого §4-pipeline'а (формулировка того doc-comment'а — «until the NOX backend is chosen» — устарела: бэкенд выбран, не определена именно схема аутентификации stage 2).

### 4.1 Пример: две оси требований к запросу

(Пример — схема аутентификации stage 2 ещё не определена; заменить на реальный контракт. Ниже — одна возможная форма требований.)

| Ось | Простой Bearer | Пример: бэкенд NOX |
|---|---|---|
| Идентификация запроса | только `Authorization: Bearer <token>` | `Authorization: Bearer <access_jwt>` **+** HMAC-подпись запроса **+** security-заголовки **+** replay-окно **+** build-gate |
| Токен-модель | один долгоживущий токен | **собственная**: короткий **access-JWT** (~15 мин) + **opaque refresh** (~45 дней) с **ротацией** и **reuse-detection** на refresh |
| Подпись запроса | нет | **обязательна** на (почти) каждом запросе — без неё `403` ещё до исполнения endpoint'а |
| Force-update | нет | невалидный/неполный `x-user-agent` → `403` ДО проверки timestamp/подписи; валидный UA с `buildNumber < min_build_number` → `426 Upgrade Required` (`error.code: upgrade_required`) |

То есть надстраиваем **две** вещи: (a) дополнительные request-интерсепторы (подпись + security-заголовки + timestamp + build-UA), и (b) `getUserAuthIdToken()`, бэкенднутый `AuthRepository` поверх `flutter_secure_storage` с refresh→rotate→retry на 401.

### 4.2 (a) Дополнительные request-интерсепторы — HMAC + security-заголовки + timestamp + build-UA

Структура: **отдельный** `InterceptorsWrapper` (или цепочка), навешиваемый в `ApiClient.initBase()` **после** auth-interceptor'а из §1. Он на каждом запросе:

1. ставит `x-request-timestamp` (epoch **ms**, в пределах ±5-мин replay-окна сервера);
2. ставит security-заголовки: `x-trace-id` (uuid per request), `x-device-id` (стабильный id устройства);
3. ставит `x-user-agent` в формате `'{os}/{appVersion}/{buildNumber}/{deviceModel}/{osVersion}/{isPhysical}'` — ровно 6 slash-сегментов; `os` покрывает все 5 целевых платформ (`ios`/`android`/`windows`/`linux`/`macos`, регистр lower-case — точный набор токенов пример/TBD), `buildNumber` — int, `isPhysical` — bool; пример: `ios/1.0.0/100/iPhone14,2/17.0/true`; канон — `UserAgentModel` (`user_agent_model.dart`). Невалидный/неполный UA → `403` ДО проверки timestamp/подписи; валидный UA с `buildNumber < min_build_number` → `426 Upgrade Required` (`error.code: upgrade_required`);
4. вычисляет `x-request-signature = hex(HMAC-SHA256(signing_key, signature_input))` и ставит его последним (когда `body`/`path`/`timestamp` уже финализированы).

В этом примере каждый запрос несёт ровно 5 security-заголовков — `x-request-timestamp`, `x-request-signature`, `x-user-agent`, `x-device-id`, `x-trace-id` (наличие всех проверяется одним «hasAllSecurityHeaders»-гейтом); отсутствие любого → `403` до проверки HMAC. (Точный набор и имена заголовков — пример/TBD.)

#### `UserAgentModel` — определение (источник `x-user-agent`)

Выше `UserAgentModel` цитировался как канон формата — здесь его контракт фиксируется (пример формы — финальный формат `x-user-agent` задаст схема аутентификации stage 2). Модель собирает 6 сегментов значения `x-user-agent`, склеиваемых через `/` строго в этом порядке: `{os}/{appVersion}/{buildNumber}/{deviceModel}/{osVersion}/{isPhysical}`.

| Сегмент | Тип | Источник | Правило |
|---|---|---|---|
| `os` | `String` | вычисляется по платформе (`Platform.isIOS`/`isAndroid`/`isWindows`/`isMacOS`/`isLinux`) | один из 5 целевых: `'ios'`/`'android'`/`'windows'`/`'macos'`/`'linux'`, регистр lower-case (точный набор токенов — пример/TBD) |
| `appVersion` | `String` | `package_info_plus` (`PackageInfo.version`) | semver-строка, напр. `1.0.0` |
| `buildNumber` | `int` | `package_info_plus` (`PackageInfo.buildNumber`) | целое; `buildNumber` ниже `min_build_number` → `426` build-gate (§4.4) |
| `deviceModel` | `String` | плагин device-info (per-OS-ветка: model/computer-name по платформе — точный источник пример/TBD) | напр. `iPhone14,2` |
| `osVersion` | `String` | плагин device-info (per-OS-ветка: версия ОС по платформе — точный источник пример/TBD) | напр. `17.0` |
| `isPhysical` | `bool` | плагин device-info (физическое устройство vs симулятор/эмулятор; на десктопе — `true`/example-TBD) | `true` — реальное устройство, `false` — симулятор/эмулятор |

> `package_info_plus` (пиннится в [01-stack-and-tooling.md](01-stack-and-tooling.md), `^10`) даёт только `appVersion`+`buildNumber`; `deviceModel`+`osVersion`+`isPhysical` приходят из отдельного плагина device-info (конкретный пакет ещё не выбран и в `pubspec.yaml` не подключён — пример/TBD; запиннить в [01-stack-and-tooling.md](01-stack-and-tooling.md) при подключении первым консьюмером). На десктопе (Windows/macOS/Linux) такой плагин имеет свои per-OS-ветки; точное соответствие сегментов десктопным полям — пример/TBD, финализируется вместе со схемой аутентификации stage 2.

`lib/domain/model/user_agent/user_agent_model.dart` (целевой скелет — Freezed-модель с фабрикой и `toHeaderValue()`; в коде этого файла ещё нет):

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
    throw UnimplementedError('TODO(auth-stage2): build from package_info_plus + a device-info plugin (5 platforms)');
  }

  /// Значение заголовка x-user-agent — ровно 6 сегментов через '/'.
  String toHeaderValue() => '$os/$appVersion/$buildNumber/$deviceModel/$osVersion/$isPhysical';
}
```

> **Где кешируется.** `UserAgentModel.build()` — асинхронная и читает плагины, поэтому собирается **один раз при старте** (значения неизменны на сессию) и регистрируется как DI-синглтон (`@lazySingleton` через `@preResolve`-провайдер, либо просто провайдер `DeviceContext`, поднимаемый в бутстрапе после `getIt.allReady()` — см. [02-dependency-injection.md](02-dependency-injection.md)). Security-interceptor (§4.2 п.3) берёт уже готовую строку через `userAgent.toHeaderValue()` синхронно — **не** дёргает `package_info_plus`/плагин device-info на каждом запросе.

#### `x-device-id` — стабильный id устройства

`x-device-id` (§4.2 п.2) — **стабильный** идентификатор устройства: генерируется **один раз** при первом запуске (uuid v4 через пакет `uuid`, [01-stack-and-tooling.md](01-stack-and-tooling.md)) и **сохраняется** в `flutter_secure_storage` под ключом `_device_id`; при последующих запусках читается из storage, не перегенерируется. Тот же id потом уходит и в push-регистрацию — детальный контракт хранения и его роль в дедупе push-токенов см. [15-push-notifications.md](15-push-notifications.md) §6.4.

> **`x-device-id` НЕ участвует в подписи.** Строка подписи — `METHOD\nPATH\nBODY_SHA256\nTIMESTAMP` (ниже); `x-device-id` в неё **не** входит. Поэтому смена/ротация device-id **не** ломает HMAC-подпись — запрос всё равно подписан корректно и проходит security-pipeline. Реальное последствие неправильного/«плавающего» device-id — **не** ошибка авторизации, а **осиротевший push-токен**: при смене id сервер дедупит push-строку по fallback-ключу и создаёт новую строку вместо обновления старой (старая остаётся сиротой), плюс теряется различение устройств. Поэтому id обязан быть стабильным и непустым — см. [15-push-notifications.md](15-push-notifications.md) §6.4.

Пример формы `signature_input` (схема аутентификации stage 2 ещё не определена — заменить на неё, когда финализируют) — конкатенация через `\n`:

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
// lib/data/remote/api/base/security_interceptor.dart — STRUCTURE, not final.
// TODO(auth-stage2): the stage-2 authentication scheme is not finalized yet —
// replace the header names, order and signature_input format with the real one.
// Do not hardcode a signing scheme by guesswork.
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

> **Web-deep-link исключение (пример/TBD).** Если у финальной схемы появятся endpoint'ы, открываемые по входящей web-ссылке в браузере (`requiresWebDeepLink = true`), такие пути HMAC/security-заголовки **не требуют** и не подписываются — их обрабатывает [13-deep-links.md](13-deep-links.md). Учесть при разводке interceptor'а (пропускать подпись для этих путей). Конкретный набор таких endpoint'ов — открытый вопрос (deep links в приложении не реализованы) — у NOX идентичность анонимная (ID + label, без email/телефона), поэтому email-verification / password-reset ссылки здесь неприменимы.

### 4.3 (b) `getUserAuthIdToken()` поверх `AuthRepository` + refresh→rotate→retry

`AppConfigRepository.getUserAuthIdToken()` (§2) в этой схеме отдавал бы **access-JWT** из `AuthRepository` (сегодня он читает secure storage напрямую, писателя нет). Структура (пример — схема аутентификации stage 2 ещё не определена; заменить на неё, когда финализируют):

- **`AuthRepository`** хранит пару `access` + `refresh` в **`flutter_secure_storage`** ([01-stack-and-tooling.md](01-stack-and-tooling.md)); контракт — `RepositoryResult`-форма ([03-domain-layer.md](03-domain-layer.md)), как у остального слоя данных. Десктоп-бэкенд хранилища refresh-токена под будущий auth-флоу — Keychain (macOS) / DPAPI/wincreds (Windows) / libsecret (Linux), см. ниже «Secure storage — desktop backends & local wipe».
- **`getUserAuthIdToken()`** возвращает текущий access-JWT (или `null`, если разлогинен → запрос идёт без `Authorization`, §1).
- **refresh-on-401**: отдельный response-interceptor (или обёртка в `AuthRepository`): при `401` (token expired) — дёрнуть refresh-эндпоинт (в примере — `POST /api/v1/auth/token/refresh/`) с `refresh_token` → получить **новую** пару → перезаписать в secure storage → **повторить** исходный запрос. В примере сервер делает **ротацию** refresh-токена и **reuse-detection**: предъявление уже отозванного refresh блэклистит всю сессию — поэтому клиент обязан хранить только **последнюю** выданную пару и не гонять параллельные refresh'и (нужен single-flight lock на refresh, иначе можно сжечь собственную сессию).

Контракт токен-эндпоинта (пример — заменить на реальную схему аутентификации stage 2, когда её финализируют):

| Поле ответа | Смысл |
|---|---|
| `access_token` | короткий JWT для `Authorization: Bearer` |
| `refresh_token` | opaque-токен для refresh-эндпоинта (в примере — `POST /api/v1/auth/token/refresh/`) |
| `access_token_valid_timestamp` | ISO-8601 UTC — до когда валиден access |
| `refresh_token_valid_timestamp` | ISO-8601 UTC — до когда валиден refresh |

Алгоритм клиента: использовать access до `access_token_valid_timestamp`; на истечении (или на `401 token_expired`) — refresh → rotate → retry. При провале refresh (refresh истёк / блэклистнут) — разлогин → экран входа.

> **Secure storage — desktop backends & local wipe.** `flutter_secure_storage` (`^10`) кросс-платформен и покрывает все 5 целевых платформ (iOS, Android, Windows, Linux, macOS): на macOS — Keychain, на Windows — DPAPI/wincreds, на Linux — libsecret/gnome-keyring (или KWallet). Продуктовое правило «one identity per device» опирается на этот ОС-keystore — он есть на всех 5 платформах. «Full local wipe на Logout» = `secureStorage.deleteAll()` + очистка Sembast/`shared_preferences` — **единый путь без платформенных веток** (один и тот же вызов на всех 5). Linux-нюанс: рабочий keyring (libsecret/gnome-keyring или KWallet) — **рантайм-предусловие** и **known-risk** именно для launch-deferred платформ Windows/Linux (их desktop-запуск отложен; в CI — только compile-smoke на всех трёх десктопах). В реальном коде secure storage уже подключён: `SessionRepositoryImpl` хранит там анонимный идентификатор (`session.identifier`), `AppConfigRepositoryImpl` читает оттуда `auth_id_token` (писателя нет), а `AuthRepositoryImpl.logout({forced})` выполняет описанный выше wipe: сначала `SessionRepository.clear()` (`secureStorage.deleteAll()` + удаление двух ключей prefs), и только на его успехе — очистка sembast-сторов, где `sync`-курсор сбрасывается **первым**, до чатов и сообщений. Не хватает только токен-модели §4 (access + refresh с ротацией) — она приезжает со схемой аутентификации stage 2.

### 4.4 Обработка статусов: 503 «initializing», 429, 426 build-gate

Клиент обязан понимать стартовые/защитные коды сервера (форма — пример из чужой схемы; в контракте v0 эти состояния приходят кодами ошибок §2.1, например `rate_limited`, которые уже мапятся через `RepositoryException.fromWireCode`). Сами мeханики обработки (где принимается решение о повторе, лимит попыток, раздельные ветки) — переносимы под любую финальную схему:

- **`503 service_unavailable` («initializing»)** — в примере сразу после деплоя на свежую БД сервер отдаёт retryable-503, пока идёт out-of-band provisioning схемы. Это семантически **retryable**, **но** retry **НЕ** делается автоматически внутри interceptor'а — `503 initializing` пробрасывается наверх и **возвращается в `BLoC`** как ошибка. Решение «повторить» (короткий backoff + повтор) принимает уже слой презентации/`BLoC` (например, splash/initialisation-экран показывает спиннер и ретраит), а не сетевой interceptor. Так первый «холодный» запрос не зависает в transparent-retry-цикле, скрытом от UI. (Это согласуется с инвариантом §5.5: решение о повторе принадлежит презентации/`BLoC`.)
- **`429 Too Many Requests`** — в примере превышен per-category rate-limit (auth 10 req/60s и т.п.). Источник retry-инфо зависит от транспорта (пример/TBD): либо HTTP-заголовок `Retry-After`, либо поле `error.details.retry_after` (int, секунды) в JSON body — реальный бэкенд NOX может уметь одно или другое. **Контракт повтора (переносим):** при наличии retry-after-значения — ждать ровно столько секунд перед повтором; при **отсутствии** — экспоненциальный backoff (с потолком **5 минут**). В обоих случаях — **не более 3 попыток на одно пользовательское действие**; после исчерпания попыток ошибка отдаётся в `BLoC`/UI. Не долбить сервер чаще, чем разрешает retry-after.
- **426 build-gate / 403 невалидный UA** — в примере: невалидный/неполный `x-user-agent` → `403` ДО проверки timestamp/подписи; валидный UA с `buildNumber < min_build_number` → `426 Upgrade Required` (`error.code: upgrade_required`): показать force-update-экран, увести в стор. Это РАЗНЫЕ коды — `403` и `426` обрабатываются **отдельными** ветками. Build для гейта берётся из `x-user-agent` (§4.2).

### 4.5 Правила этой схемы (пример)

- **Собственная токен-модель, не внешний identity-провайдер.** В этом примере NOX не использует чужой identity-токен как bearer — токен-модель собственная (§4.3). `AppConfigRepository.getUserAuthIdToken()` бэкендит `AuthRepository`, а не сторонний auth-SDK. (Это согласуется с продуктовой моделью NOX: анонимная идентичность ID + label, без телефона/email — никакого внешнего identity-провайдера на клиенте.)
- **Подписанные запросы.** В этом примере без HMAC-подписи запрос отвергается `403` до исполнения — interceptor §4.2 обязателен.

> **FLAG (схема аутентификации stage 2 ещё не финализирована).** §4.2–4.3 описывают **структуру** на примере одной схемы. Конкретные имена заголовков, формат `signature_input`, конкретный HMAC-вариант, путь и тело токен-эндпоинта — **не финальны в этом документе**: их надо заменить на реальную схему аутентификации stage 2, когда её определят (и согласовать с `client_backend/` + контрактом v0). В коде оставить `TODO(auth-stage2)`, как в скелете §4.2.

---

## 5. Сетевое состояние и lifecycle-driven refresh

> **Зачем эта секция.** Сетевой контур из §1–4 (HMAC + custom access/refresh JWT, `ApiClient`-интерсепторы, `401 → refresh`) описывает поведение *в момент запроса*. Здесь добавляются два ортогональных наблюдателя, питающих этот контур контекстом: (1) `ConnectivityService` — реактивный поток «онлайн/офлайн» для UX-деградации и (2) app-lifecycle observer, который на возврате приложения из background инициирует превентивную проверку/refresh access-токена. Оба — best-effort слой поверх обязательного контура; ни один не заменяет реактивную обработку ошибок в `ApiClient`.

> **Форма из блюпринта.** Оба слоя следуют уже зафиксированным формам: (1) форма сервиса-обёртки над плагином (`@LazySingleton(as: Interface, env: [dev, prod])` + мок под `[test]`, потоковый геттер) — ровно как `CameraPermissionService` / `FilePickerService`; (2) форма lifecycle-наблюдателя (`WidgetsBindingObserver` → `bloc.add(AppResumed())` с re-entrancy guard) — ровно как app-root-страница блюпринта.

> **Forward-ref.** `AuthBloc` / `AuthRepository.ensureFreshAccessToken()` — часть auth-реализации §4 (обязательна **до релиза**); здесь они уже используются как делегаты. До поднятия auth-флоу observer можно подключать только под connectivity-сигнал.

### 5.1 Принцип: два наблюдателя поверх обязательного контура

Сетевой контур из §1–4 — **единственный источник истины** о реальной доступности API. `connectivity_plus` сигнализирует только наличие сетевого интерфейса (Wi-Fi/cellular поднят), а **не** реальный интернет: туннель может быть поднят, но трафик не ходить (captive portal, DNS-дыра, упавший backend). Поэтому правило разделения ответственности:

| Слой | Источник истины | Что решает |
|---|---|---|
| `ApiClient`-интерсепторы (§1–4) | фактический ответ/ошибка от backend | `401 → refresh`, маппинг `DioException → RepositoryException`, реальная «нет сети» |
| `ConnectivityService` (5.2) | состояние сетевого интерфейса ОС | UX-баннер «нет подключения», подавление заведомо-провальных ретраев |
| app-lifecycle observer (5.4) | переход `paused → resumed` | превентивный refresh access-токена до первого запроса после долгого background |

> **Инвариант.** `ConnectivityService.watchOnline()` НЕ управляет авторизацией и НЕ решает, делать ли запрос — он только красит UX. Финальное решение «запрос провалился» всегда принимает `ApiClient` по фактической `DioException`. Не городить «офлайн-гейт», который блокирует запрос до проверки connectivity — это даёт ложные негативы (интерфейс «none», но VPN/прокси работает) и расходится с источником истины.

### 5.2 `ConnectivityService` — доменный контракт

Пакет: `connectivity_plus` (пиннится в `pubspec.yaml`, сейчас `^7.3.1`; см. [01-stack-and-tooling.md](01-stack-and-tooling.md)). Seam оформлен **сервисом**, а не репозиторием (рядом с `CameraPermissionService` / `FilePickerService`): у него нет ни кеша, ни доменной модели — только обёртка над плагином, чтобы блоки оставались тестируемыми.

`lib/domain/service/connectivity_service.dart`:

```dart
/// Domain seam over device connectivity. "Online" = the device reports at least one
/// active network. This is a PROXY for the design's Offline state: real reachability
/// becomes a session phase (no socket → connecting → catching-up → live) with the
/// transport in phase 027, which is what these consumers move onto.
abstract class ConnectivityService {
  /// The current online state (one-shot).
  Future<bool> isOnline();

  /// Emits the CURRENT online state on listen (seed), then a value on every change.
  Stream<bool> watchOnline();
}
```

> **Гарантия типов.** Оба члена отдают «голый» `bool`, без `RepositoryResult`: это горячий UX-сигнал без режима ошибки (отсутствие интерфейса — не исключение, а валидное состояние `false`), и seam — сервис, а не репозиторий, поэтому контракт `data-XOR-exception` из [03-domain-layer.md](03-domain-layer.md) здесь не применяется.

### 5.3 `ConnectivityServiceImpl` — реализация

`lib/data/service/connectivity_service_impl.dart`:

```dart
@LazySingleton(as: ConnectivityService, env: [Environment.dev, Environment.prod])
class ConnectivityServiceImpl implements ConnectivityService {
  final Connectivity _connectivity = Connectivity();

  bool _online(List<ConnectivityResult> results) => results.any((r) => r != ConnectivityResult.none);

  @override
  Future<bool> isOnline() async => _online(await _connectivity.checkConnectivity());

  @override
  Stream<bool> watchOnline() async* {
    yield await isOnline(); // seed the current value (onConnectivityChanged does not replay it)
    yield* _connectivity.onConnectivityChanged.map(_online).distinct();
  }
}
```

`connectivity_plus` отдаёт `List<ConnectivityResult>` (устройство может держать несколько интерфейсов одновременно); правило online = «список содержит хотя бы один не-`none`». `.distinct()` гасит дубли — поток эмитит только при фактической смене online↔offline, а первый `yield` подсевает текущее значение, которого `onConnectivityChanged` не реплеит. **DI env-split обязателен:** реальная импл биндится на `[dev, prod]`, а под `[test]` работает `MockConnectivityService` (`lib/data/service/mock/`, всегда online) — плагину нужен platform channel, иначе падают widget/BLoC-тесты. Ручной регистрации нет: аннотации подхватывает генератор `configureDependencies(env)` ([02-dependency-injection.md](02-dependency-injection.md)).

### 5.4 App-lifecycle observer — превентивный refresh на resume

Когда приложение уходит в background надолго, access-токен может протухнуть к моменту возврата. Реактивный `401 → refresh` из §4 это покроет — но **первый** запрос после resume словит `401`, отыграет refresh-раунд и повторится, добавив задержку к первому экрану. Lifecycle-observer убирает этот лишний раунд: на переходе `paused → resumed` он превентивно дёргает `AuthBloc` сделать проверку/refresh **до** первого пользовательского запроса. Наблюдатель ставится **один раз** на app-root `State` (`_AppRootState`, см. [05-presentation-layer.md](05-presentation-layer.md) §6.2), а не на каждой странице:

`lib/presentation/app/app_root.dart` (фрагмент `_AppRootState`):

Это **дельта поверх существующего** `_AppRootState` (05 §6.2 + 13 §5.1), а не замещающий класс: уже присутствуют `_bloc` (`AppRootBloc`) и `_navigatorKey` (= `MaterialApp.navigatorKey`), а `_deepLinkSub` появится вместе с deep links (13 §5.1, в коде их пока нет) — жизненный цикл всех трёх (`_bloc.close()`, `_deepLinkSub?.cancel()` в `dispose`) **сохраняется**; добавляются только `with WidgetsBindingObserver`, connectivity-подписка и lifecycle-хук. Сегодня `_AppRootState` connectivity не слушает вовсе: сигнал потребляют сами блоки (`ChatsListBloc` / `ChatThreadBloc` держат по подписке на `connectivityService.watchOnline()` под офлайн-баннер и флаш очереди отправки) — app-root-подписка нужна именно как триггер auth-контура §4.

```dart
class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  // late final AppRootBloc _bloc;                 // из 05 §6.2
  // final _navigatorKey = GlobalKey<NavigatorState>(); // из 05 §6.2 (MaterialApp.navigatorKey)
  // StreamSubscription<DeepLink>? _deepLinkSub;    // из 13 §5.1
  late final AuthBloc _authBloc = getIt<AuthBloc>();
  late final ConnectivityService _connectivity = getIt<ConnectivityService>();
  StreamSubscription<bool>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    // _bloc = AppRootBloc()..add(...);  _deepLinkSub = _deepLinkRepository.watchDeepLink().listen(...);  // 05 §6.2 / 13 §5.1
    WidgetsBinding.instance.addObserver(this);
    _connectivitySub = _connectivity.watchOnline().listen(
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

1. **Не блокировать запрос по connectivity.** Запрос уходит в `ApiClient` всегда; если интерфейса нет — `Dio` бросит `DioException` (`connectionError`/таймаут), `BaseRepositoryHelper.execute` смаппит его в `RepositoryException.connection` (именно `connection`, а не `internal` — маппинг идёт по типу/статусу, см. §3 и [04-data-layer.md](04-data-layer.md)), презентация покажет понятную ошибку. Это и есть «корректная деградация» — единый путь ошибки, без спец-кейса.
2. **`401 ≠ офлайн`.** Офлайн даёт `connectionError`/таймаут, а не `401`. Поэтому refresh-интерсептор (§4) НЕ должен срабатывать на сетевую ошибку — refresh запускается строго на `401 unauthenticated` от backend. Зацикливание «офлайн → 401 → refresh → офлайн» исключено по построению.
3. **UX-баннер — основная роль connectivity.** Поток `watchOnline()` гасит/показывает баннер и может дизейблить кнопки отправки на экранах; на транспортный слой он не влияет.
4. **Ретраи — реактивные, не по таймеру.** Не крутить фоновый ретрай-демон: чтение пользователь повторяет сам (pull-to-refresh / повторный тап). Одно исключение уже в коде: `ChatThreadBloc` на фронте `offline → online` переотправляет свои `pending`-сообщения (`_redeliverQueued`) — это **in-memory** очередь одного открытого треда, а не общий демон. Durable-очередь отправки (persistent outbox) — работа клиентского трека (фазы 025–027), в `lib/` её пока нет.

> **Итог.** `ConnectivityService` и lifecycle-observer — два тонких UX/превентивных слоя поверх обязательного auth-контура; источник истины о доступности API остаётся за `ApiClient` и его интерсепторами (`401 → refresh`, `DioException → ошибка`). Любая логика, которая *решает*, делать ли запрос, на основе connectivity — анти-паттерн в этом проекте.

---

## 6. Чеклист

- [ ] **§5 connectivity/lifecycle:** `ConnectivityService` (`watchOnline()` со seed'ом + `isOnline()`, оба «голый» `bool`; `@LazySingleton(as: ConnectivityService, env:[dev,prod])` + `MockConnectivityService` под `[test]`, `connectivity_plus`); app-lifecycle observer на `_AppRootState` (`WidgetsBindingObserver`, `resumed → AppResumed` превентивный refresh, **re-entrancy guard** в `AuthBloc`); connectivity НЕ гейтит запрос — источник истины остаётся за `ApiClient`.
- [ ] `ApiClient.initBase()` (целевой) — Dio, `baseUrl = ${config.apiUrl}/api/`, 30-сек таймауты, JSON; **один** auth-`InterceptorsWrapper`, читающий `getUserAuthIdToken()` async per request → `Bearer` (null → снять `Authorization`); `onResponse`/`onError` — пасс-тру (debug). В коде `ApiClient` — плоский `lib/data/remote/api_client.dart`: `@lazySingleton` с `AppConfigRepository` в конструкторе, полями `_config`+`dio` и **идемпотентным методом** `initBase()`, который ставит `baseUrl` из `apiUrl` (**без** `/api/`) и один раз навешивает `AuthInterceptor`; §4-pipeline'а нет, и всё инертно (`apiUrl == null`, `initBase()` зовут только тесты, ни один data source его не инжектит — это DI-флип 016, фаза 028).
- [ ] **Один хост.** У NOX единственный бэкенд — Go-сервер `noxd` (`client_backend/`), отдельного второго хоста (search/etc.) нет; `apiUrl` приходит из `AppConfig`, per флейвор (сегодня `null` во всех, реальный URL — фаза 027).
- [ ] `BaseApiRepository` (целевой) отдаёт единственный `baseClient` геттером; API-классы наследуют его. В коде файла ещё нет — все четыре API-класса (`GetItemsApi`, `GetChatsApi`, `GetMessagesApi`, `SendMessageApi`) — моки, собирающие `ResponseEntity<T>` напрямую, без `BaseApiRepository`/`RequestBuilder`. `GetItemsApi` — намеренно замороженная верификационная нарезка (`ItemsEntity{items, page, page_size, total}`, путь `v1/items`, 1-based); её `total` **не** попадает в доменную `PageMetadata{hasMore, nextPage}`.
- [ ] `AppConfigRepository` — фактический контракт (6 членов): `initialize(flavorType:)` / `config` / `getUserAuthIdToken()` (**метод**) / `limits` / `updateLimits(ServerLimits)` / `isTestEnvironment` в `domain/`; геттера `baseApiUrl` нет; импл — `@LazySingleton(as: AppConfigRepository, env:[dev,prod,test])` с `FlutterSecureStorage` + `@Named('isTestEnvironment')` в конструкторе, без `BaseRepositoryHelper`, `StateError` на чтение `config` до `initialize`; резолв через `getIt<AppConfigRepository>()` напрямую (в `global_aliases.dart` не алиасится).
- [ ] `AppConfig` несёт `flavor` + nullable `apiUrl` (`null` во всех флейворах до фазы 027, [02-dependency-injection.md](02-dependency-injection.md), [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md)); `apiSignatureKey` — пример/TBD-поле схемы §4, в коде его нет; собирается в `AppConfigRepositoryImpl.initialize(flavorType:)`, который вызывается в `main.dart` после `getIt.allReady()`.
- [ ] REST-мост: `RequestBuilder`/`RequestBuilderHelper` + `ResponseEntity<T>`/`EntityConverter<E>` — по [04-data-layer.md](04-data-layer.md) §2–3, §7; envelope = `{success, ErrorWireEntity? error, T? data}` (контракт v0, `error` = `{code, message}`); распаковка — `unwrapEnvelope`, у `execute` три catch-ветки (`BaseRepositoryException` насквозь → `DioException` по типу/статусу → catch-all `unknown`), нет `ApiException`/`DaoException`; конкретный код ошибки даёт `RepositoryException.fromWireCode(error.code)`, а не ручная проверка `statusCode`.
- [ ] **§4 (до релиза, схема — пример/TBD):** дополнительный security-interceptor — в примере ровно 5 security-заголовков: `x-request-timestamp` (epoch ms, ±5 мин), `x-request-signature`, `x-user-agent`, `x-device-id`, `x-trace-id` (отсутствие любого → `403` до проверки HMAC); `x-user-agent` — 6 slash-сегментов `'{os}/{appVersion}/{buildNumber}/{deviceModel}/{osVersion}/{isPhysical}'` (канон `UserAgentModel`); `x-request-signature` — HMAC-SHA256 по `METHOD\nPATH\nBODY_SHA256\nTIMESTAMP` (METHOD = `ApiRequestMethod.<verb>`, **не** uppercase; PATH — в примере **с** query); пропуск подписи для web-deep-link endpoint'ов.
- [ ] **§4 (до релиза, схема — пример/TBD):** `getUserAuthIdToken()` бэкендит `AuthRepository` поверх `flutter_secure_storage` (access-JWT + opaque refresh); refresh→rotate→retry на 401 через refresh-эндпоинт (в примере — `POST /api/v1/auth/token/refresh/`); single-flight lock на refresh (reuse-detection блэклистит сессию); разлогин при провале refresh; десктоп-бэкенды хранилища — Keychain/DPAPI/libsecret, local wipe = `secureStorage.deleteAll()` + Sembast/`shared_preferences` (единый путь, 5 платформ). В коде уже есть secure storage, `AuthRepositoryImpl.logout({forced})` с полным wipe и чтение ключа `auth_id_token` (писателя нет) — не хватает именно токен-модели stage 2.
- [ ] **§4 (до релиза, схема — пример/TBD):** `UserAgentModel` определён (6 сегментов `os`/`appVersion`/`buildNumber`/`deviceModel`/`osVersion`/`isPhysical`; `package_info_plus` → appVersion+buildNumber, плагин device-info → deviceModel+osVersion+isPhysical с per-OS-ветками; `os` по 5 платформам `ios`/`android`/`windows`/`macos`/`linux` — набор пример/TBD; `buildNumber` int, `isPhysical` bool); собирается **один раз** в DI-бутстрапе (синглтон/`DeviceContext`), interceptor берёт готовую строку.
- [ ] **§4 (до релиза, схема — пример/TBD):** `x-device-id` стабильный — генерируется uuid v4 **один раз** на первом запуске, persist в `flutter_secure_storage` (ключ `_device_id`, см. [15-push-notifications.md](15-push-notifications.md) §6.4); **НЕ** входит в `signature_input` (его смена не ломает подпись; последствие неправильного id — осиротевший push-токен, не auth-fail).
- [ ] **§4 (до релиза, схема — пример/TBD):** обработка `503 initializing` — **не** авторетраить в interceptor'е, отдать в `BLoC` (повтор решает презентация); `429` — ждать retry-after-значение (заголовок `Retry-After` или поле `error.details.retry_after` — транспорт пример/TBD), при отсутствии — экспоненциальный backoff (потолок 5 мин), **макс 3 попытки на одно пользовательское действие**; `403` невалидного/неполного UA, `426 upgrade_required` build-gate при `build < min_build_number` (force-update-экран — отдельная ветка от `403`).
- [ ] **FLAG:** точный контракт HMAC (имена заголовков, `signature_input`, алгоритм) и токен-эндпоинта **заменены на реальную схему аутентификации stage 2** (stage 1 контракта v0 работает без авторизации, модель stage 2 не финализирована) до реализации; в коде — `TODO(auth-stage2)`, не изобретать схему здесь.
