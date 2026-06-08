# 17 — Клиентская аналитика (Mixpanel)

> **Назначение:** зафиксировать клиентский analytics-слой приложения Speech AI Mobile как сквозной (cross-cutting) сервис — интерфейс `AnalyticsRepository` в `lib/domain/repository/analytics/`, Mixpanel-имплементацию `AnalyticsRepositoryImpl` в `lib/data/repository/analytics/`, типобезопасный таксоном событий через `@freezed`-union `AnalyticsEvent`, инициализацию SDK (`mixpanel_flutter`) с project-token'ом из флейвора (`AppConfigRepository`, НЕ хардкод), super-properties (`user_id` / `platform` / `app_version` / `build`), правила приватности (opt-out, без PII) и точки вызова из BLoC. Слой проектируется **с нуля** — в проекте-каноне владельца (existlive) аналитики нет; зеркалируется лишь общая форма repository-слоя.
> **Когда читать:** перед поднятием папки `lib/{domain,data}/repository/analytics/`, перед добавлением первой точки трекинга в любой BLoC, и обязательно — при расширении таксонома событий (новое событие = новый вариант `AnalyticsEvent`, а не строковый литерал по коду).
> **Связанные документы:** [03-domain-layer.md](03-domain-layer.md) (`RepositoryResult`, `RepositoryException`, контракты репозиториев), [04-data-layer.md](04-data-layer.md) (`BaseRepositoryHelper`, `execute(...)`, форма `*_repository_impl.dart`, `LogRepository` как сквозной), [05-presentation-layer.md](05-presentation-layer.md) (Freezed-BLoC, `AppRoot` + `AppRootBloc`, где звать `trackEvent`), [02-dependency-injection.md](02-dependency-injection.md) (`configureDependencies`, `@lazySingleton(as:)`, `AppConfigRepository`, bootstrap `main.dart`), [14-networking-and-auth.md](14-networking-and-auth.md) (auth-флоу: `identify` после login / `reset` после logout — `distinct_id` = Appwrite user `$id`; сетевой слой не трогаем — SDK ходит в Mixpanel сам), [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md) (`mixpanelProjectToken` per флейвор из зашифрованных секретов).

---

## 0. Идея: аналитика как первоклассный архитектурный компонент

Этот документ — единственный дом контракта клиентской аналитики. Он отвечает на три вопроса:

1. **Зачем клиентская аналитика отдельным слоем** — продуктовые воронки (`Free → Premium`, `OCR → TTS → listening`) — это **поведенческие** данные, которых backend-строки в Appwrite не дают; их источник — клиентские события в Mixpanel. Прямое следствие Constitution Принципа XIII (см. §1). §1.
2. **Как устроен слой** — `AnalyticsRepository` (контракт в `lib/domain/`) + `AnalyticsRepositoryImpl` (Mixpanel-обёртка в `lib/data/`), типобезопасный таксоном `AnalyticsEvent`, инициализация с токеном из конфига, super-properties, приватность. §2–§6.
3. **Откуда и когда звать трекинг** — из presentation-слоя (BLoC) на ключевых переходах; `identify`/`reset` завязаны на auth-флоу; init — в bootstrap. §7.

> **Единый пакет.** Все пути — `lib/...` внутри одного пакета `speech_ai_mobile` (worked example). Импорты — полные `package:speech_ai_mobile/...`, относительные `../` запрещены (кроме `part`-директив).

> **Аналитика никогда не роняет UX.** Сбой SDK, отсутствие токена, нет сети — всё это поглощается молча (fail-silent через `LogRepository`-предупреждение), ровно как best-effort broker-dispatch на бэкенде. Ни один вызов трекинга не должен бросать исключение в UI-поток и не должен блокировать пользовательское действие.

---

## 1. Связь с Constitution Принципом XIII (Admin & Analytics Readiness by Design)

