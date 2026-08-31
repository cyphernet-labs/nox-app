# 15 — Push-уведомления (FCM)

> **Назначение:** зафиксировать единый механизм push-уведомлений в `nox_app` поверх Firebase Cloud Messaging — подключение `firebase_messaging`, получение и ротация device-токена, его регистрация/разрегистрация на бэкенде NOX (`POST`/`DELETE /api/v1/user/push_notification/` — импортированный REST-пример: бэкенд у NOX выбран — Go-сервер `noxd` (`client_backend/`, встроенный SQLite) и контракт v0, — но **регистрация push-токена в нём открыта**: `push.register` — этап 2, §8.2 контракта, заблокирован Q2/Q13, поэтому §6 подлежит замене на реальный контракт по закрытии Q2), три режима приёма сообщений (foreground / background / terminated), разрешения (iOS APNs, Android 13+ `POST_NOTIFICATIONS`) и навигацию по тапу. Слои — по канону блюпринта: `PushTokenRepository` (интерфейс в `lib/domain/repository/`, impl `with BaseRepositoryHelper`, методы возвращают `RepositoryResult<T>`), DI-регистрация `@LazySingleton(as: …)`, подключение в `main.dart` + `AppRoot`-observer.
> **Когда читать:** перед поднятием папки push-уведомлений (`lib/{domain,data}/.../push/`), перед добавлением `firebase_messaging` в `pubspec.yaml`, при реализации регистрации device-токена на бэкенде, при разводке навигации «пользователь тапнул по уведомлению», а также при добавлении нового типа push-payload'а от серверной стороны.
> **Связанные документы:** [13-deep-links.md](13-deep-links.md) (навигация по тапу — общий механизм маршрутизации `AppRootBloc`, `GlobalKey<NavigatorState>`, dispatch-table; push-tap переиспользует его), [14-networking-and-auth.md](14-networking-and-auth.md) (сетевой вызов register/unregister — HMAC + access/refresh JWT, security-заголовки — **не переизобретать**; push-endpoint'ы идут через полный security-pipeline; конкретная модель подписи/токенов — пример: этап 1 контракта v0 работает **без авторизации**, а модель аутентификации/пейринга этапа 2 ещё не финализирована), [04-data-layer.md](04-data-layer.md) (`BaseRepositoryHelper.execute`, мапперы, REST-слой `RequestBuilder`/`ResponseEntity`), [05-presentation-layer.md](05-presentation-layer.md) (`AppRoot`/`AppRootBloc`, `BaseBloc.executeLogic`, потребление `RepositoryResult` через `match`), [03-domain-layer.md](03-domain-layer.md) (`RepositoryResult`, `RepositoryException`, контракты репозитория), [02-dependency-injection.md](02-dependency-injection.md) (`configureDependencies`, регистрация репозитория, bootstrap `main.dart`), [01-stack-and-tooling.md](01-stack-and-tooling.md) (версии `firebase_core`/`firebase_messaging`/`permission_handler`).

---

## 0. Идея: «получить токен → зарегистрировать на бэкенде → принять и смаршрутизировать сообщение»

Документ отвечает на четыре подвопроса:

1. **Откуда берётся device-токен** — `firebase_messaging` (`getToken()` + поток `onTokenRefresh`), под капотом APNs (iOS) / FCM (Android). §2, §4.
2. **Как токен попадает на бэкенд** — через `PushTokenRepository`, который шлёт `POST /api/v1/user/push_notification/` (register) и `DELETE …` (unregister на logout) по контракту §6 (импортированный REST-пример — реальная команда контракта v0 `push.register` (§8.2) открыта по Q2/Q13; заменить на неё, когда Q2 закроют). Сетевой вызов идёт через тот же подписанный сетевой слой, что и весь API ([14-networking-and-auth.md](14-networking-and-auth.md)). §6, §7.
3. **Как принимаются сообщения** — три канала: foreground (`onMessage`), background-tap (`onMessageOpenedApp`), terminated/cold-start (`getInitialMessage`) + top-level background-handler (`onBackgroundMessage`). §5.
4. **Что происходит по тапу** — извлекаем routing-поля из `data`-payload'а и **переиспользуем** маршрутизатор deep-link'ов из [13-deep-links.md](13-deep-links.md), а не строим второй. §8.

> **Единый пакет.** Все пути — `lib/...` внутри одного пакета `nox_app` (worked example). Импорты — полные `package:nox_app/...`, относительные `../` запрещены (кроме `part`-директив).

> **Зона ответственности бэкенда NOX в этом документе — только регистрация/разрегистрация токена.** Сама эмиссия push-**событий** (что и когда отправлять) — отдельный серверный контракт, **не** покрываемый этим документом; на стороне мобильного клиента — только `POST`/`DELETE /api/v1/user/push_notification/` (импортированный REST-пример; контракт v0 держит для этого одну команду `push.register` (§8.2), и она открыта по Q2/Q13). Контракт payload'ов доставляемых уведомлений (§9) — на серверной стороне; мобильный handler читает их `data`-поля, но источник правды по их форме — серверная спека.

> **NOX-нюанс приватности (предварительно).** Push приходят только по «своим» чатам — тем, что пользователь создал, где писал или которые открывал; включается единым toggle'ом. Точные правила охвата уточняются при закрытии Q2 — контракт v0 push-событий пока не описывает.

**Стадии пайплайна:**

```
1. main.dart bootstrap: Firebase.initializeApp() + регистрация top-level
   FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler)
        │
        ▼
2. После login (есть access-JWT): PushTokenRepository.initialize()
        запросить разрешение (iOS APNs / Android 13+ POST_NOTIFICATIONS)
        getToken() → PushTokenRepository.register(...) → POST /api/v1/user/push_notification/
        подписка на onTokenRefresh → re-register при ротации
        │
        ▼
3. Приём сообщений (три канала):
        onMessage          → foreground (приложение открыто) — показать in-app / локальное уведомление
        onMessageOpenedApp → tap из background — навигация
        getInitialMessage  → tap из terminated (cold start) — навигация
        onBackgroundMessage→ top-level isolate (DI недоступен) — лёгкая обработка/локальное уведомление
        │
        ▼
4. Навигация по тапу: routing-поля из message.data
        → переиспользовать маршрутизатор deep-link (AppRootBloc, GlobalKey<NavigatorState>) — §8, [13-deep-links.md](13-deep-links.md)
        │
        ▼
5. Logout: PushTokenRepository.unregister(...) → DELETE /api/v1/user/push_notification/
        затем dispose() — снять подписки
```

---

## 1. Контракт и инварианты

- **Регистрация токена требует аутентификации.** В примере §6 `POST`/`DELETE /api/v1/user/push_notification/` идут с обязательным `Authorization: Bearer <access_jwt>` **и** полным security-pipeline (HMAC-подпись + security-заголовки) — иначе `401`/`403` ещё до исполнения endpoint'а. Сам per-request Bearer/HMAC — часть примера, а не контракта v0: там аутентификация **одноразовая при установлении WebSocket-соединения** (§9 контракта), и её модель — этап 2. Инвариант, переживающий замену контракта: `register(...)` дёргается **только после успешного login** (когда сессия уже аутентифицирована), а не на старте приложения.
- **Сетевой слой не переизобретается.** Запрос строится тем же `RequestBuilder` → `baseClient` → `ResponseEntity<T>`, что и любой другой API-вызов; подпись/токен ставит security-interceptor из [14-networking-and-auth.md](14-networking-and-auth.md) §4. Push-репозиторий **не** трогает заголовки/подпись напрямую. **Оговорка транспорта:** в контракте v0 команды идут не по REST, а **WebSocket-конвертом** (клиент конверта приехал в фазе 026 — `NoxSocketClient`, `lib/data/remote/socket/nox_socket_client.dart`; целевая форма транспорта — **wss:443 с пиннингом ключа**, в коде её пока нет: `WebSocketChannelFactory` открывает голый `IOWebSocketChannel.connect`, а в окружении `dev` (флейвор `stage`) адрес — plain-ws на локальный `noxd`), REST остаётся только под blob-обмен; когда `push.register` (§8.2) откроют, регистрация станет командой конверта, а не HTTP-вызовом — но правило «репозиторий отдаёт только тело, транспортную обвязку ставит слой ниже» не меняется.
- **Тело запроса — ровно два ключа.** Клиент шлёт только `push_notification_provider` + `push_notification_token`. Всё остальное (`device_id`, `platform`, …) проставляет сервер из заголовков/хардкодом — см. load-bearing-нюанс в §6.4. Не добавляйте в body «лишние» поля схемы — endpoint их не читает.
- **Ротация токена → повторная регистрация.** На каждое событие `onTokenRefresh` повторяем `register(...)` с новым токеном. Сервер идемпотентен по composite-UNIQUE `(user, device_id)` (пример — точный ключ дедупликации финализируется вместе с `push.register`, §8.2 контракта / Q2) — повторный POST обновляет строку, не плодит дубли.
- **Background-handler — top-level функция, DI недоступен.** `onBackgroundMessage` исполняется в отдельном isolate, где `getIt` не поднят. Handler аннотируется `@pragma('vm:entry-point')`, делает **минимум** (логирование / показ локального уведомления) и **не** обращается к репозиториям через `getIt`.
- **Навигация по тапу — через единый маршрутизатор.** Tap по уведомлению маршрутизируется тем же механизмом, что и deep-link ([13-deep-links.md](13-deep-links.md)): routing-поля из `message.data` → `AppRootBloc` → `GlobalKey<NavigatorState>`. Второго навигатора не заводим.
- **Все мутации репозитория возвращают `RepositoryResult<T>`** (`success(data: …)` / `error(exception: …)`), как и весь остальной слой данных ([04-data-layer.md](04-data-layer.md) §5).
- **push (`firebase_messaging`) — mobile-only feature-gated; на десктопах вендорский push не используется по решению Q2 (доставка — резидентный процесс с постоянным сокетом контракта v0).** На Windows / Linux / macOS push деградирует в no-op (§10) — `firebase_*` подключаются как platform-conditional (mobile-only) deps, desktop-env регистрирует no-op `PushTokenRepository`.

---

## 2. Нативная интеграция и зависимости (обязательна)

Пакеты в `pubspec.yaml` (версии пинить по `firebase_core` constraint, см. [01-stack-and-tooling.md](01-stack-and-tooling.md)):

| Пакет | Линейка | Роль |
|---|---|---|
| `firebase_core` | `^4.x` | Инициализация Firebase в `main.dart` |
| `firebase_messaging` | `^16.x` (совместима с `firebase_core ^4.x`) | FCM: токен, потоки сообщений, разрешения |
| `permission_handler` | `^12.x` | Явный запрос `POST_NOTIFICATIONS` (Android 13+); опционален, можно обойтись `requestPermission()` плагина |
| `firebase_messaging` (background) | — | top-level `@pragma('vm:entry-point')`-handler |

> **`firebase_core` инициализируется явно.** Правило блюпринта: `FirebaseMessaging` требует инициализированного `Firebase`, поэтому в `nox_app` `Firebase.initializeApp()` вызывается **явно** в bootstrap (§7.1), до регистрации background-handler'а. Ленивая/неявная инициализация firebase-плагинов для FCM не годится.

### Android — `android/app/src/main/AndroidManifest.xml` + `build.gradle`

- Подключить плагин `com.google.gms.google-services` (через `google-services.json` в `android/app/`, выдаётся Firebase-консолью per флейвор — см. [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md)).
- `minSdkVersion` — по требованию `firebase_messaging` (актуально ≥ 21; уточнить по версии плагина).
- **Android 13+ (`API 33`):** разрешение `POST_NOTIFICATIONS` рантайм-запрашивается (§3); декларация в манифесте добавляется плагином автоматически.
- (Опционально) `<meta-data>` для дефолтного канала уведомлений и иконки:

`android/app/src/main/AndroidManifest.xml`:

```xml
<meta-data
    android:name="com.google.firebase.messaging.default_notification_channel_id"
    android:value="default_channel" />
<meta-data
    android:name="com.google.firebase.messaging.default_notification_icon"
    android:resource="@drawable/ic_notification" />
```

### iOS — APNs + capabilities

- В Xcode включить capability **Push Notifications** и **Background Modes → Remote notifications**.
- Загрузить APNs-ключ (или сертификат) в Firebase-консоль (Project Settings → Cloud Messaging → APNs).
- `GoogleService-Info.plist` в `ios/Runner/` per флейвор ([09-build-and-secrets-infra.md](09-build-and-secrets-infra.md)).
- iOS отдаёт FCM-токен **только после** выдачи APNs-токена и разрешения пользователя — поэтому на iOS `requestPermission()` обязателен **до** `getToken()` (§3).

> **Без нативной декларации токен не выдаётся.** Как и с deep-link'ами ([13-deep-links.md](13-deep-links.md) §2), нативная часть — обязательное предусловие: без `google-services.json` / `GoogleService-Info.plist` + APNs-ключа `getToken()` вернёт `null`/бросит.

---

## 3. Разрешения (iOS APNs, Android 13+ POST_NOTIFICATIONS)

Запрос разрешения — **первый** шаг `initialize()`, до `getToken()`:

- **iOS:** `FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true)` — открывает системный диалог APNs. Без него токен на iOS не выдаётся.
- **Android < 13:** уведомления разрешены по умолчанию — диалога нет, `requestPermission()` резолвится в `authorized` без UI.
- **Android 13+ (`API 33`):** требуется рантайм-разрешение `POST_NOTIFICATIONS`. Его покрывает либо `FirebaseMessaging.requestPermission()` (плагин делегирует на нативный диалог), либо явно `permission_handler` (`Permission.notification.request()`) — выбрать одно, не дублировать.

Результат — `AuthorizationStatus`; при `denied` токен не запрашиваем, регистрацию пропускаем (логируем через `LogRepository`, не падаем):

`lib/data/repository/push/push_token_repository_impl.dart` (фрагмент `initialize`):

```dart
final settings = await _messaging.requestPermission(
  alert: true,
  badge: true,
  sound: true,
);
if (settings.authorizationStatus == AuthorizationStatus.denied) {
  // Пользователь отказал — не запрашиваем токен, не регистрируем. Не ошибка флоу.
  return RepositoryResult.success(data: false);
}
```

> **Запрашивать разрешение в правильный момент.** Системный диалог лучше показывать не на «холодном» старте, а после явного пользовательского действия/онбординга (UX-практика). Технически `initialize()` дёргается из presentation-слоя (§7.3) — место вызова определяет продукт, репозиторий лишь предоставляет метод.

---

## 4. Доменный слой — `PushTokenRepository` + модели

### 4.1 Модель токена

`PushTokenModel` — доменная модель того, что клиент знает о своём токене. `@freezed`, доменные типы (enum `PushProvider`, не сырая строка). Маппинг enum ↔ строка allowlist (`firebase`/`apns`/`webpush`) — в маппере ([04-data-layer.md](04-data-layer.md) §4) либо тонким геттером.

`lib/domain/model/push/push_token_model.dart`:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'push_token_model.freezed.dart';

@freezed
abstract class PushTokenModel with _$PushTokenModel {
  const factory PushTokenModel({
    required String token,
    @Default(PushProvider.firebase) PushProvider provider,
  }) = _PushTokenModel;
}

/// Closed allowlist of the §6 example register contract: push_notification_provider in
/// {firebase, apns, webpush}. The real contract v0 command (push.register, 8.2) is still
/// open - Q2/Q13 - so this allowlist is a placeholder, not the wire truth.
enum PushProvider { firebase, apns, webpush }
```

> **`provider` на мобиле — всегда `firebase`.** FCM выдаёт единый токен и под Android, и под iOS (APNs прячется за FCM). Значения `apns`/`webpush` присутствуют в allowlist бэкенда (§6) ради других клиентов, но мобильный FCM-клиент шлёт `firebase`. Enum держим полным, чтобы маппер был тотальным.

### 4.2 Доменная push-сообщение-модель (для навигации)

Принятое сообщение нормализуется в типизированную модель — её потребляет маршрутизатор тапа (§8). Держим минимум: `title`/`body` (для in-app-показа) + `data`-карта routing-полей.

`lib/domain/model/push/push_message_model.dart`:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'push_message_model.freezed.dart';

@freezed
abstract class PushMessageModel with _$PushMessageModel {
  const factory PushMessageModel({
    String? title,
    String? body,
    @Default(<String, String>{}) Map<String, String> data, // routing-поля payload'а (см. §9)
  }) = _PushMessageModel;
}
```

### 4.3 Контракт репозитория

`lib/domain/repository/push/push_token_repository.dart`:

```dart
import 'package:nox_app/domain/model/push/push_message_model.dart';
import 'package:nox_app/domain/model/push/push_token_model.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

abstract class PushTokenRepository {
  /// Разрешение + первый getToken + подписки на потоки. Вызывается ПОСЛЕ login (есть access-JWT).
  Future<RepositoryResult<bool>> initialize();

  /// Зарегистрировать токен на бэкенде: POST /api/v1/user/push_notification/ (§6.1).
  Future<RepositoryResult<bool>> register({required PushTokenModel token});

  /// Разрегистрировать токен на бэкенде: DELETE /api/v1/user/push_notification/ (§6.2). Идемпотентно.
  Future<RepositoryResult<bool>> unregister({required PushTokenModel token});

  /// Текущий FCM device-токен (или null, если ещё не выдан / разрешение отклонено).
  Future<RepositoryResult<String?>> currentToken();

  /// foreground-сообщения (приложение открыто) — onMessage.
  Stream<PushMessageModel> watchForegroundMessages();

  /// tap по уведомлению из background/terminated — onMessageOpenedApp + getInitialMessage.
  Stream<PushMessageModel> watchMessageOpened();

  /// ротация токена (FCM перевыпустил) — onTokenRefresh; презентация повторяет register(...).
  Stream<String> watchTokenRefresh();

  /// Снять подписки, закрыть стримы. Вызывается на logout (после unregister).
  Future<RepositoryResult<bool>> dispose();
}
```

---

## 5. Три режима приёма сообщений + background-handler

| Канал | API `firebase_messaging` | Состояние приложения | Что делаем |
|---|---|---|---|
| Foreground | `FirebaseMessaging.onMessage` | открыто, на экране | эмитим в `watchForegroundMessages()` → in-app-баннер / локальное уведомление |
| Background-tap | `FirebaseMessaging.onMessageOpenedApp` | свёрнуто, пользователь тапнул по системному уведомлению | эмитим в `watchMessageOpened()` → навигация (§8) |
| Terminated/cold-start | `FirebaseMessaging.instance.getInitialMessage()` | убито, открыто тапом по уведомлению | one-shot: то же, что background-tap → навигация (§8) |
| Background-data (isolate) | `FirebaseMessaging.onBackgroundMessage(handler)` | свёрнуто/убито, **data-only** push | top-level handler, DI недоступен, лёгкая обработка |

> **`onMessage` НЕ показывает уведомление сам.** Когда приложение в foreground, iOS/Android по умолчанию **не** рисуют системное уведомление — приходит только `onMessage`-callback. Если нужен баннер в foreground — показать его руками (in-app-виджет или `flutter_local_notifications`, если решим его подключить). На background/terminated систему рисует уведомление ОС из `notification`-блока payload'а.

### Top-level background-handler

`lib/data/repository/push/push_background_handler.dart`:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Top-level (вне класса) — требование плагина: исполняется в отдельном isolate.
/// DI (getIt) здесь НЕ поднят — никаких репозиториев. Только Firebase + лёгкая работа.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Если в isolate нужен Firebase — поднять заново (контейнер изолирован):
  await Firebase.initializeApp();
  // Здесь: запись в локальный лог-буфер / показ локального уведомления (flutter_local_notifications),
  // НО без обращения к getIt / репозиториям. Тяжёлую работу — отложить на возврат в foreground.
}
```

Регистрация — в bootstrap, до `runApp` (§7.1).

---

## 6. Бэкенд-контракт регистрации токена (пример — TBD)

> **Весь §6 — импортированный REST-пример, а не контракт NOX.** Бэкенд выбран (Go-сервер `noxd`, контракт v0), но **именно регистрация push-токена в нём открыта**: контракт держит для неё одну команду `push.register` (§8.2, этап 2) и помечает её 🔴 Q2 («как устройство регистрирует токен и как ключ push-сервера попадает на устройство») + Q13 (контракт с relay). Направление, уже зафиксированное в реестре Q2: токен уезжает **непрозрачным blob'ом, зашифрованным ключом push-сервера**, — то есть двух ключей открытым текстом (`push_notification_provider`/`push_notification_token`) в финальной форме, скорее всего, не будет. Конкретные endpoint'ы, тело запроса, набор security-заголовков, коды ошибок, rate-limit и серверные правила записи (§6.4) ниже — реалистичный образец того, *как* клиент регистрирует device-токен. Паттерн (репозиторий шлёт только тело, транспортную обвязку ставит слой ниже) — обязателен; конкретный контракт подставляется по закрытии Q2.

Сетевой вызов идёт через подписанный слой [14-networking-and-auth.md](14-networking-and-auth.md) §4 — push-репозиторий передаёт только тело, заголовки/подпись ставит security-interceptor.

### 6.1 `POST /api/v1/user/push_notification/` — регистрация / обновление

| Аспект | Значение |
|---|---|
| Метод + путь | `POST /api/v1/user/push_notification/` |
| Аутентификация | access-JWT **обязателен** (`Authorization: Bearer …`); нет/невалиден/expired → `401` |
| HMAC + security-заголовки | HMAC-подпись **обязательна**. В этом примере запрос несёт security-заголовки `x-trace-id`, `x-request-timestamp`, `x-request-signature`, `x-user-agent` (обязательны — проблема любого → `403` до проверки HMAC) + `x-device-id`. `x-device-id` — **strongly-recommended, но формально опционален** в wire-контракте; именно из него сервер берёт `device_id` (§6.4), поэтому без стабильного непустого `x-device-id` различение устройств ломается. Точный набор и обязательность заголовков — пример, финализируется вместе с `push.register` (Q2) |
| Тело (ровно 2 ключа, оба обязательны) | `{"push_notification_provider": "firebase", "push_notification_token": "<token>"}` |
| Валидация | `push_notification_provider` ∈ `{firebase, apns, webpush}`; `push_notification_token` непустой, ≤ 4096 байт |
| Успех | `200 OK`, `data` = **пустой объект** `{}`. На клиенте ответ разбирается общим envelope `ResponseEntity{success, error, data}` (`lib/data/entity/base/response_entity.dart`), где `error` — `ErrorWireEntity{code, message}` контракта v0 §2.1; распаковка — `BaseRepositoryHelper.unwrapEnvelope<T>(response, what)` |
| Rate limit | категория `pushTokenWrite`: **20 req / 60 s per user** (общий bucket с DELETE) |

Коды ошибок:

| Код | Тип | Когда |
|---|---|---|
| `400` | `bad_request` | body null / не JSON-объект / пустое поле → `"Invalid or missing push notification data"`; провайдер вне allowlist → `"push_notification_provider must be one of: firebase, apns, webpush"`; токен > 4096 байт → `"push_notification_token exceeds maximum length (4096 bytes)"` |
| `401` | `unauthorized` | `"Missing or invalid authentication token"` |
| `403` | `forbidden` | `"Missing or invalid security headers"` (отсутствует/невалиден обязательный security-заголовок, либо провал HMAC/replay-окна) |
| `429` | `rate_limited` | `"Limited to 20 requests per 60-second window per authenticated user"` |
| `503` | `service_unavailable` | сбой инфраструктуры/хранилища → `"Push registration service temporarily unavailable"` |

### 6.2 `DELETE /api/v1/user/push_notification/` — разрегистрация

| Аспект | Значение |
|---|---|
| Метод + путь | `DELETE /api/v1/user/push_notification/` |
| Аутентификация / HMAC | те же требования, что у POST; header-проблема → `403` |
| Тело | идентично POST — те же 2 ключа |
| Идемпотентность | unknown / уже-удалённый токен → всё равно `200`; сервер не раскрывает, существовал ли токен |
| Успех | `200 OK`, `data` = `{}` |
| Rate limit | тот же bucket `pushTokenWrite` (20 req / 60 s, общий с POST) |

Коды ошибок — зеркальны POST (`400`/`401`/`403`/`429`; `503` → `"Push registry temporarily unavailable"`).

### 6.3 Когда что дёргать

- **`register(...)`** — после успешного login (есть токен-пара) и при каждом `onTokenRefresh`.
- **`unregister(...)`** — на logout, **до** очистки токен-пары (запрос требует валидного access-JWT). Затем `dispose()`.

### 6.4 Load-bearing-нюанс: что реально пишется в БД (не из body)

Клиент шлёт **только** 2 ключа; остальное проставляет сервер — это важно учитывать, чтобы **не** пытаться слать «лишние» поля:

1. **`device_id` — из заголовка `x-device-id`** (`request.deviceId`), а не из body. При **пустом значении** заголовка сервер пишет `device_id=null` — тогда дедупликация на стороне сервера (в этом примере) идёт по fallback-ключу `(user, push_token)` вместо `(user, device_id)`: строки не сливаются в одну, но при ротации FCM-токена создаётся новая строка вместо обновления существующей (старая остаётся сиротой), и различение устройств по `device_id` теряется. **Вывод для клиента:** security-interceptor [14-networking-and-auth.md](14-networking-and-auth.md) §4.2 обязан слать стабильный **непустой** `x-device-id` — иначе несколько устройств одного пользователя затрут друг друга. Это единственная клиентская «ручка», влияющая на различение устройств.
2. **`platform` хардкодится сервером в `'mobile'`** (расходится с задокументированным enum схемы `{ios, android, web}` — известное расхождение реализации). Клиент `platform` **не** передаёт.
3. **`app_version` / `os_version` / `locale` / `timezone` / `environment` этим endpoint'ом НЕ заполняются** — даже если они есть в серверной схеме (пример — финализируется вместе с `push.register`, Q2), регистрация токена их не пишет. Клиенту слать их некуда (в body-контракте их нет).

> **Серверная коллекция токенов — internal-only (пример — TBD).** Мобильный клиент её напрямую не читает — только пишет токен через `POST`/`DELETE`. Публичного read-API у неё нет.

---

## 7. Слой данных + DI + подключение в presentation

### 7.1 bootstrap в `main.dart` — Firebase + background-handler

`Firebase.initializeApp()` и регистрация top-level background-handler'а — **до** `runApp`, рядом с `configureDependencies` ([05-presentation-layer.md](05-presentation-layer.md) §6.3). `PushTokenRepository.initialize()` здесь **не** дёргаем — он требует login (§7.3).

`lib/main.dart` (фрагмент, дополняет канон [05-presentation-layer.md](05-presentation-layer.md) §6.3):

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:nox_app/data/repository/push/push_background_handler.dart';
// ... остальные импорты bootstrap'а — см. 05-presentation-layer.md §6.3

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // 1) Firebase — ЯВНО (правило блюпринта). Нужен для FirebaseMessaging.
      await Firebase.initializeApp(/* options per флейвор, если используем DefaultFirebaseOptions */);

      // 2) background-handler — top-level, до runApp.
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      final env = AppFlavor.getFlavor() == AppFlavorType.prod ? Environment.prod : Environment.dev;
      await configureDependencies(env);
      await getIt.allReady();

      runApp(const AppRoot());
    },
    (error, stack) {
      if (getIt.isRegistered<LogRepository>()) {
        getIt<LogRepository>().error(target: 'main', error: error, stackTrace: stack);
      }
    },
  );
}
```

