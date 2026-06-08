# 13 — Обработка ссылок (deep links / universal links)

> **Назначение:** зафиксировать единый, **обобщённый** механизм обработки **любой** входящей ссылки в приложении Speech AI Mobile — не только «классических» deep links, но и universal/app links и любых внешних URL, которые должны открыть/направить приложение. Пайплайн: ОС отдаёт ссылку → `app_links` → `DeepLinkRepository` парсит сырой URI в **типизированную** доменную модель → app-root маршрутизирует по типу. Перенесён из существующего проекта владельца и адаптирован под конвенции блюпринта (single-package, `@freezed`-модели, Freezed-BLoC).
> **Когда читать:** перед реализацией любого сценария «пользователь пришёл по ссылке» (верификация email, сброс пароля, открытие расшаренной записи, OAuth-callback и т.п.), а также при добавлении нового типа линка.
> **Связанные документы:** [03-domain-layer.md](03-domain-layer.md) (`RepositoryResult`, `RepositoryConfig`, `BaseMapper`-контракт), [04-data-layer.md](04-data-layer.md) (`BaseMapper`, `BaseRepositoryHelper`, DI-репозиториев), [05-presentation-layer.md](05-presentation-layer.md) (`AppRoot` + `AppRootBloc`, страницы, Freezed-BLoC), [02-dependency-injection.md](02-dependency-injection.md) (регистрация репозитория), [01-stack-and-tooling.md](01-stack-and-tooling.md) (`app_links`), [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md) (флейворы host/URL), [14-networking-and-auth.md](14-networking-and-auth.md) (verify-email/reset-password дёргают auth-endpoint'ы; web-deep-link endpoint'ы не подписываются HMAC).

---

## 0. Идея: «обработать любой входящий линк», а не только deep link

Это **общий** механизм. Единица работы — **сырая строка-ссылка + контекст её прихода** (`DeepLinkSource`), а не что-то жёстко завязанное на конкретный тип. Доменный контракт (`String data` + `DeepLinkSource source`) link-агностичен; конкретные поддерживаемые типы — это просто набор `@freezed`-моделей, реализующих общий интерфейс, и расширяется добавлением ещё одной модели + одной ветки парсинга + одной ветки маршрутизации.

Пакет: **`app_links: ^7.1.1`** (см. [01-stack-and-tooling.md](01-stack-and-tooling.md)). Он отдаёт и **cold-start** ссылку (приложение запущено по ссылке из убитого состояния), и **warm** поток (ссылка пришла, когда приложение уже работает).

**Четыре стадии пайплайна:**

```
1. ОС/браузер открывает https://<host>/<path>?<query>
        │  (по нативным intent-filter / associated-domains — §2)
        ▼
2. app_links доставляет сырую строку:
        getInitialLinkString()  → cold start (DeepLinkSource.background)
        stringLinkStream        → warm   (DeepLinkSource.foreground)
        │
        ▼
3. DeepLinkRepositoryImpl._internalParseLink (§4):
        (опц.) раскрыть tracking-редирект (SendGrid-стиль)
        → цепочка XxxEntity.isValid(link) → XxxEntity.parse(link) → mapper.toModel(ad: source)
        → BaseDeepLinkModel (типизированная модель) на BehaviorSubject<BaseDeepLinkModel?>
        │
        ▼
4. AppRoot (widget) подписан на watchDeepLink() → диспатчит OnDeepLink(navigator, deepLink)
        → AppRootBloc._onOnDeepLink: dispatch-table `is`-проверок → push нужной страницы
        → token-линки валидируются на ValidateDeepLinkPage и затем pop (§5)
```

---

## 1. Контракт и инварианты