Принцип XIII (`.specify/memory/constitution.md`, monorepo-wide — действует во **всех** проектах наравне с Принципом I) требует, чтобы **каждая** фича захватывала данные/события/queryable-поля, нужные admin-панели и продуктовой аналитике, **в момент первой записи** строки/события — а не ретрофитила позже. На backend это означает write-time capture в Appwrite-коллекциях: attribution (`owner_id`/actor IDs), timestamps (`created_at`/`updated_at` + время событий), явные status/lifecycle-enum'ы, counters/magnitudes (а не только booleans). Связка с Принципом VII (No DB Migrations): сигнал, не записанный в момент write, теряется навсегда — «добавить колонку потом» нельзя.

**Что из этого следует для клиента:**

- **Поведенческая аналитика — клиентская по природе.** Backend-строки фиксируют *состояние* (record создан, track `ready`), но не *поведение* (где пользователь нажал, на каком шаге воронки отвалился, что показал paywall). Принцип XIII прямо обосновывает, **зачем** в mobile нужен отдельный analytics-слой: это источник продуктовых воронок, которые admin-панель не получит из live-БД.
- **Capture-not-build на клиенте тоже.** Каждый значимый пользовательский шаг (экран, действие в воронке, успех/ошибка длинной операции) закладывает точку трекинга **на этапе дизайна экрана/BLoC**, а не доклеивается потом. Аналитика — первоклассный компонент, а не afterthought.
- **No speculative events.** Заводим интерфейс и стартовый таксоном (§5), но **конкретный финальный список событий — продуктовое решение** (см. §5). Не плодим события «на всякий случай».
- **Mirror-инвариант идентификатора.** Где у фичи есть и backend-строка, и клиентское событие — идентификатор пользователя должен совпадать: Mixpanel `distinct_id` ← Appwrite user `$id` (тот же контракт, что у backend `owner_id` и RevenueCat `app_user_id`). Это связывает поведенческую воронку с серверной строкой при кросс-анализе.

> **Где именно «момент первой записи» на клиенте.** Для парных длинных операций (TTS-джоба, создание record) трекинг — это `_started` в начале и `_succeeded`/`_failed` в исходе (см. §5). Это и есть «counters/magnitudes, а не только boolean» из XIII: воронка `started → succeeded/failed` даёт drop-off, который один boolean «готово/нет» не покажет.

---

## 2. Раскладка и форма слоя (зеркало канона existlive)

В проекте-каноне владельца (existlive) клиентского analytics-слоя **нет** — ни `mixpanel_flutter`, ни `firebase_analytics`, ни одного `trackEvent`. Поэтому копировать готовый паттерн «как трекаются события» неоткуда: слой проектируется с нуля. Зеркалируется лишь **общая форма** repository-слоя, которую existlive фиксирует для всех областей:

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
        analytics_repository_impl.dart  # @LazySingleton(as: AnalyticsRepository) — Mixpanel-обёртка
```

> **SDK ходит в Mixpanel сам.** `mixpanel_flutter` отправляет события напрямую в Mixpanel-ingest, **не** через `ApiClient`/Dio из [14-networking-and-auth.md](14-networking-and-auth.md). Сетевой слой и auth-pipeline клиента аналитика не трогает — это разные транспорты. Единственная точка пересечения с auth — `identify`/`reset` (§4, §7).

---

## 3. Доменный контракт `AnalyticsRepository`

Интерфейс минимален и не утекает деталями Mixpanel: presentation знает только «трекни событие», «опознай пользователя», «сбрось», «обнови свойства профиля», «выключи аналитику».

`lib/domain/repository/analytics/analytics_repository.dart`:

```dart
import 'package:speech_ai_mobile/domain/model/analytics/analytics_event.dart';
import 'package:speech_ai_mobile/domain/model/analytics/analytics_user_properties.dart';
import 'package:speech_ai_mobile/domain/repository/base/repository_result.dart';

abstract interface class AnalyticsRepository {
  /// Поднимает SDK (token из AppConfigRepository), ставит super-properties.
  /// Best-effort: пустой token (dev / opt-out) => no-op success.
  Future<RepositoryResult<bool>> initialize();

  /// Связывает дальнейшие события с пользователем. distinct_id == Appwrite user `$id`.
  Future<RepositoryResult<bool>> identify(String userId);

  /// Обновляет свойства профиля пользователя (people-properties). Без PII.
  Future<RepositoryResult<bool>> setUserProperties(AnalyticsUserProperties properties);

