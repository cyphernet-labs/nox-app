# 17 — Клиентская аналитика

> **Приватность прежде всего (NOX).** Аналитика в NOX **по умолчанию ВЫКЛЮЧЕНА** — это строго opt-in: пока пользователь явно не включил её, не отправляется ни одного события. И даже при включённой аналитике слой **никогда** не передаёт PII, содержимое сообщений, идентификаторы пользователей в открытом виде или имена чатов — это прямое следствие Signal-подобной модели NOX «минимизировать метаданные» (см. §6). Конкретный analytics-провайдер для NOX не выбран; этот документ фиксирует **паттерн** слоя, а не вендора.
>
> **Назначение:** зафиксировать клиентский analytics-слой приложения NOX как сквозной (cross-cutting) сервис — интерфейс `AnalyticsRepository` в `lib/domain/repository/analytics/`, имплементацию `AnalyticsRepositoryImpl` в `lib/data/repository/analytics/`, типобезопасный таксоном событий через `@freezed`-union `AnalyticsEvent`, инициализацию SDK с project-token'ом из флейвора (`AppConfigRepository`, НЕ хардкод), super-properties как поведенческий контекст (`platform` / `app_version` / `build` / `environment`), отдельную от них идентичность (`distinct_id` через `identify()`, зеркалит opaque user id бэкенда NOX — это **не** super-property), правила приватности (opt-in по умолчанию, без PII) и точки вызова из BLoC. Слой проектируется **с нуля** — это правило блюпринта; зеркалируется лишь общая форма repository-слоя.
> **Когда читать:** перед поднятием папки `lib/{domain,data}/repository/analytics/`, перед добавлением первой точки трекинга в любой BLoC, и обязательно — при расширении таксонома событий (новое событие = новый вариант `AnalyticsEvent`, а не строковый литерал по коду).
> **Связанные документы:** [03-domain-layer.md](03-domain-layer.md) (`RepositoryResult`, `RepositoryException`, контракты репозиториев), [04-data-layer.md](04-data-layer.md) (`BaseRepositoryHelper`, `execute(...)`, форма `*_repository_impl.dart`, `LogRepository` как сквозной), [05-presentation-layer.md](05-presentation-layer.md) (Freezed-BLoC, `AppRoot` + `AppRootBloc`, где звать `trackEvent`), [02-dependency-injection.md](02-dependency-injection.md) (`configureDependencies`, `@lazySingleton(as:)`, `AppConfigRepository`, bootstrap `main.dart`), [14-networking-and-auth.md](14-networking-and-auth.md) (auth-флоу: `identify` после login / `reset` после logout — `distinct_id` = opaque user id бэкенда NOX; сетевой слой не трогаем — SDK ходит к analytics-провайдеру сам), [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md) (`analyticsProjectToken` per флейвор из зашифрованных секретов).

---

## 0. Идея: аналитика как первоклассный архитектурный компонент

Этот документ — единственный дом контракта клиентской аналитики. Он отвечает на три вопроса:

1. **Зачем клиентская аналитика отдельным слоем** — продуктовые воронки — это **поведенческие** данные, которых серверное состояние бэкенда NOX не даёт; их источник — клиентские события у analytics-провайдера. Это вытекает из Принципа I конституции NOX (приватность/E2EE — opt-in, без PII) и Принципа III (архитектурный блюпринт) — см. §1.
2. **Как устроен слой** — `AnalyticsRepository` (контракт в `lib/domain/`) + `AnalyticsRepositoryImpl` (обёртка над analytics-провайдером в `lib/data/`), типобезопасный таксоном `AnalyticsEvent`, инициализация с токеном из конфига, super-properties, приватность. §2–§6.
3. **Откуда и когда звать трекинг** — из presentation-слоя (BLoC) на ключевых переходах; `identify`/`reset` завязаны на auth-флоу; init — в bootstrap. §7.

> **Единый пакет.** Все пути — `lib/...` внутри одного пакета `nox_app` (worked example). Импорты — полные `package:nox_app/...`, относительные `../` запрещены (кроме `part`-директив).

> **Аналитика никогда не роняет UX.** Сбой SDK, отсутствие токена, нет сети — всё это поглощается молча (fail-silent через `LogRepository`-предупреждение). Ни один вызов трекинга не должен бросать исключение в UI-поток и не должен блокировать пользовательское действие.