### 7.2 `PushTokenRepositoryImpl` — impl `with BaseRepositoryHelper`

`@LazySingleton(as: PushTokenRepository)`. Внутри — `FirebaseMessaging.instance` + `PublishSubject` под каждый стрим (как `BehaviorSubject` в `DeepLinkRepositoryImpl`, [13-deep-links.md](13-deep-links.md) §4.4). Сетевой register/unregister — через инжектированный API-класс (`PushTokenApi`, строится как любой API-класс в [04-data-layer.md](04-data-layer.md) §7); ниже он обозначен как `_pushTokenApi`, тело запроса — `{push_notification_provider, push_notification_token}` (§6).

`lib/data/repository/push/push_token_repository_impl.dart`:

```dart
import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:injectable/injectable.dart';
import 'package:rxdart/rxdart.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/data/mapper/push/push_message_mapper.dart';
import 'package:nox_app/data/remote/api/push/push_token_api.dart';
import 'package:nox_app/domain/model/push/push_message_model.dart';
import 'package:nox_app/domain/model/push/push_token_model.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/push/push_token_repository.dart';

@LazySingleton(as: PushTokenRepository)
class PushTokenRepositoryImpl with BaseRepositoryHelper implements PushTokenRepository {
  PushTokenRepositoryImpl(this._pushTokenApi, this._pushMessageMapper);

  final PushTokenApi _pushTokenApi;
  final PushMessageMapper _pushMessageMapper;

  final _messaging = FirebaseMessaging.instance;
  final _foreground = PublishSubject<PushMessageModel>();
  final _opened = PublishSubject<PushMessageModel>();
  final _tokenRefresh = PublishSubject<String>();
  final _subs = <StreamSubscription>[];

  @override
  Future<RepositoryResult<bool>> initialize() => execute<bool>(() async {
        // 1) разрешение (iOS APNs / Android 13+) — §3
        final settings = await _messaging.requestPermission(alert: true, badge: true, sound: true);
        if (settings.authorizationStatus == AuthorizationStatus.denied) {
          return RepositoryResult.success(data: false);
        }

        // 2) подписки на три канала + ротацию
        _subs.add(FirebaseMessaging.onMessage.listen(
          (m) => _foreground.add(_pushMessageMapper.toModel(entity: m)),
        ));
        _subs.add(FirebaseMessaging.onMessageOpenedApp.listen(
          (m) => _opened.add(_pushMessageMapper.toModel(entity: m)),
        ));
        _subs.add(_messaging.onTokenRefresh.listen(_tokenRefresh.add));

        // 3) cold-start tap (terminated) — one-shot
        final initial = await _messaging.getInitialMessage();
        if (initial != null) {
          _opened.add(_pushMessageMapper.toModel(entity: initial));
        }

        return RepositoryResult.success(data: true);
      });

  @override
  Future<RepositoryResult<String?>> currentToken() => execute<String?>(() async {
        final token = await _messaging.getToken();
        return RepositoryResult.success(data: token);
      });

  @override
  Future<RepositoryResult<bool>> register({required PushTokenModel token}) => execute<bool>(() async {
        // POST /api/v1/user/push_notification/ — тело {push_notification_provider, push_notification_token}.
        // Заголовки/HMAC/Bearer ставит security-interceptor (14-networking-and-auth.md §4) — здесь не трогаем.
        await _pushTokenApi.register(provider: token.provider.name, token: token.token);
        return RepositoryResult.success(data: true);
      });

  @override
  Future<RepositoryResult<bool>> unregister({required PushTokenModel token}) => execute<bool>(() async {
        // DELETE /api/v1/user/push_notification/ — идемпотентно (unknown-токен → всё равно 200, §6.2).
        await _pushTokenApi.unregister(provider: token.provider.name, token: token.token);
        return RepositoryResult.success(data: true);
      });

  @override
  Stream<PushMessageModel> watchForegroundMessages() => _foreground.stream;

  @override
  Stream<PushMessageModel> watchMessageOpened() => _opened.stream;

  @override
  Stream<String> watchTokenRefresh() => _tokenRefresh.stream;

  @override
  Future<RepositoryResult<bool>> dispose() => execute<bool>(() async {
        for (final s in _subs) {
          await s.cancel();
        }
        _subs.clear();
        await _foreground.close();
        await _opened.close();
        await _tokenRefresh.close();
        return RepositoryResult.success(data: true);
      });
}
```