- **Сырой URI парсится в data-слое, не в presentation.** Presentation никогда не трогает `Uri` — он получает уже **типизированную** `BaseDeepLinkModel` и переключается по её конкретному подтипу.
- **Полиморфизм — интерфейсный, а не Freezed-union.** `BaseDeepLinkModel` — рукописный `abstract`-интерфейс (`data`, `source`-геттеры); каждый тип линка — отдельный `@freezed`-класс, **реализующий** этот интерфейс. Никакого `.when`/`.map` — потребитель различает типы через `is`-проверки.
- **Один маршрутизатор.** Решение «какой тип линка → какой экран» живёт **в одном месте** — в `AppRootBloc._onOnDeepLink`. Добавление типа = одна `if (deepLink is X)`-ветка там.
- **`watchDeepLink()` отдаёт `Stream<BaseDeepLinkModel?>`** (nullable): `null` — «нет/сброшен». После обработки вызывается `cleanDeepLink()`, чтобы один и тот же линк не отработал дважды.
- **Двухфазный старт.** Виджет подписывается на **выход** (`watchDeepLink`) рано (в `initState`); BLoC включает **вход** (нативные слушатели через `initialize()`) тогда, когда приложение готово (после DI/после ухода из init-состояния, если есть auth-флоу). Репозиторий буферизует cold-start-ссылку (`BehaviorSubject`), пока потребитель не готов.
- **Все мутации репозитория возвращают `RepositoryResult<bool>`** (`success(data: true)`), как и весь остальной слой данных.

---

## 2. Нативная интеграция (обязательна)

Без нативной декларации `app_links` ссылки **не дойдут** до приложения. Для **HTTPS universal/app links** (рекомендуется) нужны и нативные декларации, и файлы-ассоциации на домене.

**Хост.** Берётся из deep-link-URL'ов бэкенда (`APPWRITE_VERIFY_URL` / `APPWRITE_RESET_URL` / `APPWRITE_SHARE_URL`, см. [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md)) — по флейвору: prod-хост и stage-хост. Ниже плейсхолдеры `<prod_host>` / `<stage_host>` (например `speech-ai.app` / `stage.speech-ai.app`).

### Android — `android/app/src/main/AndroidManifest.xml`

По одному `<intent-filter android:autoVerify="true">` на каждый (host, pathPrefix), внутри `<activity android:name=".MainActivity">`:

```xml
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>
    <data android:scheme="https" android:host="<prod_host>" android:pathPrefix="/verify-email"/>
</intent-filter>
<!-- ...повторить для stage-хоста и для каждого pathPrefix: /reset-password, /r (share) ... -->
```

- `autoVerify="true"` → это **Android App Links**: требуется `https://<host>/.well-known/assetlinks.json` с SHA-256 подписи приложения (иначе ссылки откроются в браузере, а не в приложении).
- Если у вас есть **tracking-редирект-хост** (письма часто оборачивают ссылку в click-tracking, как SendGrid `url8991...`) — его хост тоже нужно заклеймить отдельным intent-filter, иначе обёрнутая ссылка откроется в браузере (раскрытие редиректа — §4).

### iOS — `ios/Runner/Runner.entitlements`

```xml
<key>com.apple.developer.associated-domains</key>
<array>
    <string>applinks:<prod_host></string>
    <string>applinks:*.<prod_host></string>
    <string>applinks:<stage_host></string>
</array>
```

- Требуется `https://<host>/.well-known/apple-app-site-association` (AASA, JSON, без расширения) с App ID и path-паттернами.
- Кастомные схемы (`myapp://`) — только как fallback (`Info.plist` → `CFBundleURLTypes`); основной канал — HTTPS app links.

> **Где живёт нативка в монорепо.** `sources/mobile_app/android/...` и `sources/mobile_app/ios/...`. Файлы-ассоциации (`assetlinks.json`, `apple-app-site-association`) публикуются на домене — это инфра бэкенда/хостинга, отдельная задача (см. `09-build-and-secrets-infra.md`).

---

## 3. Доменный слой

### 3.1 Базовый интерфейс + источник

`lib/domain/model/deep_link/base_deep_link_model.dart` — **рукописный** `abstract`-интерфейс (НЕ `@freezed`: это общий супертип, а не union):

```dart
abstract class BaseDeepLinkModel {
  String get data;          // исходная сырая ссылка
  DeepLinkSource get source;
}

/// Контекст прихода ссылки.
/// background — приложение запущено/возобновлено ссылкой (cold-start / initial link).
/// foreground — ссылка пришла, пока приложение уже работало (live-событие).
enum DeepLinkSource { background, foreground }
```

### 3.2 Типизированная модель на тип линка (`@freezed implements BaseDeepLinkModel`)

Каждый тип линка — **отдельный** `@freezed`-класс, реализующий интерфейс. Несёт (а) семантически распарсенные поля и (б) два passthrough-поля `dataValue` / `sourceValue`, переэкспонируемые через геттеры интерфейса. Приватный конструктор `._()` обязателен — без него к `@freezed`-классу нельзя добавить `@override`-геттеры.