  /// Один трек-вызов. Типобезопасный — никаких строковых литералов на стороне вызова.
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

`lib/domain/model/analytics/analytics_event.dart`:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'analytics_event.freezed.dart';

@freezed
sealed class AnalyticsEvent with _$AnalyticsEvent {
  const factory AnalyticsEvent.appOpen({required bool isFirstOpen}) = AppOpenEvent;

  const factory AnalyticsEvent.authLogin({required String method}) = AuthLoginEvent;

  const factory AnalyticsEvent.recordCreateStarted({
    required String source, // text | ocr | import
    String? languageId,
  }) = RecordCreateStartedEvent;

  const factory AnalyticsEvent.recordCreateSucceeded({
    required String recordId,
    required int sourcesCount,
  }) = RecordCreateSucceededEvent;

  const factory AnalyticsEvent.recordCreateFailed({
    required String errorCode,
    String? reason,
  }) = RecordCreateFailedEvent;

  const factory AnalyticsEvent.paywallViewed({required String trigger}) = PaywallViewedEvent;
  // … остальные варианты из §5
}

extension AnalyticsEventX on AnalyticsEvent {
  /// snake_case-имя события для Mixpanel.
  String get name => switch (this) {
        AppOpenEvent() => 'app_open',
        AuthLoginEvent() => 'auth_login',
        RecordCreateStartedEvent() => 'record_create_started',
        RecordCreateSucceededEvent() => 'record_create_succeeded',
        RecordCreateFailedEvent() => 'record_create_failed',
        PaywallViewedEvent() => 'paywall_viewed',
      };

  /// Типизированные properties → плоская Map для SDK. БЕЗ PII.
  Map<String, Object?> get properties => switch (this) {
        AppOpenEvent(:final isFirstOpen) => {'is_first_open': isFirstOpen},
        AuthLoginEvent(:final method) => {'method': method},
        RecordCreateStartedEvent(:final source, :final languageId) => {
            'source': source,
            if (languageId != null) 'language_id': languageId,
          },
        RecordCreateSucceededEvent(:final recordId, :final sourcesCount) => {
            'record_id': recordId,
            'sources_count': sourcesCount,
          },
        RecordCreateFailedEvent(:final errorCode, :final reason) => {
            'error_code': errorCode,
            if (reason != null) 'reason': reason,
          },
        PaywallViewedEvent(:final trigger) => {'trigger': trigger},
      };
}
```

> **Гарантия типобезопасности.** Имена событий и ключи properties живут в одном месте (extension над union), а не разбросаны строковыми литералами по BLoC'ам. Добавление события = новый `const factory` + ветка в `name`/`properties`; компилятор заставит закрыть `switch`.

`AnalyticsUserProperties` — `@freezed` value-объект people-properties (plan, locale, и т.п. — **без PII**, см. §6); опускаю тело ради краткости, форма — обычный `@freezed`-класс с `toMixpanelMap()`-extension.

---

## 4. Mixpanel-имплементация

`AnalyticsRepositoryImpl` оборачивает `mixpanel_flutter`, биндится через `@LazySingleton(as: AnalyticsRepository)`, использует `BaseRepositoryHelper.execute(...)` для единообразного guarded-логирования (см. [04-data-layer.md](04-data-layer.md)). Внутренне держит nullable `Mixpanel?` — `null` означает «не инициализирован / выключен / пустой token», и тогда каждый трек-вызов тихо no-op'ит.

`lib/data/repository/analytics/analytics_repository_impl.dart`:

```dart
import 'package:injectable/injectable.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';
import 'package:speech_ai_mobile/data/exception/base_repository_helper.dart';
import 'package:speech_ai_mobile/domain/model/analytics/analytics_event.dart';
import 'package:speech_ai_mobile/domain/model/analytics/analytics_user_properties.dart';
import 'package:speech_ai_mobile/domain/repository/base/repository_result.dart';
import 'package:speech_ai_mobile/domain/repository/analytics/analytics_repository.dart';
import 'package:speech_ai_mobile/domain/repository/app_config/app_config_repository.dart';
import 'package:speech_ai_mobile/domain/repository/log_repository.dart';

@LazySingleton(as: AnalyticsRepository)
class AnalyticsRepositoryImpl with BaseRepositoryHelper implements AnalyticsRepository {
  AnalyticsRepositoryImpl(this._appConfigRepository, this._logRepository);