> **`register`/`unregister` возвращают `bool`, а ошибки ловит `execute`.** Типизированного `ApiException` нет ([04-data-layer.md](04-data-layer.md) §5); у `execute` **три** catch-ветки: `on BaseRepositoryException` — уже смапленный доменный сбой проходит насквозь, `on DioException` — маппинг по типу/статусу (таймауты и `connectionError` → `connection`; `401` → `unauthenticated`; `403` → `authentication`; `404` → `notFound`; остальное → `internal`), catch-all → `unknown`. Конкретный код ошибки приходит **не** из ручной проверки `response.statusCode`, а из `BaseRepositoryHelper.unwrapEnvelope` → `RepositoryException.fromWireCode(error.code)` (`rate_limited` → `RepositoryException.rateLimited`, `invalid_request` → `invalidRequest`, …; неизвестный код деградирует в `internal`). Ретрай с backoff по `rateLimited` строится поверх этого значения.

### 7.3 Mapper `RemoteMessage → PushMessageModel`

`@lazySingleton`, one-way (`toEntity` → `throw UnimplementedError()`, как deep-link-маппер [13-deep-links.md](13-deep-links.md) §4.3). `RemoteMessage.data` приходит как `Map<String, dynamic>` — нормализуем в `Map<String, String>`.