```dart
// lib/domain/model/deep_link/verify_email_deep_link_model.dart
@freezed
abstract class VerifyEmailDeepLinkModel with _$VerifyEmailDeepLinkModel implements BaseDeepLinkModel {
  const factory VerifyEmailDeepLinkModel({
    required String userId,
    required String secret,
    required String dataValue,          // passthrough: сырая ссылка
    required DeepLinkSource sourceValue, // passthrough: источник
  }) = _VerifyEmailDeepLinkModel;
  const VerifyEmailDeepLinkModel._();

  @override
  String get data => dataValue;
  @override
  DeepLinkSource get source => sourceValue;
}
```

> **Почему `dataValue`/`sourceValue`, а не `data`/`source` в фабрике.** Freezed не может одновременно сгенерировать required-поле фабрики И удовлетворить геттер интерфейса с тем же именем — поэтому поля называются `dataValue`/`sourceValue`, а геттеры интерфейса (`data`/`source`) делаются вручную в `._()`-классе. Повторяйте этот сплит для каждого нового типа.

### 3.3 Контракт репозитория

`lib/domain/repository/deep_link/deep_link_repository.dart`:

```dart
abstract class DeepLinkRepository {
  Future<RepositoryResult<bool>> initialize();   // включить нативные слушатели + забрать initial link
  Future<RepositoryResult<bool>> dispose();      // снять подписки, закрыть стрим
  Stream<BaseDeepLinkModel?> watchDeepLink();     // центральный observable: типизированная модель | null
  Future<RepositoryResult<bool>> handleLink({required HandleLinkConfig config}); // ручной ввод сырой ссылки
  void cleanDeepLink();                           // сбросить текущее значение в null (ack)
}
```

`lib/domain/repository/deep_link/handle_link_config.dart` — единственный аргумент `handleLink` (`@freezed implements RepositoryConfig`, см. принцип «один конфиг на вызов», [03-domain-layer.md](03-domain-layer.md)):

```dart
@freezed
abstract class HandleLinkConfig with _$HandleLinkConfig implements RepositoryConfig {
  const factory HandleLinkConfig({required String data, required DeepLinkSource source}) = _HandleLinkConfig;
}
```

---

## 4. Слой данных

### 4.1 Link-парсящие entity (статические `isValid` / `parse`)

В отличие от обычных `@freezed + json_serializable` entity, link-entity — это **тонкие парсеры**: статический `isValid(String)` (матч хоста/пути) + `parse(String)` (извлечение полей). Одна на тип линка.

```dart
// lib/data/entity/deep_link/verify_email_deep_link_entity.dart
class VerifyEmailDeepLinkEntity {
  VerifyEmailDeepLinkEntity._({required this.data, required this.userId, required this.secret});

  final String data;
  final String userId;
  final String secret;

  // Базовый URL = APPWRITE_VERIFY_URL бэкенда (по флейвору). СВЕРИТЬ формат с client_backend.
  static const _verifyStage = 'https://<stage_host>/verify-email';
  static const _verifyProd = 'https://<prod_host>/verify-email';

  static bool isValid(String data) {
    if (!data.startsWith(_verifyStage) && !data.startsWith(_verifyProd)) return false;
    final q = Uri.parse(data).queryParameters;
    return q['userId'] != null && q['secret'] != null;
  }

  static Future<VerifyEmailDeepLinkEntity> parse(String data) async {
    final q = Uri.parse(data).queryParameters;
    return VerifyEmailDeepLinkEntity._(data: data, userId: q['userId'] ?? '', secret: q['secret'] ?? '');
  }
}
```

> Поля в path (а не query) извлекаются срезом после префикса: `token = data.substring(_prefix.length)` (например `https://<host>/r/<record_id>` для share).

### 4.2 (Опционально) Раскрытие tracking-редиректа

Письма часто оборачивают реальную ссылку в click-tracking-редирект (SendGrid и т.п.). Перед основной цепочкой парсинга такой URL **раскрывается** — ручным проходом по HTTP-редиректам (до N хопов), чтобы получить реальную ссылку. Нужно **только** если используется почтовый провайдер с tracking-обёрткой; иначе стадию опускаем.