  final AppConfigRepository _appConfigRepository;
  final LogRepository _logRepository;

  Mixpanel? _mixpanel;
  bool _enabled = true;

  @override
  Future<RepositoryResult<bool>> initialize() => execute(() async {
        final token = _appConfigRepository.config.mixpanelProjectToken;
        if (token.isEmpty) {
          // dev-флейвор / пустой секрет — аналитика отключена, это НЕ ошибка.
          _logRepository.debug(target: 'AnalyticsRepositoryImpl', message: 'Analytics disabled: empty Mixpanel token');
          return RepositoryResult.success(data: false);
        }
        final mixpanel = await Mixpanel.init(token, trackAutomaticEvents: false);

        // super-properties — клеятся ко ВСЕМ событиям автоматически.
        final cfg = _appConfigRepository.config;
        mixpanel.registerSuperProperties({
          'platform': cfg.platform, // ios | android
          'app_version': cfg.appVersion, // CalVer YY.M.D
          'build': cfg.buildNumber, // shifted-epoch build
          'environment': cfg.environment, // stage | production
        });

        _mixpanel = mixpanel;
        await _applyOptState();
        return RepositoryResult.success(data: true);
      });

  @override
  Future<RepositoryResult<bool>> identify(String userId) => execute(() async {
        // distinct_id == Appwrite user `$id` — совпадает с backend owner_id (Принцип XIII).
        await _mixpanel?.identify(userId);
        return RepositoryResult.success(data: _mixpanel != null);
      });

  @override
  Future<RepositoryResult<bool>> setUserProperties(AnalyticsUserProperties properties) => execute(() async {
        final people = _mixpanel?.getPeople();
        properties.toMixpanelMap().forEach((k, v) => people?.set(k, v)); // people-properties, без PII
        return RepositoryResult.success(data: _mixpanel != null);
      });

  @override
  Future<RepositoryResult<bool>> trackEvent(AnalyticsEvent event) => execute(() async {
        if (!_enabled || _mixpanel == null) {
          return RepositoryResult.success(data: false); // opt-out / не инициализирован — тихий no-op
        }
        await _mixpanel!.track(event.name, properties: event.properties);
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
        await _mixpanel?.reset(); // разрывает связь с distinct_id (после logout)
        return RepositoryResult.success(data: _mixpanel != null);
      });