---

## 1. Связь с Конституцией NOX (Принцип I — Приватность и E2EE)

Якорь этого слоя — **Принцип I** конституции NOX (`.specify/memory/constitution.md`, v1.3.0, семь принципов: приватность/E2EE, спецификации и дизайн-корпус — источник истины, обязательный архитектурный блюпринт, верность дизайн-системе, языковая дисциплина, паритет платформ mobile ↔ desktop, контракт провода — закон). Принцип I прямо требует: клиентская аналитика **никогда** не содержит PII, содержимого сообщений, идентификаторов пользователей или имён чатов, и она **строго opt-in (по умолчанию выключена)**. Этот документ — реализация этого требования на уровне слоя. Вторично слой опирается на **Принцип III** (обязательный архитектурный блюпринт): форма repository-слоя, `RepositoryResult`, обязательный `LogRepository`, codegen-first — едины для всех областей и применяются здесь так же.

> **Приватность — первичный гейт (NOX).** В NOX любая capture-логика подчинена Принципу I: фиксация поведенческого сигнала не оправдывает сбор PII, содержимого сообщений или метаданных, идентифицирующих переписку. Аналитика опциональна (opt-in), поведенческая и обезличенная — см. §6.

**Что из этого следует для клиента:**

- **Поведенческая аналитика — клиентская по природе.** Серверные данные бэкенда NOX фиксируют *состояние* (сущность создана, операция перешла в терминальный статус), но не *поведение* (где пользователь нажал, на каком шаге воронки отвалился). Отсюда — **зачем** клиенту нужен отдельный analytics-слой: это источник продуктовых воронок, которые из серверного состояния не восстановить.
- **Точки трекинга закладываются на этапе дизайна, а не доклеиваются потом.** Каждый значимый пользовательский шаг (экран, действие в воронке, успех/ошибка длинной операции) получает точку трекинга **на этапе дизайна экрана/BLoC**. Аналитика — первоклассный компонент, а не afterthought.
- **No speculative events.** Заводим интерфейс и стартовый таксоном (§5), но **конкретный финальный список событий — продуктовое решение** (см. §5). Не плодим события «на всякий случай».
- **Mirror-инвариант идентификатора.** Где у фичи есть и серверная запись, и клиентское событие — идентификатор пользователя должен совпадать: analytics `distinct_id` ← публичный id автора бэкенда NOX. Бэкенд выбран (Go-сервер `noxd` + контракт провода v0); открыт лишь **вид** этого публичного id — вопрос Q11 реестра `docs/client-backend/open-questions.md`. Это связывает поведенческую воронку с серверной записью при кросс-анализе. (В NOX `distinct_id` — всегда opaque-идентификатор, никогда не телефон/email/имя; см. §6.)

> **Где именно «момент первой записи» на клиенте.** Для парных длинных операций (создание сущности и т.п.) трекинг — это `_started` в начале и `_succeeded`/`_failed` в исходе (см. §5). Это даёт магнитуды/счётчики, а не один boolean: воронка `started → succeeded/failed` показывает drop-off, который «готово/нет» не покажет.

---

## 2. Раскладка и форма слоя

Готового паттерна «как трекаются события» в блюпринте нет — слой analytics проектируется с нуля. Зеркалируется лишь **общая форма** repository-слоя, единая для всех областей блюпринта:

- интерфейс — `lib/domain/repository/<area>/...`;
- имплементация — `lib/data/repository/<area>_repository_impl.dart`, `with BaseRepositoryHelper`, методы `return execute(() async { ... })`;
- DI — биндинг через get_it + injectable; `LogRepository` сквозной.

Раскладка analytics-слоя:

```
lib/
  domain/
    repository/
      analytics/
        analytics_repository.dart       # контракт
    model/
      analytics/
        analytics_event.dart            # @freezed sealed union (таксоном)
        analytics_user_properties.dart  # @freezed value-объект (профиль пользователя)
  data/
    repository/
      analytics/
        analytics_repository_impl.dart  # @LazySingleton(as: AnalyticsRepository) — обёртка над analytics-провайдером
```