```dart
// lib/data/entity/deep_link/redirect_unwrap_entity.dart (по образцу SendGrid)
static bool isValid(String data) => data.contains(_trackingHost);

static Future<String> parse(String data) async {
  final client = HttpClient();
  var current = Uri.parse(data);
  for (var i = 0; i < _maxHops; i++) {
    final req = (await client.getUrl(current))..followRedirects = false;
    final res = await req.close();
    final loc = res.headers.value(HttpHeaders.locationHeader);
    if (loc == null || !res.isRedirect) return current.toString();
    current = Uri.parse(loc);
  }
  return current.toString();
}
```

### 4.3 Mapper (entity → model, one-way)

`BaseMapper<Entity, Model, DeepLinkSource, dynamic>` — `AdResult = DeepLinkSource` прокидывает источник в модель; `toEntity` не нужен (`throw UnimplementedError()`).

```dart
@lazySingleton
class VerifyEmailDeepLinkMapper extends BaseMapper<VerifyEmailDeepLinkEntity, VerifyEmailDeepLinkModel, DeepLinkSource, dynamic> {
  @override
  VerifyEmailDeepLinkModel toModel({required VerifyEmailDeepLinkEntity entity, DeepLinkSource Function(dynamic entity)? ad}) {
    final sourceValue = ad?.call(null) ?? DeepLinkSource.background;
    return VerifyEmailDeepLinkModel(userId: entity.userId, secret: entity.secret, dataValue: entity.data, sourceValue: sourceValue);
  }

  @override
  VerifyEmailDeepLinkEntity toEntity({required VerifyEmailDeepLinkModel model, Function(dynamic entity)? ad}) => throw UnimplementedError();
}
```

### 4.4 Реализация репозитория — ядро парсинга/диспатча

`lib/data/repository/deep_link_repository_impl.dart`. `app_links` + `BehaviorSubject` + цепочка `isValid → parse → mapper`.

```dart
@LazySingleton(as: DeepLinkRepository, env: [Environment.dev, Environment.prod, Environment.test])
class DeepLinkRepositoryImpl with BaseRepositoryHelper implements DeepLinkRepository {
  final _appLinks = AppLinks();
  final _deepLinksStreamController = BehaviorSubject<BaseDeepLinkModel?>();
  StreamSubscription<String>? _appLinksSubscription;

  @override
  Future<RepositoryResult<bool>> initialize() => execute<bool>(() async {
        await _initializeAppLinks();
        return RepositoryResult.success(data: true);
      });

  @override
  Future<RepositoryResult<bool>> dispose() => execute<bool>(() async {
        await _appLinksSubscription?.cancel();
        await _deepLinksStreamController.close();
        return RepositoryResult.success(data: true);
      });

  @override
  Future<RepositoryResult<bool>> handleLink({required HandleLinkConfig config}) =>
      execute<bool>(() async => RepositoryResult.success(data: await _processAppLinkData(config)));

  @override
  Stream<BaseDeepLinkModel?> watchDeepLink() => _deepLinksStreamController.stream;

  @override
  void cleanDeepLink() => _deepLinksStreamController.add(null);

  Future<void> _initializeAppLinks() async {
    // cold start: приложение запущено по ссылке
    final initial = await _appLinks.getInitialLinkString();
    if (initial != null) {
      await _processAppLinkData(HandleLinkConfig(data: initial, source: DeepLinkSource.background));
    }
    // warm: ссылка пришла во время работы
    _appLinksSubscription = _appLinks.stringLinkStream.listen((link) async {
      if (link != initial) {
        await _processAppLinkData(HandleLinkConfig(data: link, source: DeepLinkSource.foreground));
      }
    });
  }

  Future<bool> _processAppLinkData(HandleLinkConfig config) async {
    final result = await _internalParseLink(config: config);
    if (result.hasData) {
      _deepLinksStreamController.add(result.data!);
      return true;
    }
    return false;
  }

  Future<RepositoryResult<BaseDeepLinkModel>> _internalParseLink({required HandleLinkConfig config}) =>
      execute<BaseDeepLinkModel>(() async {
        String link = config.data;

        // (опц.) раскрыть tracking-редирект до реальной ссылки
        // if (RedirectUnwrapEntity.isValid(link)) link = await RedirectUnwrapEntity.parse(link);

        if (VerifyEmailDeepLinkEntity.isValid(link)) {
          final e = await VerifyEmailDeepLinkEntity.parse(link);
          return RepositoryResult.success(data: verifyEmailDeepLinkMapper.toModel(entity: e, ad: (_) => config.source));
        }
        if (ResetPasswordDeepLinkEntity.isValid(link)) {
          final e = await ResetPasswordDeepLinkEntity.parse(link);
          return RepositoryResult.success(data: resetPasswordDeepLinkMapper.toModel(entity: e, ad: (_) => config.source));
        }
        if (ShareRecordDeepLinkEntity.isValid(link)) {
          final e = await ShareRecordDeepLinkEntity.parse(link);
          return RepositoryResult.success(data: shareRecordDeepLinkMapper.toModel(entity: e, ad: (_) => config.source));
        }
        return RepositoryResult.error(exception: RepositoryException.unknown);
      });
}
```