  Future<void> _applyOptState() async {
    if (_enabled) {
      await _mixpanel?.optInTracking();
    } else {
      await _mixpanel?.optOutTracking();
    }
  }
}
```

> **Token не хардкодится.** `mixpanelProjectToken` приходит из `AppConfigRepository.config` per-флейвор (см. [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md)): public-token из `secrets/{stage,production}.enc.yaml::public.mixpanel.project_token`, прокидывается в bundle через `--dart-define`/флейвор-конфиг. В `dev` token — **пустая строка**, поэтому `initialize()` отдаёт `success(data: false)` и локалки событий не шлют. Это разделяет stage и prod **разными токенами** (= разные Mixpanel-проекты), а не env-тегом.

### Mixpanel-проекты (`docs/operations/external_resources.md` §4)

| Env | Project name | Project ID | Source токена |
|---|---|---|---|
| Stage | `Speech AI Stage` | `4022441` | `public.mixpanel.project_token` в `secrets/stage.enc.yaml` |
| Production | `Speech AI Production` | `4022442` | `public.mixpanel.project_token` в `secrets/production.enc.yaml` |
| Dev | — | — | пустая строка (события не шлются) |

EU data-residency (`eu.mixpanel.com`), Free-план (1M событий/мес на проект). `API Secret` (`secret.mixpanel.api_secret`, server-only) на клиенте **не используется** — архитектура mobile-only, backend в Mixpanel напрямую не пишет.

---

## 5. Стартовый таксоном событий — как ПАТТЕРН (не финальный контракт)

> **Финальный список событий — продуктовое решение, не инженерное.** В `docs/product/overview_0.2.md` явно стоит «TODO: подготовить список событий». Поэтому ниже — стартовый **паттерн** + соглашения об именовании, **а не зафиксированный контракт**. Продуктовые доки фиксируют split двух систем: **Firebase Analytics** — объём/сессии (`app_open`, `screen_view`, `user_engaged`), **Mixpanel** — поведенческие воронки/инсайты (`record_create_*`, `tts_track_*`, `translation_toggled`, `share_link_opened`). Этот документ — про Mixpanel-часть.

**Соглашения об именовании (паттерн):**

- Имена событий — `snake_case`, форма `subject_verb` (`record_create_started`); исходы — состоянием/прошедшим временем (`_succeeded` / `_failed`).
- Парные длинные операции — `_started` → `_succeeded` / `_failed` (для воронок и drop-off): это «counters/magnitudes, а не boolean» из Принципа XIII.
- Properties — типизированные: `source` (откуда инициировано), `language_id`, `voice_id`, `plan` (`free`/`premium`), `duration_ms`, `error_code` для `_failed`.
- `distinct_id` = Appwrite user `$id`; `identify` после login, `reset` после logout (§7).

**Стартовый набор (worked-пример, ориентирован на воронки product-doc'ов — `OCR → TTS → listening`, `Free → Premium`):**

| Событие | Когда | Ключевые properties |
|---|---|---|
| `app_open` | холодный/тёплый старт (дублируется в Firebase как session) | `is_first_open` |
| `onboarding_completed` | прошёл onboarding | `steps_seen` |
| `auth_login` | успешный логин | `method` (`email`/`google`/`apple`) |
| `auth_register` | успешная регистрация | `method` |
| `record_create_started` | пользователь инициировал создание record | `source` (`text`/`ocr`/`import`), `language_id` |
| `record_create_succeeded` | record создан (`201`/`200`) | `record_id`, `sources_count` |
| `record_create_failed` | ошибка создания | `error_code`, `reason` |
| `tts_track_started` | старт TTS-джобы | `voice_id`, `language_id`, `estimated_seconds` |
| `tts_track_completed` | трек перешёл в `ready` | `track_id`, `duration_ms` |
| `playback_started` | начал слушать | `track_id`, `speed` |
| `translation_toggled` | переключил перевод | `enabled` |
| `share_link_opened` | открыл/создал share-ссылку | `record_id` |
| `paywall_viewed` | показан paywall | `trigger` (где сработал лимит) |
| `subscription_purchased` | успешная подписка (RevenueCat) | `plan` (`monthly`/`annual`) |

Эти события закрывают воронки, явно названные продуктовыми доками: «Imported → Processed → Played», «переводы → TTS-jobs → completed listening», конверсия `Free → Premium`, retention 30/90 дней.

> **`method=google`/`apple` — только Phase 2.** OAuth-логин (`/api/v1/auth/login_with_google/`, `/login_with_apple/`) **route-deactivated** в Phase 1 (возвращает `404`; см. `docs/spec/pending_implementations.md` §OAuth Phase 2). В Phase 1 у `auth_login`/`auth_register` фактически только `method=email`; `google`/`apple` появятся после реактивации OAuth. (Финальный список событий — продуктовое решение, OQ-3.)

> **Связь events ↔ deep links.** `share_link_opened` коррелирует с входной share-ссылкой из [13-deep-links.md](13-deep-links.md) (`APPWRITE_SHARE_URL`/`share/{record_id}`): событие трекается в app-bloc на ветке маршрутизации share-модели — там же, где навигация по `is`-типу.

---

## 6. Приватность: opt-out и запрет PII

Аналитика — поведенческая, не идентифицирующая. Два жёстких инварианта:

1. **Никакого PII в свойствах событий и people-properties.** В `properties` / `setUserProperties` запрещены: email, имя/фамилия, телефон, текст пользовательских record'ов, содержимое source-файлов, любые токены/секреты. Допустимо: непрямые идентификаторы-ссылки (`record_id`, `track_id`, `voice_id`, `language_id`), категориальные поля (`plan`, `source`, `method`, `trigger`), магнитуды (`duration_ms`, `sources_count`, `estimated_seconds`). `distinct_id` — это Appwrite `$id` (opaque), **не** email.
2. **Глобальный opt-out.** `setTrackingEnabled(false)` → `mixpanel.optOutTracking()` — SDK перестаёт слать что-либо до `optInTracking()`. Состояние opt-out персистится (через `AppConfigRepository`/local settings) и применяется на старте в `initialize()` до первого `track`. Точка вызова — экран приватности/настроек (toggle «Разрешить аналитику»), который дёргает `AnalyticsBloc`/настройки-BLoC → `setTrackingEnabled`.

> **Правило свойства.** Прежде чем добавить ключ в `properties`/people-properties, ответь: «это категория/магнитуда/opaque-ссылка — или это идентифицирует человека?». Второе — запрещено. Сомневаешься — не клади (capture-not-build из §1: поле добавляется только под конкретный analytics-вопрос).

`super-properties` (§4) — тоже без PII: `platform` / `app_version` / `build` / `environment` категориальны и не идентифицируют пользователя.

---

## 7. Точки вызова: init, identify/reset, трекинг из BLoC

Analytics — сквозной сервис; вызовы живут в presentation-слое (BLoC), резолвятся через `getIt<AnalyticsRepository>()`. Три класса точек:

**(1) Инициализация — в bootstrap, один раз.** `AnalyticsRepository.initialize()` вызывается из app-root после `configureDependencies(env)` (см. [02-dependency-injection.md](02-dependency-injection.md)) — например, в `AppRootBloc._onInitialize`, рядом с поднятием `DeepLinkRepository`. Best-effort: результат не блокирует запуск UI (`match` логирует ошибку и идёт дальше).

**(2) `identify` / `reset` — на границах auth-флоу** ([14-networking-and-auth.md](14-networking-and-auth.md)):

- после **успешного login/register** (получены access+refresh JWT) → `identify(appwriteUserId)` + `setUserProperties(...)`. `appwriteUserId` — это `$id` пользователя, тот же, что backend пишет в `owner_id` (Принцип XIII, §1);
- после **logout** → `reset()` (разрывает связь с `distinct_id`, чтобы события следующего гостя не приклеились к предыдущему пользователю).

**(3) `trackEvent` — на ключевых переходах**, из соответствующего BLoC:

```dart
// внутри RecordsCreateBloc — на ключевом переходе воронки:
_analyticsRepository.trackEvent(const AnalyticsEvent.recordCreateStarted(source: 'ocr', languageId: 'en'));
final result = await _recordsRepository.create(...);
result.match(
  onData: (record) => _analyticsRepository.trackEvent(
    AnalyticsEvent.recordCreateSucceeded(recordId: record.id, sourcesCount: record.sourcesCount),
  ),
  onError: (e) => _analyticsRepository.trackEvent(
    // e — BaseRepositoryException (маркер без .name); сужаем до RepositoryException.
    AnalyticsEvent.recordCreateFailed(errorCode: e is RepositoryException ? e.name : 'unknown', reason: null),
  ),
);
```

> **Где именно в BLoC.** Трек-вызов ставится **после** разрешения `RepositoryResult` через `match` (исход известен) для `_succeeded`/`_failed`, и **до** старта длинной операции для `_started`. Сам `trackEvent` — fire-and-forget best-effort: не `await`-им его так, чтобы он задерживал переход состояния, и его ошибка не уводит BLoC в `Error` (он сам гасит сбой через `execute`/`LogRepository`).

`app_open` трекается из `AppRootBloc` на инициализации (после `initialize()`); экранные `screen_view`-подобные события (если решат вести их в Mixpanel, а не только Firebase) — из `initState` страницы или из route-observer'а, единообразно через `getIt<AnalyticsRepository>().trackEvent(...)`.

---

## 8. DI-регистрация и кодогенерация

`AnalyticsRepositoryImpl` помечен `@LazySingleton(as: AnalyticsRepository)` — биндинг к интерфейсу резолвится одним инстансом на всё приложение (см. [02-dependency-injection.md](02-dependency-injection.md)). Зависимости (`AppConfigRepository`, `LogRepository`) приходят через конструктор-инъекцию. После добавления файлов — кодогенерация: `*.freezed.dart` для `AnalyticsEvent`/`AnalyticsUserProperties` и `*.config.dart` для DI (`build_runner build --delete-conflicting-outputs`).

> **Нет `*.g.dart` у `AnalyticsEvent`.** Это чисто in-memory тип, никогда не сериализуется в JSON (как и State/Event BLoC из [05-presentation-layer.md](05-presentation-layer.md)) — генерируется только `*.freezed.dart`. Сериализацию в плоскую Map делает extension `properties`, а не `json_serializable`.

---

## Чеклист

- [ ] `lib/domain/repository/analytics/analytics_repository.dart` — интерфейс (`initialize`/`identify`/`setUserProperties`/`trackEvent`/`setTrackingEnabled`/`reset`), все методы `Future<RepositoryResult<...>>`.
- [ ] `lib/domain/model/analytics/analytics_event.dart` — `@freezed sealed` union + extension `name`/`properties` (типобезопасный таксоном, без строковых литералов по коду).
- [ ] `lib/domain/model/analytics/analytics_user_properties.dart` — `@freezed` value-объект people-properties, **без PII**.
- [ ] `lib/data/repository/analytics/analytics_repository_impl.dart` — `@LazySingleton(as: AnalyticsRepository)`, `with BaseRepositoryHelper`, методы через `execute(...)`; nullable `Mixpanel?` (пустой token ⇒ тихий no-op).
- [ ] Token — из `AppConfigRepository.config.mixpanelProjectToken` per-флейвор (НЕ хардкод); `dev` = пустая строка; stage/prod — разные токены = разные проекты (`4022441` / `4022442`).
- [ ] super-properties (`platform`/`app_version`/`build`/`environment`) регистрируются в `initialize()`; **без PII**.
- [ ] `identify(appwriteUserId)` после login/register (`distinct_id` = Appwrite `$id` = backend `owner_id`, Принцип XIII); `reset()` после logout.
- [ ] Точки `trackEvent` заложены на этапе дизайна BLoC ключевых экранов/воронок; вызовы best-effort fire-and-forget — не блокируют переход состояния и не уводят BLoC в `Error`.
- [ ] opt-out: `setTrackingEnabled(false)` → `optOutTracking()`, состояние персистится и применяется на старте; экран приватности дёргает toggle.
- [ ] Запрет PII в `properties`/people-properties проверен для каждого ключа (категория/магнитуда/opaque-ссылка — да; идентифицирует человека — нет).
- [ ] **Open question (продуктовое решение):** финальный список событий + их properties — вынести владельцу/продукту; стартовый таксоном §5 — лишь паттерн.
- [ ] Кодогенерация: `*.freezed.dart` (union/value-объект) + `*.config.dart` (DI); `*.g.dart` у `AnalyticsEvent` **не** генерируется.

---

## Связанные документы

[03-domain-layer.md](03-domain-layer.md) (`RepositoryResult`, `RepositoryException`, форма контракта репозитория, потребление через `match`), [04-data-layer.md](04-data-layer.md) (`BaseRepositoryHelper`, `execute(...)`, форма `*_repository_impl.dart`, `LogRepository` как сквозной — fail-silent логирование сбоев SDK), [05-presentation-layer.md](05-presentation-layer.md) (Freezed-BLoC, extension-геттеры на union, `AppRoot` + `AppRootBloc`, где звать `trackEvent`/`identify`/`reset`), [02-dependency-injection.md](02-dependency-injection.md) (`configureDependencies`, `@lazySingleton(as:)`, инъекция `AppConfigRepository`/`LogRepository`, bootstrap `main.dart`), [14-networking-and-auth.md](14-networking-and-auth.md) (auth-флоу login/register/logout — границы `identify`/`reset`; SDK ходит в Mixpanel сам, сетевой слой не трогаем), [13-deep-links.md](13-deep-links.md) (share-ссылка ⇒ `share_link_opened`, трек в app-bloc на ветке маршрутизации), [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md) (`mixpanelProjectToken` per-флейвор из зашифрованных секретов, `public.mixpanel.project_token`), [01-stack-and-tooling.md](01-stack-and-tooling.md) (`mixpanel_flutter`, версии пакетов).