> **SDK ходит к analytics-провайдеру сам.** Analytics-SDK отправляет события напрямую в свой ingest, **не** через `ApiClient`/Dio из [14-networking-and-auth.md](14-networking-and-auth.md). Сетевой слой и auth-pipeline клиента аналитика не трогает — это разные транспорты. Единственная точка пересечения с auth — `identify`/`reset` (§4, §7).

---

## 3. Доменный контракт `AnalyticsRepository`

Интерфейс минимален и не утекает деталями analytics-провайдера: presentation знает только «трекни событие», «опознай пользователя», «сбрось», «обнови свойства профиля», «выключи аналитику».

`lib/domain/repository/analytics/analytics_repository.dart`:

```dart
import 'package:nox_app/domain/model/analytics/analytics_event.dart';
import 'package:nox_app/domain/model/analytics/analytics_user_properties.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

abstract interface class AnalyticsRepository {
  /// Поднимает SDK (token из AppConfigRepository), ставит super-properties.
  /// Best-effort: пустой token (dev / opt-out) => no-op success.
  Future<RepositoryResult<bool>> initialize();

  /// Связывает события с пользователем. distinct_id == публичный id автора бэкенда NOX (его вид — открытый вопрос Q11).
  Future<RepositoryResult<bool>> identify(String userId);

  /// Обновляет свойства профиля пользователя (people-properties). Без PII.
  Future<RepositoryResult<bool>> setUserProperties(AnalyticsUserProperties properties);

  /// Один трек-вызов. Типобезопасный — без строковых литералов на стороне вызова.
  Future<RepositoryResult<bool>> trackEvent(AnalyticsEvent event);

  /// Глобальный opt-out: больше ничего не отправляется до opt-in.
  Future<RepositoryResult<bool>> setTrackingEnabled(bool enabled);

  /// Разрывает связь с distinct_id (вызывается после logout).
  Future<RepositoryResult<bool>> reset();
}
```

`RepositoryResult<bool>` / `RepositoryException` — контракт из [03-domain-layer.md](03-domain-layer.md); потребляется через `match(onData:, onError:)`, **никогда** `result.data!`. Все методы best-effort: даже на ошибке SDK возвращается `RepositoryResult` (через `execute`), а не throw.

### `AnalyticsEvent` — типобезопасный таксоном

Таксоном — `@freezed sealed`-union: каждый вариант несёт **типизированные** properties, а не `Map<String, dynamic>` по месту вызова. Это превращает «забыл/опечатался в имени события» в ошибку компиляции. Имя события и собранную `Map<String, Object?>` отдают extension-геттеры `name` / `properties` (логика на состоянии живёт в extension, как и в BLoC — см. [05-presentation-layer.md](05-presentation-layer.md)).

Ниже — worked-пример на нейтральной модели `Item` (`<Feature>`/`<Model>`-плейсхолдер блюпринта); реальные события NOX подставляются по тому же образцу.

`lib/domain/model/analytics/analytics_event.dart`:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'analytics_event.freezed.dart';

@freezed
sealed class AnalyticsEvent with _$AnalyticsEvent {
  const factory AnalyticsEvent.appOpen({required bool isFirstOpen}) = AppOpenEvent;

  const factory AnalyticsEvent.authLogin({required String method}) = AuthLoginEvent;

  const factory AnalyticsEvent.itemCreateStarted({
    required String source,
    String? variant,
  }) = ItemCreateStartedEvent;

  const factory AnalyticsEvent.itemCreateSucceeded({
    required String itemId,
    required int partsCount,
  }) = ItemCreateSucceededEvent;

  const factory AnalyticsEvent.itemCreateFailed({
    required String errorCode,
    String? reason,
  }) = ItemCreateFailedEvent;
  // … остальные варианты из §5
}

extension AnalyticsEventX on AnalyticsEvent {
  /// snake_case-имя события для analytics-SDK.
  String get name => switch (this) {
        AppOpenEvent() => 'app_open',
        AuthLoginEvent() => 'auth_login',
        ItemCreateStartedEvent() => 'item_create_started',
        ItemCreateSucceededEvent() => 'item_create_succeeded',
        ItemCreateFailedEvent() => 'item_create_failed',
      };