> Мапперы резолвятся через `global_aliases.dart`-геттеры (`verifyEmailDeepLinkMapper` и т.п.) или `getIt<T>()` (см. [02-dependency-injection.md](02-dependency-injection.md)). `BaseRepositoryHelper.execute<T>()` логирует через обязательный `LogRepository` (см. [04-data-layer.md](04-data-layer.md)) — это касается и нераспознанной ссылки (`RepositoryException.unknown`).

---

## 5. Слой представления

### 5.1 Подписка в `AppRoot` (widget)

`AppRoot` держит `StreamSubscription` и `GlobalKey<NavigatorState>` (он же `MaterialApp.navigatorKey`) — чтобы BLoC мог навигировать **без** `BuildContext`. Подписка открывается в `initState`, диспатчит `OnDeepLink`, отменяется в `dispose`.

```dart
final _deepLinkRepository = getIt<DeepLinkRepository>();
StreamSubscription<BaseDeepLinkModel?>? _deepLinkSub;
NavigatorState get _navigator => _navigatorKey.currentState!;
final _navigatorKey = GlobalKey<NavigatorState>();

@override
void initState() {
  super.initState();
  _bloc = AppRootBloc()..add(const AppRootEvent.initialize());
  _deepLinkSub = _deepLinkRepository.watchDeepLink().listen((deepLink) {
    if (deepLink != null) _bloc.add(AppRootEvent.onDeepLink(navigator: _navigator, deepLink: deepLink));
  });
}

@override
void dispose() {
  _deepLinkSub?.cancel();
  _bloc.close();
  super.dispose();
}
```

### 5.2 Маршрутизатор в `AppRootBloc` (Freezed-BLoC)

В блюпринте `AppRootBloc` — Freezed-BLoC (см. [05-presentation-layer.md](05-presentation-layer.md) §6.1). Расширяем его Event-union двумя кейсами и добавляем dispatch-table.

```dart
@freezed
sealed class AppRootEvent with _$AppRootEvent {
  const factory AppRootEvent.initialize() = Initialize;
  const factory AppRootEvent.setTheme({required ThemeMode themeMode}) = SetTheme;
  const factory AppRootEvent.initializeDeepLinks() = InitializeDeepLinks;
  const factory AppRootEvent.onDeepLink({required NavigatorState navigator, required BaseDeepLinkModel deepLink}) = OnDeepLink;
}
```

```dart
final _deepLinkRepository = getIt<DeepLinkRepository>();

// Включаем ВХОД пайплайна, когда приложение готово (после DI; если есть auth/splash-флоу —
// после ухода из init-состояния). До этого репозиторий буферизует cold-start-ссылку.
FutureOr<void> _onInitializeDeepLinks(InitializeDeepLinks event, Emitter<AppRootState> emit) async {
  await _deepLinkRepository.initialize();
}

FutureOr<void> _onOnDeepLink(OnDeepLink event, Emitter<AppRootState> emit) async {
  final deepLink = event.deepLink;
  _deepLinkRepository.cleanDeepLink(); // ack ПЕРВЫМ делом — чтобы линк не отработал дважды

  if (deepLink is VerifyEmailDeepLinkModel) {
    unawaited(event.navigator.push(ValidateDeepLinkPage.route(deepLink: deepLink)));   // token → серверная валидация
  } else if (deepLink is ResetPasswordDeepLinkModel) {
    unawaited(event.navigator.push(SetNewPasswordPage.route(deepLink: deepLink)));     // напрямую на смену пароля
  } else if (deepLink is ShareRecordDeepLinkModel) {
    unawaited(event.navigator.push(RecordDetailsPage.route(recordId: deepLink.recordId)));
  }
  // неизвестный подтип — молча игнорируется (нет default-ветки): dispatch-table курируется вручную
}
```