`lib/data/mapper/push/push_message_mapper.dart`:

```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/mapper/base_mapper.dart';
import 'package:nox_app/domain/model/push/push_message_model.dart';

@lazySingleton
class PushMessageMapper extends BaseMapper<RemoteMessage, PushMessageModel, dynamic, dynamic> {
  @override
  PushMessageModel toModel({required RemoteMessage entity, dynamic Function(dynamic entity)? ad}) {
    return PushMessageModel(
      title: entity.notification?.title,
      body: entity.notification?.body,
      data: entity.data.map((k, v) => MapEntry(k, '$v')),
    );
  }

  @override
  RemoteMessage toEntity({required PushMessageModel model, Function(dynamic entity)? ad}) => throw UnimplementedError();
}
```

### 7.4 DI-регистрация

`@LazySingleton(as: PushTokenRepository)` на `PushTokenRepositoryImpl`; маппер и API-класс — `@lazySingleton`. Кодоген — `configureDependencies` ([02-dependency-injection.md](02-dependency-injection.md)). После добавления аннотаций — прогнать `build_runner` ([12-dev-commands.md](12-dev-commands.md)). Резолв — `getIt<PushTokenRepository>()`.

| Артефакт | Аннотация | Путь |
|---|---|---|
| `PushTokenRepositoryImpl` | `@LazySingleton(as: PushTokenRepository)` | `lib/data/repository/push/push_token_repository_impl.dart` |
| `PushMessageMapper` | `@lazySingleton` | `lib/data/mapper/push/push_message_mapper.dart` |
| `PushTokenApi` | `@lazySingleton` | `lib/data/remote/api/push/push_token_api.dart` |
| `firebaseMessagingBackgroundHandler` | — (top-level, не в DI) | `lib/data/repository/push/push_background_handler.dart` |