  /// Типизированные properties → плоская Map для SDK. БЕЗ PII.
  Map<String, Object?> get properties => switch (this) {
        AppOpenEvent(:final isFirstOpen) => {'is_first_open': isFirstOpen},
        AuthLoginEvent(:final method) => {'method': method},
        ItemCreateStartedEvent(:final source, :final variant) => {
            'source': source,
            if (variant != null) 'variant': variant,
          },
        ItemCreateSucceededEvent(:final itemId, :final partsCount) => {
            'item_id': itemId,
            'parts_count': partsCount,
          },
        ItemCreateFailedEvent(:final errorCode, :final reason) => {
            'error_code': errorCode,
            if (reason != null) 'reason': reason,
          },
      };
}
```

> **Гарантия типобезопасности.** Имена событий и ключи properties живут в одном месте (extension над union), а не разбросаны строковыми литералами по BLoC'ам. Добавление события = новый `const factory` + ветка в `name`/`properties`; компилятор заставит закрыть `switch`.

`AnalyticsUserProperties` — `@freezed` value-объект people-properties (locale, категориальные флаги и т.п. — **без PII**, см. §6); опускаю тело ради краткости, форма — обычный `@freezed`-класс с `toProviderMap()`-extension.

---

## 4. Имплементация поверх analytics-провайдера

`AnalyticsRepositoryImpl` оборачивает SDK выбранного analytics-провайдера, биндится через `@LazySingleton(as: AnalyticsRepository)`, использует `BaseRepositoryHelper.execute(...)` для единообразного guarded-логирования (см. [04-data-layer.md](04-data-layer.md)). Внутренне держит nullable handle SDK — `null` означает «не инициализирован / выключен / пустой token», и тогда каждый трек-вызов тихо no-op'ит.

> **Вендор не зафиксирован.** Конкретный analytics-провайдер для NOX не выбран. Один из возможных вариантов имплементации — Mixpanel (`mixpanel_flutter` как **опциональная** vendor-зависимость), на нём и показан worked-пример ниже; так же подставляется любой другой SDK. API провайдера (`init` / `identify` / `track` / `optInTracking`/`optOutTracking` / `reset`) — пример; реальные вызовы зависят от выбранного SDK.

`lib/data/repository/analytics/analytics_repository_impl.dart`:

```dart
import 'package:injectable/injectable.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart'; // пример vendor-SDK (опциональная зависимость)
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/domain/model/analytics/analytics_event.dart';
import 'package:nox_app/domain/model/analytics/analytics_user_properties.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/analytics/analytics_repository.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_app/domain/repository/log_repository.dart';

@LazySingleton(as: AnalyticsRepository)
class AnalyticsRepositoryImpl with BaseRepositoryHelper implements AnalyticsRepository {
  AnalyticsRepositoryImpl(this._appConfigRepository, this._logRepository);

  final AppConfigRepository _appConfigRepository;
  final LogRepository _logRepository;

  Mixpanel? _client; // handle vendor-SDK (тип зависит от провайдера)
  bool _enabled = false; // NOX: opt-in — трекинг включается только явным согласием пользователя

  @override
  Future<RepositoryResult<bool>> initialize() => execute(() async {
        final token = _appConfigRepository.config.analyticsProjectToken;
        if (token.isEmpty) {
          // dev-флейвор / пустой секрет — аналитика отключена, это НЕ ошибка.
          _logRepository.debug(target: 'AnalyticsRepositoryImpl', message: 'Analytics disabled: empty analytics token');
          return RepositoryResult.success(data: false);
        }
        final client = await Mixpanel.init(token, trackAutomaticEvents: false);

        // super-properties — поведенческий контекст, клеится ко ВСЕМ событиям автоматически.
        // НЕ содержит идентичности: distinct_id ставится отдельно через identify() (ниже).
        final cfg = _appConfigRepository.config;
        client.registerSuperProperties({
          'platform': cfg.platform, // ios | android | windows | linux | macos
          'app_version': cfg.appVersion, // CalVer YY.M.D
          'build': cfg.buildNumber, // shifted-epoch build
          'environment': cfg.environment, // stage | production
        });

        _client = client;
        await _applyOptState(); // opt-in по умолчанию выключен (§6)
        return RepositoryResult.success(data: true);
      });

  @override
  Future<RepositoryResult<bool>> identify(String userId) => execute(() async {
        // distinct_id == the public author id of the NOX backend (open: Q11).
        await _client?.identify(userId);
        return RepositoryResult.success(data: _client != null);
      });