- Диспатч — **плоская последовательность `is`-проверок** по конкретному подтипу (не `switch` по `DeepLinkSource`, не exhaustive). Нераспознанный тип игнорируется.
- `cleanDeepLink()` — **первым** действием, до навигации.
- Навигация — через `NavigatorState` из события (не `BuildContext`-в-bloc).
- `InitializeDeepLinks` диспатчится из `AppRoot` после готовности (например, в `_onInitialize` → `add(const AppRootEvent.initializeDeepLinks())`, либо по сигналу app-state, если позже появится auth/splash-флоу — см. [05-presentation-layer.md](05-presentation-layer.md) §6.1 «Опциональный auth/splash-флоу»).

### 5.3 `ValidateDeepLinkPage` — серверная валидация token-линков

Token-несущие линки (verify-email и т.п.) ведут на отдельную страницу, которая валидирует токен через репозиторий (например `AuthRepository`), показывает прогресс, и на успехе **закрывается** (pop) — пост-экран выбирает общий флоу приложения; на ошибке показывает error-виджет.

Страница — по конвенции page-folder ([00-architecture-overview.md](00-architecture-overview.md) §6): `lib/presentation/pages/validate_deep_link_page/` + `bloc/` + `widgets/`. BLoC — Freezed (две подсостояния `Initializing` / `Error`, без явного success — успех выражается `pop`):

```dart
// validate_deep_link_state.dart
@freezed
sealed class ValidateDeepLinkState with _$ValidateDeepLinkState {
  const factory ValidateDeepLinkState.initializing({required BaseDeepLinkModel deepLink, @Default(false) bool loading}) = Initializing;
  const factory ValidateDeepLinkState.error({required BaseDeepLinkModel deepLink, BaseRepositoryException? exception}) = Error;
}

// validate_deep_link_event.dart
@freezed
sealed class ValidateDeepLinkEvent with _$ValidateDeepLinkEvent {
  const factory ValidateDeepLinkEvent.initialize({required BuildContext context}) = Initialize;
}
```

```dart
// validate_deep_link_bloc.dart (фрагмент handler'а)
FutureOr<void> _onInitialize(Initialize event, Emitter<ValidateDeepLinkState> emit) async {
  final state = this.state;
  if (state is! Initializing || state.loading) return;
  emit(state.copyWith(loading: true));

  RepositoryResult<bool>? result;
  final link = state.deepLink;
  if (link is VerifyEmailDeepLinkModel) {
    // verify_email — web-deep-link endpoint: без HMAC/security-заголовков (см. 14-networking-and-auth.md §4.2).
    result = await _authRepository.verifyEmail(config: VerifyEmailConfig(userId: link.userId, secret: link.secret));
  }
  // ...другие token-типы...

  if (result != null && result.hasData && result.data == true) {
    if (event.context.mounted) Navigator.of(event.context).pop();   // успех → закрываемся
  } else {
    emit(ValidateDeepLinkState.error(deepLink: link, exception: result?.exception));
  }
}
```

Тело страницы рендерится через `state.when(initializing: ..., error: ...)`: прогресс-плейсхолдер на `Initializing` и `ValidateDeepLinkErrorWidget` на `Error`. Валидация стартует сразу в `initState` (`..add(ValidateDeepLinkEvent.initialize(context: context))`).

> **Не каждый тип проходит через ValidateDeepLinkPage.** `ResetPassword` (несёт `userId`/`secret` — Appwrite-recovery, без firebase-style `oobCode`) уходит **сразу** на экран смены пароля, который сам дёргает API при отправке формы (`verify_reset_password`). Серверную валидацию `ValidateDeepLinkPage` проходят только линки, которые надо подтвердить до показа экрана (verify-email и т.п.).

---

## 6. Типы линков SpeechAI (под бэкенд)

Конкретный набор — под deep-link-URL'ы `client_backend`. **URL/имена query-параметров сверить с бэкендом перед реализацией** (`APPWRITE_VERIFY_URL` / `APPWRITE_RESET_URL` / `APPWRITE_SHARE_URL`; Appwrite-формат верификации/восстановления обычно несёт `userId` + `secret`).

