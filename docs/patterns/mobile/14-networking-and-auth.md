# 14 — Сеть и авторизация

> **Назначение:** зафиксировать сетевой слой приложения Speech AI Mobile — как поднимается HTTP-клиент (`ApiClient` на Dio), откуда он берёт `baseUrl` и токен (`AppConfigRepository`), и как это стыкуется с REST-слоем из [04-data-layer.md](04-data-layer.md) (`RequestBuilder` → API-класс → `ResponseEntity<T>`). Базовая часть (§1–3) — **дословный канон существующего проекта владельца** (existlive): один Dio с одним auth-`InterceptorsWrapper`, читающим `getUserAuthIdToken` → `Bearer`. Поверх этого §4 описывает **адаптацию под `client_backend`** — тот ждёт не Firebase-ID-токен, а собственную токен-модель (короткий access-JWT + opaque refresh) И подписанные запросы (HMAC-SHA256 + security-заголовки + replay-окно + build-gate). §4 даёт **структуру**, а точный контракт подписи/токенов помечен как cross-project-решение «сверить с бэкендом до реализации».
> **Когда читать:** перед поднятием `lib/data/remote/` (Dio-клиент, auth-interceptor), перед подключением `AppConfigRepository` к `ApiClient` и `main.dart`, и обязательно — перед реализацией auth-флоу (login / refresh / logout) и security-pipeline'а клиента.
> **Связанные документы:** [03-domain-layer.md](03-domain-layer.md) (`RepositoryResult`, `RepositoryException`), [04-data-layer.md](04-data-layer.md) (`ApiClient`/`BaseApiRepository`/`RequestBuilder`/`ResponseEntity`/`EntityConverter`, `BaseRepositoryHelper`), [02-dependency-injection.md](02-dependency-injection.md) (`AppFlavorType`, `AppConfigModel`, `configureDependencies`, bootstrap `main.dart`), [13-deep-links.md](13-deep-links.md) (verify-email / reset-password / share — входные ссылки, дёргающие auth-endpoint'ы), [01-stack-and-tooling.md](01-stack-and-tooling.md) (`dio`, `flutter_secure_storage`), [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md) (`apiUrl`/`searchApiUrl`/`apiSignatureKey` per флейвор из зашифрованных секретов).

---

## 0. Назначение, когда читать, связанные

Этот документ — единственный дом сетевого контракта клиента. Он отвечает на три вопроса:

1. **Как поднят HTTP-клиент** — `ApiClient.initBase()` / `initSearch()` (Dio + interceptor'ы), `BaseApiRepository` как база API-классов. §1.
2. **Откуда `baseUrl` и токен** — `AppConfigRepository` (флейвор-резолвед конфиг + источник bearer-токена). Эта зависимость раньше фигурировала в [04-data-layer.md](04-data-layer.md) как используемая, но не определённая — здесь её контракт фиксируется. §2.
3. **Как это стыкуется с REST-слоем** — `RequestBuilder` / `RequestBuilderHelper` и envelope `ResponseEntity<T>` / `EntityConverter<E>` (полные шаблоны — в [04-data-layer.md](04-data-layer.md), здесь — краткий мост). §3.

§4 — **обязательная до релиза** адаптация под реальный `client_backend`: existlive подписывает запросы только Bearer-токеном, а SpeechAI-бэкенд требует HMAC-подпись + security-заголовки + собственную токен-модель с ротацией. §5 — чеклист.

> **Единый пакет.** Все пути — `lib/...` внутри одного пакета `speech_ai_mobile` (worked example, согласован с блюпринтом). Импорты — полные `package:speech_ai_mobile/...`.

---

## 1. `ApiClient` (канон existlive, дословно)

Два экземпляра Dio: `initBase()` — основной API, авторизованный одним auth-`InterceptorsWrapper`; `initSearch()` — опциональный второй хост **без** auth-interceptor'а. `baseUrl` берётся из `AppConfigRepository.config.apiUrl` (см. §2), к нему добавляется `/api/`. Таймауты — 30 с, `Content-Type: application/json`, `ResponseType.json`.

`lib/data/remote/api/base/api_client.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:speech_ai_mobile/di/configure_dependencies.dart';
import 'package:speech_ai_mobile/domain/repository/app_config/app_config_repository.dart';

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

  static Dio initSearch({String? contentType}) {
    final appConfigRepository = getIt<AppConfigRepository>();
    final baseOptions = BaseOptions(
      baseUrl: '${appConfigRepository.config.searchApiUrl}/api/',
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      contentType: contentType ?? 'application/json',
      responseType: ResponseType.json,
    );
    // initSearch() — без auth-interceptor'а: второй хост не требует Bearer-токена.
    return Dio(baseOptions);
  }
}
```

Ключевое в каноне:

- **Один auth-interceptor, читающий токен асинхронно на каждом запросе.** Токен не кешируется в interceptor'е — `await appConfigRepository.getUserAuthIdToken` дёргается per request, поэтому ротация/обновление токена видны сразу. `null`-токен → заголовок `Authorization` **снимается** (не остаётся протухший).
- **`onResponse` / `onError` — пасс-тру.** В existlive это место под debug-логи/трекинг; ошибки **не** перехватываются здесь и **не** мапятся в типизированные исключения — на non-2xx Dio просто бросает `DioException`, который ловится выше (см. §3 и [04-data-layer.md](04-data-layer.md) §5: `DioException → RepositoryException.internal`).
- **`searchClient` — опционален.** Если второго хоста нет — `initSearch()` и `searchClient` можно выкинуть. `searchApiUrl` приходит из того же `AppConfigModel` (§2), per флейвор.

### `BaseApiRepository`

База всех API-классов отдаёт оба клиента как геттеры — каждый API-класс берёт нужный.

`lib/data/remote/api/base/base_api_repository.dart`:

```dart
import 'package:dio/dio.dart' as dio;
import 'package:speech_ai_mobile/data/remote/api/base/api_client.dart';

abstract class BaseApiRepository {
  dio.Dio get baseClient => ApiClient.initBase();

  dio.Dio get searchClient => ApiClient.initSearch();
}
```

> Каждый вызов геттера поднимает свежий `Dio` (interceptor'ы навешиваются заново). Это канон existlive; так как interceptor читает токен **из репозитория** на лету, отдельный долгоживущий синглтон-Dio не обязателен.

---

## 2. `AppConfigRepository` (контракт, от которого зависят `ApiClient` и `main.dart`)

`ApiClient` (§1) и bootstrap в `main.dart` (см. [02-dependency-injection.md](02-dependency-injection.md)) ссылаются на `AppConfigRepository` — в [04-data-layer.md](04-data-layer.md)/[02-dependency-injection.md](02-dependency-injection.md) он упоминается как используемый, но его **контракт нигде не был выписан**. Здесь он фиксируется (канон existlive, с заменой Datadog-членов на нейтральные — observability у SpeechAI идёт через `LogRepository`, см. [04-data-layer.md](04-data-layer.md)).

`lib/domain/repository/app_config/app_config_repository.dart`:

```dart
import 'package:speech_ai_mobile/domain/model/app_config/app_config_model.dart';
import 'package:speech_ai_mobile/domain/model/app_config/app_flavor_type.dart';

abstract class AppConfigRepository {
  /// Флейвор-резолвед конфиг: apiUrl, searchApiUrl, apiSignatureKey, appwriteProjectId, …
  AppConfigModel get config;

  /// Базовый API-URL (синоним config.apiUrl, удобный геттер).
  String get baseApiUrl;

  /// Поднять конфиг под выбранный флейвор. Вызывается в main.dart после готового DI-контейнера.
  Future<void> initialize({required AppFlavorType flavorType});

  /// Источник bearer-токена для auth-interceptor'а (§1). null → запрос идёт без Authorization.
  Future<String?> get getUserAuthIdToken;

  /// true под test-флейвором/окружением (например, чтобы отключить часть сетевой логики в тестах).
  bool get isTestEnvironment;
}
```

Реализация — `@LazySingleton(as: AppConfigRepository, env: [Environment.dev, Environment.prod, Environment.test])` (полный env-список: репозиторий нужен во всех окружениях, иначе `getIt<AppConfigRepository>()` в `ApiClient` упадёт под недостающим env).

`lib/data/repository/app_config/app_config_repository_impl.dart` (скелет):

```dart
@LazySingleton(as: AppConfigRepository, env: [Environment.dev, Environment.prod, Environment.test])
class AppConfigRepositoryImpl with BaseRepositoryHelper implements AppConfigRepository {
  AppConfigRepositoryImpl(this._config);

  final AppConfigModel _config;

  @override
  AppConfigModel get config => _config;

  @override
  String get baseApiUrl => _config.apiUrl;

  @override
  Future<void> initialize({required AppFlavorType flavorType}) async {
    // Поднять флейвор-зависимое состояние (если есть): прогреть Remote-Config-подобные значения,
    // проверить доступность бэкенда и т.п. Под SpeechAI — НЕ инициализирует Firebase Auth (см. §4).
  }

  @override
  Future<String?> get getUserAuthIdToken async {
    // existlive: вернуть Firebase ID-токен (auto-refresh).
    // SpeechAI (§4): вернуть access-JWT из AuthRepository (flutter_secure_storage); null если разлогинен.
    return null; // TODO(§4): подключить AuthRepository.
  }

  @override
  bool get isTestEnvironment => false;
}
```

Связи:

- **`config` — флейвор-резолвед.** `AppConfigModel` (интерфейс + одна `@Singleton(as: AppConfigModel, env:[prod,dev])`-реализация на `const String.fromEnvironment`) описан в [02-dependency-injection.md](02-dependency-injection.md) §7.3. Он несёт `apiUrl` **и** `searchApiUrl` per флейвор (prod/stage) — значения приходят из зашифрованных секретов через `dart-define-from-file` ([09-build-and-secrets-infra.md](09-build-and-secrets-infra.md)). `ApiClient` (§1) читает оба отсюда.
- **`initialize(flavorType:)`** вызывается в `main.dart` **после** `getIt.allReady()` (контейнер уже собран) — см. bootstrap-последовательность в [02-dependency-injection.md](02-dependency-injection.md) §«main.dart» и [05-presentation-layer.md](05-presentation-layer.md). Это место «поднять конфиг/observability после готового DI».
- **`getUserAuthIdToken`** — единственная точка, откуда auth-interceptor берёт токен. В existlive это Firebase ID-токен; под SpeechAI её бэкендит `AuthRepository` поверх `flutter_secure_storage` (§4).
- Резолв везде через `getIt<AppConfigRepository>()` (или алиас `configRepository` из `global_aliases.dart`, [02-dependency-injection.md](02-dependency-injection.md) §8).

---

## 3. REST-слой: `RequestBuilder` / `RequestBuilderHelper` + envelope (мост к 04)

Полные шаблоны REST-слоя — в [04-data-layer.md](04-data-layer.md) §7. Здесь — короткий мост, чтобы §1–2 замкнулись на реальный путь запроса.

- **`RequestBuilder<T>` / `RequestBuilderHelper<T>`** ([04-data-layer.md](04-data-layer.md) §7в) — `RequestBuilder` превращает доменный конфиг в `body`/`path`/`headers`; `RequestBuilderHelper` (mixin) резолвит конкретный builder из `getIt` и форвардит вызовы, чтобы API-класс не разводил билдеры руками. API-класс расширяет `BaseApiRepository` (§1) и подмешивает `RequestBuilderHelper<TheBuilder>`.
- **Envelope `ResponseEntity<T>` + `EntityConverter<E>`** ([04-data-layer.md](04-data-layer.md) §2–3) — каждый ответ бэкенда обёрнут в единый envelope; `ResponseEntity<T>` — генерик-обёртка, `@EntityConverter()` резолвит `T` в конкретный entity. Форма канона existlive:

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

- **Поток запроса:** доменный конфиг → `RequestBuilder` (`path`/`body`/`headers`) → API-класс шлёт через `baseClient` (§1) → `ResponseEntity<T>.fromJson(response.data)` → репозиторий заворачивает в `RepositoryResult` через `BaseRepositoryHelper.execute<T>()`. На non-2xx Dio бросает `DioException` → ветка `execute` мапит его в `RepositoryException.internal` (см. [04-data-layer.md](04-data-layer.md) §5; **нет** `ApiException`/`DaoException` — это канон existlive). Конкретный код (`unauthenticated` на 401, `notFound` на 404) — это **явный** `return RepositoryResult.error(...)` внутри callback'а после проверки `response.statusCode`.

> **`BaseMapper`** живёт в `lib/data/mapper/base_mapper.dart` (не `mapper/base/`), см. [04-data-layer.md](04-data-layer.md) §4 — упоминается здесь только чтобы зафиксировать путь, REST-слой его не трогает напрямую.

---

## 4. Адаптация под `client_backend` (ОБЯЗАТЕЛЬНО до релиза)

> **Это размеченная адаптация, не канон existlive.** existlive ходит в свой бэкенд по **Firebase ID-токену** (auto-refresh силами Firebase SDK) и **не подписывает** запросы. SpeechAI-`client_backend` устроен иначе по **двум** осям сразу — и токен-модель другая, и каждый запрос обязан быть подписан. Ниже — **структура**, которую надо надстроить над `ApiClient` (§1) и `AppConfigRepository` (§2). **Точные** имена заголовков, формат строки подписи, алгоритм HMAC и контракт токен-эндпоинтов — это **cross-project-контракт** (`mobile ↔ client_backend`); ниже приведена текущая форма из `docs/spec/backend_mobile_client_0.2.md`, но перед реализацией её надо **сверить с владельцем бэкенда** — не изобретать схему подписи «на глаз» здесь.

### 4.1 Чем SpeechAI отличается от existlive (две оси)

| Ось | existlive | SpeechAI `client_backend` |
|---|---|---|
| Идентификация запроса | только `Authorization: Bearer <firebase_id_token>` | `Authorization: Bearer <access_jwt>` **+** HMAC-подпись запроса **+** security-заголовки **+** replay-окно **+** build-gate |
| Токен-модель | Firebase ID-токен (auto-refresh силами Firebase SDK) | **собственная**: короткий **access-JWT** (~15 мин) + **opaque refresh** (~45 дней) с **ротацией** и **reuse-detection** на refresh |
| Подпись запроса | нет | **обязательна** на (почти) каждом запросе — без неё `403` ещё до исполнения endpoint'а |
| Force-update | нет | сервер сверяет build из `x-user-agent` с `min_build_number` → `426 Upgrade Required` (или `403`) |

То есть надстраиваем **две** вещи: (a) дополнительные request-интерсепторы (подпись + security-заголовки + timestamp + build-UA), и (b) `getUserAuthIdToken`, бэкенднутый `AuthRepository` поверх `flutter_secure_storage` с refresh→rotate→retry на 401.

### 4.2 (a) Дополнительные request-интерсепторы — HMAC + security-заголовки + timestamp + build-UA

Структура: **отдельный** `InterceptorsWrapper` (или цепочка), навешиваемый в `ApiClient.initBase()` **после** auth-interceptor'а из §1. Он на каждом запросе:

1. ставит `x-request-timestamp` (epoch **ms**, в пределах ±5-мин replay-окна сервера);
2. ставит security-заголовки: `x-trace-id` (uuid per request), `x-device-id` (стабильный id устройства);
3. ставит `x-user-agent` с платформой + версией + **build number** приложения (сервер сверяет build с `min_build_number` → `426`/`403` force-update);
4. вычисляет `x-request-signature = hex(HMAC-SHA256(signing_key, signature_input))` и ставит его последним (когда `body`/`path`/`timestamp` уже финализированы).

Текущая форма `signature_input` (из спеки, **сверить перед реализацией**) — конкатенация через `\n`:

```
signature_input = METHOD + "\n" + PATH + "\n" + BODY_SHA256 + "\n" + TIMESTAMP
x-request-signature = hex(HMAC-SHA256(signing_key, signature_input))
```

- **METHOD** — это **НЕ** uppercase-verb (`GET`/`POST`), а литеральная строка Dart-enum'а бэкенда (`ApiRequestMethod.get`, `ApiRequestMethod.post`, …). Третьесторонний клиент, пересчитывающий HMAC, обязан воспроизвести **эту** строку — uppercase-verb упадёт на верификации. (Та же ловушка задокументирована в Postman-коллекции бэкенда.)
- **PATH** — полный путь с query (`/api/v1/records/?limit=20`).
- **BODY_SHA256** — hex-SHA-256 сырого тела; для запросов без тела — SHA-256 пустой строки.
- **TIMESTAMP** — значение `x-request-timestamp` (epoch ms как строка).
- **signing_key** — `apiSignatureKey` из `AppConfigModel` (per флейвор, из зашифрованных секретов, [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md)).

Скелет (имена/формат — placeholder под сверку):

```dart
// lib/data/remote/api/base/security_interceptor.dart — СТРУКТУРА, не финал.
// TODO(cross-project): сверить имена заголовков, порядок и формат signature_input
// с docs/spec/backend_mobile_client_0.2.md «Заголовки запроса» + «Computation подписи»
// и с владельцем бэкенда ПЕРЕД реализацией. Не хардкодить схему «на глаз».
InterceptorsWrapper buildSecurityInterceptor(AppConfigRepository appConfig) {
  return InterceptorsWrapper(
    onRequest: (options, handler) async {
      final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
      options.headers['x-request-timestamp'] = timestamp;
      options.headers['x-trace-id'] = /* uuid v4 per request */ '';
      options.headers['x-device-id'] = /* стабильный device id */ '';
      options.headers['x-user-agent'] = /* platform + appVersion + buildNumber */ '';

      final method = /* 'ApiRequestMethod.<verb>' — НЕ uppercase! */ '';
      final path = options.uri.path + (options.uri.hasQuery ? '?${options.uri.query}' : '');
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

> **Web-deep-link исключение.** Часть endpoint'ов (`verify_email`, `verify_reset_password` — `requiresWebDeepLink = true`) HMAC/security-заголовки **не требуют** (открываются по ссылке из письма в браузере). Эти флоу идут через [13-deep-links.md](13-deep-links.md) и не подписываются — учесть при разводке interceptor'а (пропускать подпись для этих путей).

### 4.3 (b) `getUserAuthIdToken` поверх `AuthRepository` + refresh→rotate→retry

`AppConfigRepository.getUserAuthIdToken` (§2) под SpeechAI отдаёт **access-JWT** из `AuthRepository`. Структура:

- **`AuthRepository`** хранит пару `access` + `refresh` в **`flutter_secure_storage`** ([01-stack-and-tooling.md](01-stack-and-tooling.md)); контракт — `RepositoryResult`-форма ([03-domain-layer.md](03-domain-layer.md)), как у остального слоя данных.
- **`getUserAuthIdToken`** возвращает текущий access-JWT (или `null`, если разлогинен → запрос идёт без `Authorization`, §1).
- **refresh-on-401**: отдельный response-interceptor (или обёртка в `AuthRepository`): при `401` (token expired) — дёрнуть `POST /api/v1/auth/token/refresh/` с `refresh_token` → получить **новую** пару → перезаписать в secure storage → **повторить** исходный запрос. Сервер делает **ротацию** refresh-токена и **reuse-detection**: предъявление уже отозванного refresh блэклистит всю сессию — поэтому клиент обязан хранить только **последнюю** выданную пару и не гонять параллельные refresh'и (нужен single-flight lock на refresh, иначе можно сжечь собственную сессию).

Контракт токен-эндпоинта (текущая форма из спеки, **сверить**):

| Поле ответа | Смысл |
|---|---|
| `access_token` | короткий JWT для `Authorization: Bearer` |
| `refresh_token` | opaque-токен для `POST /api/v1/auth/token/refresh/` |
| `access_token_valid_timestamp` | ISO-8601 UTC — до когда валиден access |
| `refresh_token_valid_timestamp` | ISO-8601 UTC — до когда валиден refresh |

Алгоритм клиента: использовать access до `access_token_valid_timestamp`; на истечении (или на `401 token_expired`) — refresh → rotate → retry. При провале refresh (refresh истёк / блэклистнут) — разлогин → экран входа.

### 4.4 Обработка статусов: 503 «initializing», 429, 426

Клиент обязан понимать стартовые/защитные коды сервера (форма — из спеки):

- **`503 service_unavailable` («initializing»)** — сразу после деплоя на свежую БД сервер отдаёт retryable-503, пока идёт out-of-band provisioning схемы. Клиент обязан считать его **retryable** (короткий backoff + повтор), а **не** outage. (Не путать с maintenance — тот сигналится `200` + `system_status = "maintenance"`.)
- **`429 Too Many Requests`** — превышен per-category rate-limit (auth 10 req/60s и т.п.). Уважать backoff (по `Retry-After`, если есть), не долбить.
- **`426 Upgrade Required`** (или `403` от security-pipeline) — build приложения ниже `min_build_number`: показать force-update-экран, увести в стор. Build для гейта берётся из `x-user-agent` (§4.2).

### 4.5 Что **не** переносить из existlive

- **Firebase Auth.** SpeechAI не использует Firebase ID-токен как bearer — токен-модель собственная (§4.3). `AppConfigRepository.getUserAuthIdToken` бэкендит `AuthRepository`, а не Firebase SDK. (Firebase у SpeechAI используется бэкендом под Remote Config, не клиентом под auth.)
- **Неподписанные запросы.** В existlive подпись не считается; здесь без HMAC-подписи запрос отвергается `403` до исполнения — interceptor §4.2 обязателен.

> **FLAG (cross-project).** §4.2–4.3 описывают **структуру**. Точные имена заголовков, формат `signature_input`, конкретный HMAC-вариант, путь и тело токен-эндпоинта — **не финальны в этом документе**: их источник правды — `client_backend` (`docs/spec/backend_mobile_client_0.2.md` + security-pipeline) и владелец бэкенда. Перед реализацией — сверить и согласовать; в коде оставить `TODO(cross-project)`, как в скелете §4.2.

---

## 5. Сетевое состояние и lifecycle-driven refresh

> **Зачем эта секция.** Сетевой контур из §1–4 (HMAC + custom access/refresh JWT, `ApiClient`-интерсепторы, `401 → refresh`) описывает поведение *в момент запроса*. Здесь добавляются два ортогональных наблюдателя, питающих этот контур контекстом: (1) `ConnectivityRepository` — реактивный поток «онлайн/офлайн» для UX-деградации и (2) app-lifecycle observer, который на возврате приложения из background инициирует превентивную проверку/refresh access-токена. Оба — best-effort слой поверх обязательного контура; ни один не заменяет реактивную обработку ошибок в `ApiClient`.

> **Канон existlive.** В existlive `connectivity_plus`/`firebase_messaging` отсутствуют, а refresh токена делегирован Firebase SDK — поэтому готового кода под эти две задачи нет. Но переносимы 1:1: (1) форма репозитория (`with BaseRepositoryHelper`, `execute(...) → RepositoryResult`, `@LazySingleton(as: Interface)`, `rxdart`-поток) — ровно как `DeepLinkRepositoryImpl`; (2) форма lifecycle-наблюдателя (`WidgetsBindingObserver` → `bloc.add(AppResumed())` с re-entrancy guard) — ровно как `finance_management_page` в existlive.

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
- [ ] `ApiClient.initBase()` — Dio, `baseUrl = ${config.apiUrl}/api/`, 30-сек таймауты, JSON; **один** auth-`InterceptorsWrapper`, читающий `getUserAuthIdToken` async per request → `Bearer` (null → снять `Authorization`); `onResponse`/`onError` — пасс-тру (debug).
- [ ] `ApiClient.initSearch()` — второй Dio **без** auth-interceptor'а, `baseUrl = ${config.searchApiUrl}/api/`; выкинуть, если второго хоста нет.
- [ ] `BaseApiRepository` отдаёт `baseClient` / `searchClient` геттерами; API-классы наследуют его.
- [ ] `AppConfigRepository` (контракт: `config` / `baseApiUrl` / `initialize(flavorType:)` / `getUserAuthIdToken` / `isTestEnvironment`) определён в `domain/`; импл — `@LazySingleton(as: AppConfigRepository, env:[dev,prod,test])`; резолв через `getIt` / алиас `configRepository`.
- [ ] `AppConfigModel` несёт `apiUrl` **и** `searchApiUrl` (+`apiSignatureKey`) per флейвор ([02-dependency-injection.md](02-dependency-injection.md) §7.3, [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md)); `initialize(flavorType:)` вызывается в `main.dart` после `getIt.allReady()`.
- [ ] REST-мост: `RequestBuilder`/`RequestBuilderHelper` + `ResponseEntity<T>`/`EntityConverter<E>` — по [04-data-layer.md](04-data-layer.md) §2–3, §7; на non-2xx Dio бросает `DioException` → `RepositoryException.internal` через `BaseRepositoryHelper.execute` (нет `ApiException`/`DaoException`); конкретный код (`unauthenticated`/`notFound`) — явный `return RepositoryResult.error(...)` в callback'е.
- [ ] **§4 (до релиза):** дополнительный security-interceptor — `x-request-timestamp` (epoch ms, ±5 мин), `x-trace-id`, `x-device-id`, `x-user-agent` (с build), `x-request-signature` (HMAC-SHA256 по `METHOD\nPATH\nBODY_SHA256\nTIMESTAMP`, METHOD = `ApiRequestMethod.<verb>`, **не** uppercase); пропуск подписи для web-deep-link endpoint'ов.
- [ ] **§4 (до релиза):** `getUserAuthIdToken` бэкендит `AuthRepository` поверх `flutter_secure_storage` (access-JWT + opaque refresh); refresh→rotate→retry на 401 через `POST /api/v1/auth/token/refresh/`; single-flight lock на refresh (reuse-detection блэклистит сессию); разлогин при провале refresh.
- [ ] **§4 (до релиза):** обработка `503 initializing` (retryable backoff), `429` (уважать backoff), `426`/`403` (force-update-экран).
- [ ] **FLAG:** точный контракт HMAC (имена заголовков, `signature_input`, алгоритм) и токен-эндпоинта **сверены с `client_backend` (`docs/spec/`) и владельцем** до реализации; в коде — `TODO(cross-project)`, не изобретать схему здесь.