  @override
  Future<RepositoryResult<bool>> setUserProperties(AnalyticsUserProperties properties) => execute(() async {
        final people = _client?.getPeople();
        properties.toProviderMap().forEach((k, v) => people?.set(k, v)); // people-properties, без PII
        return RepositoryResult.success(data: _client != null);
      });

  @override
  Future<RepositoryResult<bool>> trackEvent(AnalyticsEvent event) => execute(() async {
        if (!_enabled || _client == null) {
          return RepositoryResult.success(data: false); // opt-out / не инициализирован — тихий no-op
        }
        await _client!.track(event.name, properties: event.properties);
        return RepositoryResult.success(data: true);
      });

  @override
  Future<RepositoryResult<bool>> setTrackingEnabled(bool enabled) => execute(() async {
        _enabled = enabled;
        await _applyOptState();
        return RepositoryResult.success(data: true);
      });

  @override
  Future<RepositoryResult<bool>> reset() => execute(() async {
        await _client?.reset(); // разрывает связь с distinct_id (после logout)
        return RepositoryResult.success(data: _client != null);
      });

  Future<void> _applyOptState() async {
    if (_enabled) {
      await _client?.optInTracking();
    } else {
      await _client?.optOutTracking();
    }
  }
}
```

> **Token не хардкодится.** `analyticsProjectToken` приходит из `AppConfigRepository.config` per-флейвор (см. [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md)): public-token из `secrets/{stage,production}.enc.yaml::public.analytics.project_token`, прокидывается в bundle через `--dart-define`/флейвор-конфиг. **Флейворов сборки два — `stage` и `prod`** (`AppFlavorType { prod, stage }`; каждый берёт токен из своего env-секрета: `secrets/stage.enc.yaml` / `secrets/production.enc.yaml` = разные проекты у провайдера). «dev» — это **не отдельный флейвор сборки**, а просто отсутствие токена (`analyticsProjectToken=''` при локальном запуске) ⇒ `initialize()` отдаёт `success(data: false)` и события не шлются. Это разделяет stage и prod **разными токенами** (= разные проекты у провайдера), а не env-тегом.

> **Super-properties ≠ идентичность.** Super-properties — это **только поведенческий контекст**: `platform` / `app_version` / `build` / `environment` (категориальные поля, клеятся ко всем событиям). Идентификатор пользователя в их число **не входит** — идентичность задаётся отдельно через `identify(...)`, который выставляет `distinct_id`, зеркалящий opaque user id бэкенда NOX (mirror-инвариант §1). Это два разных механизма: контекст vs идентичность; не смешивать в `registerSuperProperties`.

> **Поле `platform` — пять платформ.** В NOX `cfg.platform` принимает значения `ios | android | windows | linux | macos` (web вне области): аналитика должна различать все пять целевых платформ, включая desktop (Windows/Linux/macOS — обязательны по Принципу VI конституции, v1.3.0). Значение выводится из `Platform.isIOS/isAndroid/isWindows/isMacOS/isLinux`. Не сужать таксоном `platform` до `ios|android`.

### Проекты analytics-провайдера

> *(пример — analytics-провайдер для NOX ещё не выбран; заменить на реальные проекты/идентификаторы выбранного вендора)*

| Env | Project name | Source токена |
|---|---|---|
| Stage | `NOX Stage` | `public.analytics.project_token` в `secrets/stage.enc.yaml` |
| Production | `NOX Production` | `public.analytics.project_token` в `secrets/production.enc.yaml` |
| Dev | — | пустая строка (события не шлются) |

Любой server-only `API Secret` провайдера на клиенте **не используется** — аналитика client-only, backend NOX к analytics-провайдеру напрямую не пишет. Регион данных (data-residency) выбирается под требования приватности NOX при фиксации вендора.

---

## 5. Стартовый таксоном событий — как ПАТТЕРН (не финальный контракт)

> **Финальный список событий — продуктовое решение, не инженерное.** Ниже — стартовый **паттерн** + соглашения об именовании, **а не зафиксированный контракт**. Продукт может разнести события по двум системам: одна — объём/сессии (`app_open`, `screen_view`, `user_engaged`), другая — поведенческие воронки/инсайты (`item_create_*`, `chats_list_*`). Этот документ — про поведенческую часть. С учётом приватности NOX (§6) любой такой список фильтруется: события без PII, без содержимого сообщений и без имён чатов.

**Соглашения об именовании (паттерн):**

- Имена событий — `snake_case`, форма `subject_verb` (`item_create_started`); исходы — состоянием/прошедшим временем (`_succeeded` / `_failed`).
- Парные длинные операции — `_started` → `_succeeded` / `_failed` (для воронок и drop-off): магнитуды/счётчики, а не один boolean.
- Properties — типизированные: `source` (откуда инициировано), `variant`, категориальные флаги, `duration_ms`, `error_code` для `_failed`. Только категории/магнитуды/opaque-ссылки — без PII (§6).
- `distinct_id` = opaque user id бэкенда NOX; `identify` после login, `reset` после logout (§7).

**Стартовый набор (worked-пример на нейтральной модели `Item`; первая реальная поверхность NOX — список чатов общего пространства, см. ниже):**

| Событие | Когда | Ключевые properties |
|---|---|---|
| `app_open` | холодный/тёплый старт | `is_first_open` |
| `onboarding_completed` | прошёл onboarding | `steps_seen` |
| `auth_login` | успешный логин | `method` |
| `auth_register` | успешная регистрация | `method` |
| `chats_list_viewed` | открыт список чатов (первая реальная поверхность) | `count_bucket` (диапазон, не точное число) |
| `item_create_started` | пользователь инициировал создание сущности | `source`, `variant` |
| `item_create_succeeded` | сущность создана | `item_id` (opaque), `parts_count` |
| `item_create_failed` | ошибка создания | `error_code`, `reason` |

Эти события закрывают поведенческие воронки уровня `started → succeeded/failed` и retention 30/90 дней — **без** содержимого сообщений и без имён/идентификаторов чатов (§6).

> **Первая реальная поверхность — список чатов.** Первый реальный экран NOX — список чатов общего пространства (shared-space): это server-owned пагинируемый список, который на клиенте обслуживается cache-first поверх Sembast (`ChatRepositoryImpl` + `ChatDao`). Network-only carve-out для продуктовых репозиториев отменён и остаётся только в замороженном верификационном слайсе `Item`. Его аналитика-точки (`chats_list_viewed` и т.п.) трекают только обезличенные магнитуды (диапазон количества, а не имена/идентификаторы чатов).

> **Связь events ↔ deep links.** Если NOX введёт deep-link-входы (см. [13-deep-links.md](13-deep-links.md)), соответствующее событие трекается в app-bloc на ветке маршрутизации deep-link-модели — там же, где навигация по типу ссылки. Конкретный deep-link-контракт NOX ещё не зафиксирован (deep links — открытый пункт, в приложении не реализованы); пока это плейсхолдер.

---

## 6. Приватность: opt-in по умолчанию и запрет PII

Аналитика NOX — поведенческая, не идентифицирующая, и согласованная с Signal-подобной моделью «минимизировать метаданные». Три жёстких инварианта:

1. **Opt-in по умолчанию.** Трекинг **выключен**, пока пользователь явно не включил его (`_enabled = false` в §4). До opt-in `initialize()` поднимает SDK, но `_applyOptState()` оставляет его в `optOutTracking()` — ни одного события не уходит. Это противоположность «включено по умолчанию с возможностью отписаться».
2. **Никакого PII и никаких метаданных переписки в свойствах событий и people-properties.** В `properties` / `setUserProperties` запрещены: email, имя/фамилия, телефон, текст и содержимое сообщений, имена/названия чатов, идентификаторы чатов и собеседников, любые токены/секреты. Допустимо: opaque-ссылки на нейтральные сущности (`item_id`), категориальные поля (`source`, `variant`, `method`), магнитуды и диапазоны (`duration_ms`, `parts_count`, `count_bucket`). `distinct_id` — это opaque user id бэкенда NOX, **не** email/телефон/имя.
3. **Глобальный opt-out.** `setTrackingEnabled(false)` → `client.optOutTracking()` — SDK перестаёт слать что-либо до `optInTracking()`. Состояние opt-in/opt-out персистится (через `AppConfigRepository`/local settings) и применяется на старте в `initialize()` до первого `track`. Точка вызова — экран приватности/настроек (toggle «Разрешить аналитику», **по умолчанию выключен**), который дёргает `AnalyticsBloc`/настройки-BLoC → `setTrackingEnabled`.

> **Правило свойства.** Прежде чем добавить ключ в `properties`/people-properties, ответь: «это категория/магнитуда/opaque-ссылка — или это идентифицирует человека либо его переписку?». Второе — запрещено (в т.ч. имя чата, его участники, содержимое сообщения). Сомневаешься — не клади (no speculative events из §1: поле добавляется только под конкретный analytics-вопрос).

`super-properties` (§4) — тоже без PII: `platform` / `app_version` / `build` / `environment` категориальны и не идентифицируют пользователя.

---

## 7. Точки вызова: init, identify/reset, трекинг из BLoC

Analytics — сквозной сервис; вызовы живут в presentation-слое (BLoC), резолвятся через `getIt<AnalyticsRepository>()`. Три класса точек:

**(1) Инициализация — в bootstrap, один раз.** `AnalyticsRepository.initialize()` вызывается из app-root после `configureDependencies(env)` (см. [02-dependency-injection.md](02-dependency-injection.md)) — например, в `AppRootBloc._onInitialize`, рядом с поднятием `DeepLinkRepository`. Best-effort: результат не блокирует запуск UI (`match` логирует ошибку и идёт дальше).

**(2) `identify` / `reset` — на границах auth-флоу** ([14-networking-and-auth.md](14-networking-and-auth.md)):

- после **успешного login/register** → `identify(noxUserId)` + `setUserProperties(...)`. `noxUserId` — это публичный id автора бэкенда NOX (его форма — открытый вопрос Q11, реестр `docs/client-backend/open-questions.md`), тот же, что зеркалит `distinct_id` (mirror-инвариант §1);
- после **logout** → `reset()` (разрывает связь с `distinct_id`, чтобы события следующего гостя не приклеились к предыдущему пользователю).

**(3) `trackEvent` — на ключевых переходах**, из соответствующего BLoC (worked-пример на нейтральной модели `Item`):

```dart
// внутри ItemCreateBloc — на ключевом переходе воронки:
_analyticsRepository.trackEvent(const AnalyticsEvent.itemCreateStarted(source: 'manual', variant: 'a'));
final result = await _itemRepository.create(...);
result.match(
  onData: (item) => _analyticsRepository.trackEvent(
    AnalyticsEvent.itemCreateSucceeded(itemId: item.id, partsCount: item.partsCount),
  ),
  onError: (e) => _analyticsRepository.trackEvent(
    // e — BaseRepositoryException (маркер без .name); сужаем до RepositoryException.
    AnalyticsEvent.itemCreateFailed(errorCode: e is RepositoryException ? e.name : 'unknown', reason: null),
  ),
);
```

> **Где именно в BLoC.** Трек-вызов ставится **после** разрешения `RepositoryResult` через `match` (исход известен) для `_succeeded`/`_failed`, и **до** старта длинной операции для `_started`. Сам `trackEvent` — fire-and-forget best-effort: не `await`-им его так, чтобы он задерживал переход состояния, и его ошибка не уводит BLoC в `Error` (он сам гасит сбой через `execute`/`LogRepository`).

`app_open` трекается из `AppRootBloc` на инициализации (после `initialize()`); экранные `screen_view`-подобные события (если решат вести их в analytics-провайдере) — из `initState` страницы или из route-observer'а, единообразно через `getIt<AnalyticsRepository>().trackEvent(...)`.

---

## 8. DI-регистрация и кодогенерация

`AnalyticsRepositoryImpl` помечен `@LazySingleton(as: AnalyticsRepository)` — биндинг к интерфейсу резолвится одним инстансом на всё приложение (см. [02-dependency-injection.md](02-dependency-injection.md)). Зависимости (`AppConfigRepository`, `LogRepository`) приходят через конструктор-инъекцию. После добавления файлов — кодогенерация: `*.freezed.dart` для `AnalyticsEvent`/`AnalyticsUserProperties` и `*.config.dart` для DI (`build_runner build --delete-conflicting-outputs`).

> **Нет `*.g.dart` у `AnalyticsEvent`.** Это чисто in-memory тип, никогда не сериализуется в JSON (как и State/Event BLoC из [05-presentation-layer.md](05-presentation-layer.md)) — генерируется только `*.freezed.dart`. Сериализацию в плоскую Map делает extension `properties`, а не `json_serializable`.

---

## Чеклист

- [ ] `lib/domain/repository/analytics/analytics_repository.dart` — интерфейс (`initialize`/`identify`/`setUserProperties`/`trackEvent`/`setTrackingEnabled`/`reset`), все методы `Future<RepositoryResult<...>>`.
- [ ] `lib/domain/model/analytics/analytics_event.dart` — `@freezed sealed` union + extension `name`/`properties` (типобезопасный таксоном, без строковых литералов по коду).
- [ ] `lib/domain/model/analytics/analytics_user_properties.dart` — `@freezed` value-объект people-properties, **без PII**.
- [ ] `lib/data/repository/analytics/analytics_repository_impl.dart` — `@LazySingleton(as: AnalyticsRepository)`, `with BaseRepositoryHelper`, методы через `execute(...)`; nullable handle SDK (пустой token ⇒ тихий no-op).
- [ ] Token — из `AppConfigRepository.config.analyticsProjectToken` per-флейвор (НЕ хардкод); `dev` = пустая строка; stage/prod — разные токены = разные проекты у провайдера.
- [ ] super-properties (`platform`/`app_version`/`build`/`environment`) регистрируются в `initialize()`; `platform` различает пять платформ (`ios|android|windows|linux|macos`); **без PII**.
- [ ] `identify(noxUserId)` после login/register (`distinct_id` = публичный id автора бэкенда NOX, его вид — открытый вопрос Q11; Принцип I); `reset()` после logout.
- [ ] Точки `trackEvent` заложены на этапе дизайна BLoC ключевых экранов/воронок; вызовы best-effort fire-and-forget — не блокируют переход состояния и не уводят BLoC в `Error`.
- [ ] **opt-in по умолчанию (NOX):** трекинг выключен (`_enabled = false`), пока пользователь явно не включил; toggle на экране приватности по умолчанию off.
- [ ] opt-out: `setTrackingEnabled(false)` → `optOutTracking()`, состояние персистится и применяется на старте; экран приватности дёргает toggle.
- [ ] Запрет PII и метаданных переписки в `properties`/people-properties проверен для каждого ключа (категория/магнитуда/opaque-ссылка — да; идентифицирует человека, чат или содержимое сообщения — нет).
- [ ] **Open question (продуктовое решение):** финальный список событий + их properties — вынести владельцу/продукту; стартовый таксоном §5 — лишь паттерн.
- [ ] Кодогенерация: `*.freezed.dart` (union/value-объект) + `*.config.dart` (DI); `*.g.dart` у `AnalyticsEvent` **не** генерируется.

---

## Связанные документы

[03-domain-layer.md](03-domain-layer.md) (`RepositoryResult`, `RepositoryException`, форма контракта репозитория, потребление через `match`), [04-data-layer.md](04-data-layer.md) (`BaseRepositoryHelper`, `execute(...)`, форма `*_repository_impl.dart`, `LogRepository` как сквозной — fail-silent логирование сбоев SDK), [05-presentation-layer.md](05-presentation-layer.md) (Freezed-BLoC, extension-геттеры на union, `AppRoot` + `AppRootBloc`, где звать `trackEvent`/`identify`/`reset`), [02-dependency-injection.md](02-dependency-injection.md) (`configureDependencies`, `@lazySingleton(as:)`, инъекция `AppConfigRepository`/`LogRepository`, bootstrap `main.dart`), [14-networking-and-auth.md](14-networking-and-auth.md) (auth-флоу login/register/logout — границы `identify`/`reset`; SDK ходит к analytics-провайдеру сам, сетевой слой не трогаем), [13-deep-links.md](13-deep-links.md) (deep-link-ветка маршрутизации ⇒ соответствующее событие, трек в app-bloc), [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md) (`analyticsProjectToken` per-флейвор из зашифрованных секретов, `public.analytics.project_token`), [01-stack-and-tooling.md](01-stack-and-tooling.md) (`mixpanel_flutter` как опциональная vendor-зависимость, версии пакетов).