### 7.5 Подключение в presentation — `AppRoot` как observer

`PushTokenRepository` подключается на app-shell-уровне — `AppRoot`/`AppRootBloc` подписываются на его стримы ровно как на `DeepLinkRepository.watchDeepLink()` ([05-presentation-layer.md](05-presentation-layer.md) §6, [13-deep-links.md](13-deep-links.md)). Жизненный цикл:

- **После login** (app-state вышел из `init`, есть токен-пара) — `AppRootBloc` дёргает `initialize()` → `currentToken()` → `register(...)`, подписывается на `watchTokenRefresh()` (повторный `register`), `watchMessageOpened()` (навигация §8), `watchForegroundMessages()` (in-app-баннер).
- **На logout** — `unregister(...)` → `dispose()`.

`lib/presentation/app/app_root.dart` (фрагмент `_AppRootState`, дополняет канон [05-presentation-layer.md](05-presentation-layer.md) §6.2):

```dart
class _AppRootState extends State<AppRoot> {
  late final AppRootBloc _bloc;
  final _navigatorKey = GlobalKey<NavigatorState>();

  final _pushRepository = getIt<PushTokenRepository>();
  final _pushSubs = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    _bloc = AppRootBloc()..add(const AppRootEvent.initialize());

    // подписки на выход push-репозитория — рано, как у deep-link (13-deep-links.md)
    _pushSubs.add(_pushRepository.watchMessageOpened().listen(
          (m) => _bloc.add(AppRootEvent.onPushOpened(navigatorKey: _navigatorKey, message: m)),
        ));
    _pushSubs.add(_pushRepository.watchTokenRefresh().listen(
          (t) => _bloc.add(AppRootEvent.onPushTokenRefreshed(token: t)),
        ));
    // watchForegroundMessages() — на in-app-баннер; подключить по UX-потребности.
  }

  @override
  void dispose() {
    for (final s in _pushSubs) {
      s.cancel();
    }
    _bloc.close();
    super.dispose();
  }

  // ... build() — без изменений, см. 05-presentation-layer.md §6.2
}
```