| Модель | URL-паттерн (host по флейвору) | Поля | Назначение |
|---|---|---|---|
| `VerifyEmailDeepLinkModel` | `https://<host>/verify-email?userId=…&secret=…` | `userId`, `secret` | подтверждение email → `ValidateDeepLinkPage` → endpoint `verify_email` |
| `ResetPasswordDeepLinkModel` | `https://<host>/reset-password?userId=…&secret=…` | `userId`, `secret` | напрямую на экран смены пароля → `verify_reset_password` |
| `ShareRecordDeepLinkModel` | `https://<host>/r/<record_id>` | `recordId` | открыть расшаренную запись (`APPWRITE_SHARE_URL`) |

> Это **cross-project контракт** (mobile ↔ client_backend ↔ Appwrite). Точный формат URL и параметров фиксируется совместно с владельцем бэкенда (см. также `docs/spec/` бэкенда); таблица выше — стартовая, не финальная. Эндпоинты `verify_email` / `verify_reset_password` — web-deep-link (`requiresWebDeepLink = true`): **не** подписываются HMAC и не несут security-заголовков (см. [14-networking-and-auth.md](14-networking-and-auth.md) §4.2) — запрос от `ValidateDeepLinkPage` / экрана смены пароля идёт без security-interceptor'а.

> **⚠ Перед боевым деплоем (native association — иначе ссылки молча уходят в браузер).** §2 даёт каркас intent-filter / Associated Domains, но для прода обязательно добить (пометить в `docs/predeploy/`): (1) **Android `https://<host>/.well-known/assetlinks.json`** с `delegate_permission/common.handle_all_urls`, `package_name` и SHA-256-fingerprint'ами **upload-key И Play App Signing key** (Google пере-подписывает APK — без его fingerprint App Links не верифицируются в проде; самый частый провал); (2) **iOS AASA `apple-app-site-association`** в новом формате `applinks.details[].appIDs` (`<TeamID>.<BundleID>`) + `components`, отдаётся как `application/json` без редиректа и без `.json`-расширения + capability **Associated Domains** в Xcode-таргете; (3) **реальные хосты SpeechAI**: deep-link host (`APPWRITE_VERIFY_URL`/`RESET_URL`/`SHARE_URL`) — это **web-хост писем/шары** (`speech-ai.app` / `stage.speech-ai.app`), а **не** API-хост (`api-*.speech-ai.app`) — сверить с владельцем, где публикуются ссылки и `.well-known/*`; (4) опц. **custom-scheme fallback** (`CFBundleURLTypes` / Android scheme intent-filter) для приёма до подтверждения App Links; (5) **тест-план верификации** (Android `adb shell am start -W -a android.intent.action.VIEW -d "https://<host>/verify-email?..." <app_id>` + `pm verify-app-links`; iOS — AASA через `app-site-association.cdn-apple.com/a/v1/<host>` + тап из Notes); (6) гейтинг **share-record при неавторизованном пользователе** (redirect на login → возврат к отложенному deep-link).

---

## 7. Добавление нового типа линка (чеклист)

1. **Domain-модель** — `lib/domain/model/deep_link/<x>_deep_link_model.dart`: `@freezed ... implements BaseDeepLinkModel` с типизированными полями + `dataValue`/`sourceValue` + `._()` + `@override`-геттеры.
2. **Entity-парсер** — `lib/data/entity/deep_link/<x>_deep_link_entity.dart`: статические `isValid(String)` + `parse(String)`.
3. **Mapper** — `lib/data/mapper/deep_link/<x>_deep_link_mapper.dart`: `@lazySingleton extends BaseMapper<Entity, Model, DeepLinkSource, dynamic>`, `toModel(ad: → source)`, `toEntity` → `UnimplementedError`.
4. **Ветка парсинга** — добавить `if (XEntity.isValid(link)) → parse → mapper.toModel` в `DeepLinkRepositoryImpl._internalParseLink`.
5. **Ветка маршрутизации** — добавить `if (deepLink is XModel)` в `AppRootBloc._onOnDeepLink` (+ страница-назначение).
6. **Нативка** — если появился новый host/pathPrefix: добавить Android intent-filter + iOS associated-domain + обновить `assetlinks.json` / AASA (§2).
7. **Кодоген + DI** — `fvm dart run build_runner build` (Freezed/DI), при необходимости `global_aliases.dart`-геттер маппера.