> **`AppRootBloc` дёргает `initialize()`/`register()` после login, а не в `initState`.** Регистрация требует access-JWT (§1) — поэтому она привязана к появлению токен-пары (после login), а не к старту виджета. Конкретный триггер — событие `AppRootBloc` по выходу app-state из `init` (тот же паттерн, что `_onInitializeDeepLinks` в [13-deep-links.md](13-deep-links.md), который включается `BlocListener`'ом после ухода из init-состояния).

---

## 8. Навигация по тапу — переиспользуем маршрутизатор deep-link

Tap по уведомлению (background/terminated) — это **тот же** «пришёл внешний триггер навигации», что и deep-link. Поэтому **не** строим второй маршрутизатор: routing-поля из `message.data` мапятся на ту же dispatch-table `AppRootBloc`, что и deep-link-модели ([13-deep-links.md](13-deep-links.md) §5).

Два способа стыковки (выбрать один, рекомендован первый):

1. **Через payload-`data` → доменная навигация (рекомендуется).** Сервер кладёт в `data` push'а явные routing-поля (например `{"type": "new_message", "chat_id": "<id>"}`, §9 — имена полей пример, заменить на реальный контракт). `AppRootBloc._onPushOpened` читает `message.data['type']` и пушит нужную страницу через `navigatorKey.currentState`, переиспользуя те же навигационные ветки, что и deep-link.
2. **Через `data['deep_link']` → существующий deep-link-парсер.** Если payload несёт готовую ссылку (`{"deep_link": "https://<host>/c/<chat_id>"}`), отдать её в `DeepLinkRepository.handleLink(config: HandleLinkConfig(data: …, source: DeepLinkSource.background))` ([13-deep-links.md](13-deep-links.md) §3.3) — она пройдёт штатную цепочку `isValid → parse → mapper` и доедет до того же `_onOnDeepLink`. Удобно, когда push и внешняя ссылка ведут в одно место (например, конкретный чат).

`lib/presentation/app/bloc/app_root_bloc.dart` (фрагмент `_onPushOpened`):

```dart
FutureOr<void> _onPushOpened(OnPushOpened event, Emitter<AppRootState> emit) async {
  await executeLogic(() async {
    final data = event.message.data;
    final nav = event.navigatorKey.currentState;
    if (nav == null) return;

    // Способ 1 — доменная навигация по routing-полю payload'а (имена полей — пример, §9):
    switch (data['type']) {
      case 'new_message':
        final chatId = data['chat_id'];
        if (chatId != null) {
          nav.push(ChatDetailsPage.route(chatId: chatId)); // worked example, заменить на свою фичу
        }
        break;
      case 'chat_invite':
        // увести на экран приглашения в чат / список чатов
        break;
      default:
        // Способ 2 — если есть готовая ссылка, отдать в deep-link-парсер:
        final link = data['deep_link'];
        if (link != null) {
          await getIt<DeepLinkRepository>().handleLink(
            config: HandleLinkConfig(data: link, source: DeepLinkSource.background),
          );
        }
    }
  }, onError: (error, exception, stackTrace) {
    // лог уже сделан на уровне репозитория; здесь — без терминального Error (навигация — фон)
  });
}
```

> **`executeLogic` — позиционный первый аргумент.** Сигнатура `executeLogic(() async {...}, onError: (String? error, dynamic exception, StackTrace stackTrace){...})` ([05-presentation-layer.md](05-presentation-layer.md) §2). Для навигации `onError` можно опустить (фоновая операция) — логирование уже произошло в репозитории; но эмитить терминальный `Error` тут не нужно, поэтому `onError` оставляем пустым/no-op.

> **Worked example.** `ChatDetailsPage`/`chat_id`/`new_message` — реалистичный аналог для NOX (первая реальная поверхность — список чатов, тап ведёт в конкретный чат). Под свою фичу замените набор routing-веток; механизм (payload → dispatch-table → `navigatorKey`) — без изменений.

---

## 9. Контракт push-payload'ов — зона серверной стороны (пример — TBD)

Форма доставляемых уведомлений — серверный контракт, **не** покрываемый этим документом и **не** относящийся к стороне register/unregister. Мобильный handler читает их `data`-поля (§8), но источник правды по их форме — серверная спека, не этот документ.

Ориентировочные routing-поля, которые handler ожидает в `data` (пример — контракт v0 push-payload'ов не описывает вовсе, они появятся вместе с закрытием Q2/Q13; сверить с реальным контрактом перед реализацией навигации):

| Поле `data` | Смысл | Использование на клиенте |
|---|---|---|
| `type` | тип события (`new_message` / `chat_invite` / …) | ветка dispatch-table (§8) |
| `chat_id` | id чата | навигация на экран чата |
| `message_id` | id сообщения (опц.) | подсветка конкретного сообщения |
| `deep_link` (опц.) | готовая ссылка | передать в `DeepLinkRepository.handleLink` (§8, способ 2) |

> **TBD.** Точные имена и набор `data`-полей push-payload'а — **не финальны**: их источник правды — серверная сторона, а push-часть протокола открыта (Q2 «как реализовать push-уведомления» + Q13 «протокол client-сервер ↔ relay»; контракт v0 push-событий не содержит). Ориентир, уже зафиксированный в Q2: push **content-free** — доезжает сигнал пробуждения, а содержимое приложение забирает из своего client-сервера и рисует уведомление локально, поэтому `data` несёт ровно routing-минимум. Перед реализацией навигационных веток (§8) — сверить с реальным контрактом; в коде оставить `TODO(backend-tbd)` на маппинге payload-полей.

---

## 10. Desktop fallback — push отключён (no-op)

На **Windows / Linux** у `firebase_messaging` реализации нет вовсе (плагин покрывает iOS / Android / macOS), а на **macOS** push сознательно не берётся по решению Q2 (см. врезку ниже). Поэтому push на всех трёх desktop-платформах = **выключен (no-op)**: ни токен не запрашивается, ни сетевая register/unregister не дёргается, ни стримы сообщений не эмитят.

- **Feature-gated, mobile-only.** Сама push-фича — feature-gated; когда она включается, `firebase_*`-зависимости (`firebase_core`, `firebase_messaging`) добавляются как **platform-conditional (mobile-only)** deps, и в **том же** change-set'е desktop-env регистрирует **no-op `PushTokenRepository`** (все методы возвращают `RepositoryResult.success(data: false)` / пустые стримы, `currentToken()` → `null`). Так `getIt<PushTokenRepository>()` резолвится на всех 5 платформах, но на desktop ничего не делает.
- **Сегодня push не поднят нигде.** В `lib/` нет ни одного `firebase_*`-импорта и нет `PushTokenRepository`, а сами зависимости в `pubspec.yaml` лежат закомментированными — весь этот документ описывает целевую фичу, а не существующий код. Во frozen-слайсе верификации Feature-001 (`AppShell`/`ItemListPage`, продуктовым флоу не смонтирован) push тоже не регистрируется: `initialize()` дёргается **только после login**, которого в этом слайсе нет.

> **На десктопах push не берётся — и это решение, а не пробел.** Владелец зафиксировал (Q2, 2026-08-16): доставка на Windows/macOS/Linux идёт **резидентным процессом с постоянным сокетом** — тем самым WebSocket-соединением контракта v0 (автозапуск при входе в систему, реконнект по событию пробуждения), — а вендорский push на десктопе не используется (так же поступили все восемь разобранных десктопных клиентов). Первоначальное обоснование «на десктопах push-канала нет» **опровергнуто** (APNs на macOS и WNS raw notifications на Windows существуют); причина отказа — цена против единственного закрываемого сценария «приложение закрыто полностью». Здесь же фиксируется только клиентское следствие: mobile-фича на desktop деградирует в no-op, а не ломает сборку/запуск shell'а.

---

## 11. Чеклист

- [ ] `pubspec.yaml`: `firebase_core ^4.x` + `firebase_messaging ^16.x` (+ опц. `permission_handler ^12.x` / `flutter_local_notifications`); версии пинятся по `firebase_core` constraint ([01-stack-and-tooling.md](01-stack-and-tooling.md)).
- [ ] Нативка: Android `google-services.json` + плагин `google-services` + `meta-data` канала; iOS `GoogleService-Info.plist` + APNs-ключ в Firebase + capabilities Push Notifications / Background Remote notifications (per флейвор, [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md)).
- [ ] `main.dart`: **явный** `Firebase.initializeApp()` (правило блюпринта) + `FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler)` — до `runApp`, рядом с `configureDependencies` ([05-presentation-layer.md](05-presentation-layer.md) §6.3).
- [ ] `firebaseMessagingBackgroundHandler` — top-level `@pragma('vm:entry-point')`, DI недоступен, только лёгкая работа (§5).
- [ ] Разрешение: `requestPermission(...)` **первым** в `initialize()`, до `getToken()`; iOS обязателен для выдачи токена; Android 13+ → `POST_NOTIFICATIONS`; `denied` → `success(data: false)`, не падать (§3).
- [ ] Доменка: `PushTokenModel` (enum `PushProvider`, на мобиле всегда `firebase`), `PushMessageModel` (`title`/`body`/`data`), `PushTokenRepository` (`initialize`/`register`/`unregister`/`currentToken`/`watchForegroundMessages`/`watchMessageOpened`/`watchTokenRefresh`/`dispose`) — все мутации `RepositoryResult<T>` (§4).
- [ ] Data: `PushTokenRepositoryImpl with BaseRepositoryHelper` `@LazySingleton(as: PushTokenRepository)` — три `PublishSubject`, подписки на `onMessage`/`onMessageOpenedApp`/`onTokenRefresh` + `getInitialMessage()`; `register`/`unregister` через `_pushTokenApi`, обёрнуты в `execute<bool>` (§7.2).
- [ ] Mapper `RemoteMessage → PushMessageModel` `@lazySingleton`, one-way (`toEntity → UnimplementedError`); `data` нормализуется в `Map<String, String>` (§7.3).
- [ ] Бэкенд-контракт (§6 — импортированный REST-пример; реальная команда контракта v0 `push.register` (§8.2) открыта по Q2/Q13): тело **ровно 2 ключа** (`push_notification_provider`/`push_notification_token`); `register` после login + на каждый `onTokenRefresh`; `unregister` на logout **до** очистки токен-пары; идемпотентность DELETE; rate-limit `pushTokenWrite` 20/60s (общий bucket). Сетевой вызов — через подписанный слой [14-networking-and-auth.md](14-networking-and-auth.md) §4 (HMAC/Bearer ставит interceptor, не репозиторий).
- [ ] Load-bearing (§6.4): `x-device-id` (из security-interceptor) — **единственная** клиентская ручка различения устройств (composite-UNIQUE `(user, device_id)` — пример, ключ финализируется вместе с `push.register` / Q2); `platform`/`app_version`/… сервер не берёт из body — не слать.
- [ ] Presentation (§7.5): `AppRoot` подписан на `watchMessageOpened()`/`watchTokenRefresh()` рано (в `initState`); `AppRootBloc` дёргает `initialize()`/`register()` **после login** (сессия аутентифицирована; access-JWT — деталь примера §6, в контракте v0 аутентификация одноразовая при установлении соединения), `unregister()`/`dispose()` на logout.
- [ ] Навигация по тапу (§8): **переиспользовать** маршрутизатор deep-link ([13-deep-links.md](13-deep-links.md)) — `AppRootBloc._onPushOpened` по `message.data['type']` (или `data['deep_link']` → `DeepLinkRepository.handleLink`); `executeLogic` с **позиционным** первым аргументом, `onError` опционален для фоновой навигации.
- [ ] **TBD (§9):** набор `data`-полей push-payload'а — источник правды серверная сторона; push-часть протокола открыта (Q2/Q13, контракт v0 её не содержит) — сверить с реальным контрактом перед реализацией навигационных веток, в коде — `TODO(backend-tbd)`.
- [ ] Desktop (§10): на Windows/Linux/macOS push = no-op (на Windows/Linux реализации плагина нет, на macOS — решение Q2: доставка резидентным сокетом) — `firebase_*` как platform-conditional (mobile-only) deps; desktop-env регистрирует no-op `PushTokenRepository` в том же change-set'е, чтобы `getIt<PushTokenRepository>()` резолвился на всех 5 платформах; сегодня в `lib/` push не поднят вообще.

---

## Связанные документы

- [13-deep-links.md](13-deep-links.md) — навигация по тапу переиспользует общий маршрутизатор входящих ссылок (`AppRootBloc._onOnDeepLink`, `GlobalKey<NavigatorState>`, dispatch-table, `DeepLinkRepository.handleLink`); push-tap — ещё один источник того же навигационного триггера.
- [14-networking-and-auth.md](14-networking-and-auth.md) — сетевой вызов register/unregister идёт через подписанный слой (HMAC-SHA256 + security-заголовки + access/refresh JWT + `x-device-id` — конкретная модель подписи/токенов пример: этап 1 контракта v0 идёт без авторизации, модель этапа 2 ещё не финализирована); push-репозиторий передаёт только тело, заголовки/подпись ставит security-interceptor — **не переизобретать**.
- [04-data-layer.md](04-data-layer.md) — `BaseRepositoryHelper.execute`, `BaseMapper`, REST-слой (`RequestBuilder`/`ResponseEntity<T>`/`EntityConverter`), отсутствие `ApiException`/`DaoException` (три catch-ветки `execute`: `BaseRepositoryException` насквозь → маппинг `DioException` по типу/статусу → catch-all `unknown`; коды ошибок конверта — через `unwrapEnvelope` → `RepositoryException.fromWireCode`).
- [05-presentation-layer.md](05-presentation-layer.md) — `AppRoot`/`AppRootBloc` (app-shell, observer, `GlobalKey<NavigatorState>`), `BaseBloc.executeLogic` (позиционный первый аргумент), потребление `RepositoryResult<T>` через `match`/`hasData`, bootstrap `main.dart`.
- [03-domain-layer.md](03-domain-layer.md) — `RepositoryResult<T>` (data-XOR-exception + `match`), `RepositoryException` (`internal`/`unknown`/`notFound`/`connection`/`unauthenticated`/`authentication` + проводные коды контракта v0 `invalidRequest`/`nameTaken`/`payloadTooLarge`/`attachmentGone`/`rateLimited`/`unsupportedSchema` и `RepositoryException.fromWireCode`), контракт репозитория.
- [02-dependency-injection.md](02-dependency-injection.md) — `configureDependencies(env)`, регистрация `@LazySingleton(as: PushTokenRepository)` / `@lazySingleton`-мапперов, последовательность bootstrap `main.dart`.
- [01-stack-and-tooling.md](01-stack-and-tooling.md) — версии пакетов (`firebase_core`, `firebase_messaging`, `permission_handler`).