---

## 8. Подводные камни

- **Интерфейсный полиморфизм, не union.** `BaseDeepLinkModel` — рукописный `abstract`-интерфейс; **нет** `.when`/`.map`. Различать только через `is`-проверки. (Это исключение из общего «Freezed-BLoC/Freezed-union»: модели линков — value-объекты с общим интерфейсом, а не sealed union.)
- **`dataValue`/`sourceValue` + `._()`** обязательны в каждой модели — иначе `@override`-геттеры к `@freezed`-классу не добавить.
- **`watchDeepLink()` nullable + `cleanDeepLink()`-ack.** `null` — «сброшено». Не вызвав `cleanDeepLink()`, рискуете обработать тот же линк дважды (BehaviorSubject реплеит последнее значение на новую подписку).
- **Двухфазный старт.** Виджет подписывается рано; `initialize()` (нативные слушатели) включается, когда приложение готово. Репозиторий обязан буферизовать cold-start-ссылку (`BehaviorSubject`) до готовности потребителя.
- **`autoVerify` + файлы-ассоциации.** Без `assetlinks.json` (Android) / `apple-app-site-association` (iOS) ссылки откроются в браузере, а не в приложении. Это отдельная инфра-задача на домене.
- **Tracking-редирект-хост** (если есть) надо и **заклеймить** нативно, и **раскрыть** в `_internalParseLink` — иначе обёрнутая ссылка не дойдёт/не распарсится.
- **Не все типы валидируются на сервере.** `ValidateDeepLinkPage` — только для token-линков, требующих подтверждения до экрана; остальные роутятся напрямую.
- **Навигация без `BuildContext` в bloc** — через `NavigatorState` из события (`GlobalKey<NavigatorState>` = `MaterialApp.navigatorKey`). На странице-валидаторе, наоборот, `BuildContext` прокидывается в событие и гардится `context.mounted` перед `pop` — две разные стратегии по слоям, не путать.
- **URL-контракт — cross-project.** Host/path/query фиксируются совместно с бэкендом; не хардкодить «на глаз».

---

## Чеклист

- [ ] `app_links: ^7.1.1` в `pubspec.yaml` ([01-stack-and-tooling.md](01-stack-and-tooling.md)).
- [ ] Нативка: Android intent-filter'ы (`autoVerify`) на каждый host/pathPrefix + iOS `associated-domains`; `assetlinks.json` / AASA опубликованы на домене.
- [ ] `BaseDeepLinkModel` (рукописный `abstract` интерфейс) + `enum DeepLinkSource {background, foreground}`.
- [ ] По одному `@freezed ... implements BaseDeepLinkModel` на тип линка (с `dataValue`/`sourceValue` + `._()` + `@override`-геттеры).
- [ ] `DeepLinkRepository`-контракт (`initialize`/`dispose`/`watchDeepLink`/`handleLink`/`cleanDeepLink`) + `HandleLinkConfig` (`@freezed implements RepositoryConfig`).
- [ ] Link-entity (`isValid`/`parse`) + mapper (`BaseMapper<…, DeepLinkSource, dynamic>`, `toEntity`→`UnimplementedError`) на каждый тип.
- [ ] `DeepLinkRepositoryImpl` (`@LazySingleton(as: DeepLinkRepository, env:[dev,prod,test])`, `BaseRepositoryHelper`, `AppLinks()`, `BehaviorSubject`, цепочка `isValid→parse→mapper`).
- [ ] `AppRoot` подписан на `watchDeepLink()` → `OnDeepLink(navigator, deepLink)`; отписка в `dispose`; `InitializeDeepLinks` после готовности приложения.
- [ ] `AppRootBloc` dispatch-table (`cleanDeepLink()` первым; `is`-ветки на каждый тип → страница).
- [ ] `ValidateDeepLinkPage` (page-folder + Freezed-BLoC `Initializing`/`Error`) для token-линков; успех = `pop`, ошибка = `ValidateDeepLinkErrorWidget`.
- [ ] URL-контракт типов линков сверён с `client_backend` (`APPWRITE_VERIFY_URL`/`RESET_URL`/`SHARE_URL`).
