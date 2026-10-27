# Data Model: App-state flow (spine приложения)

**Feature**: `009-app-state-flow` | **Date**: 2026-06-25 | **Phase**: 1 (Design)

Все доменные типы — **Freezed, только `.freezed.dart`** (без `*.g.dart`/`fromJson` — блюпринт `03 §6`). Производная логика — в `extension`-геттерах, не в теле классов. Доменный слой ни от чего не зависит (`presentation → domain ← data`). Пути ниже — целевые (новые), в одном пакете `nox_app`.

---

## 1. `AppStateType` (enum)

**Файл**: `lib/domain/model/app/app_state_type.dart`

```text
enum AppStateType { init, unauthorized, registrationPending, authorized }
```

| Значение | Смысл | Top-level экран |
|---|---|---|
| `init` | Не разрешено (boot sentinel) | `SplashPage` (1.1) |
| `unauthorized` | Нет сохранённой сессии | `LoginPage` (2.1) |
| `registrationPending` | Идентификатор есть, `onboardingComplete=false` | `SetUsernamePage` (2.3) |
| `authorized` | Идентификатор есть, `onboardingComplete=true` | `TabBarShell` (4.1) |

NOX-адаптация исходника: удалены `authorizedGuest` (нет гостя) и `selectProfileType` (нет ролей) → заменён на `registrationPending` (first-login gate имени).

## 2. `SessionModel` (Freezed value-object)

**Файл**: `lib/domain/model/app/session_model.dart`

| Поле | Тип | Default | Описание |
|---|---|---|---|
| `identifier` | `String` | — (required) | Технический анонимный идентификатор (`Your ID`). **Security-чувствительный** → secure storage. Пустая строка трактуется как «нет сессии». |
| `label` | `String?` | `null` | Публичный display-label (кэш). Несекретный → SharedPreferences. |
| `onboardingComplete` | `bool` | `false` | Завершён ли first-login (шаг `Set username` 2.3). **Дискриминатор** `registrationPending` ↔ `authorized`. Несекретный → SharedPreferences. |

- Единственный вход резолвера. Заменяет `user: UserModel?` из исходника (доменной `UserModel` в NOX нет).
- Без бизнес-логики в теле; при необходимости — `extension SessionModelExt`.

## 3. `AppStateModel` (Freezed value-object)

**Файл**: `lib/domain/model/app/app_state_model.dart`

| Поле | Тип | Default | Описание |
|---|---|---|---|
| `state` | `AppStateType` | — (required) | Текущая фаза жизненного цикла. |
| `session` | `SessionModel?` | — (required, nullable) | Разрешённая сессия (null до резолюции / в `unauthorized`). |
| `sessionExpired` | `bool` | `false` | **Одноразовый** признак причины выхода. `true` ТОЛЬКО на `unauthorized`-модели от forced-logout. |

```text
factory AppStateModel.init() => AppStateModel(state: AppStateType.init, session: null);
```

- **Проекция**, не источник правды; пересчитывается на каждом cold-start; отдельно не персистится (нет DAO — миграционный гайд §1.1).

## 4. Состояние резолвера (правила перехода)

Алгоритм `AppStateRepositoryImpl.fetchAppState({bool sessionExpired = false})` (cache-only, без сети; первый матч выигрывает):

```text
session := await sessionRepository.readSession()        // RepositoryResult<SessionModel?>
match session:
  onError(e)                          → AppStateModel(unauthorized, session: null, sessionExpired)   // fail-safe (FR-015)
  onData(null | identifier == '')     → AppStateModel(unauthorized, session: null, sessionExpired)   // (FR-003)
  onData(s) & !s.onboardingComplete   → AppStateModel(registrationPending, session: s)
  onData(s) &  s.onboardingComplete   → AppStateModel(authorized, session: s)
→ _subject.add(RepositoryResult.success(data: model))   // пуш в BehaviorSubject
```

`sessionExpired` «едет» только на ветке `unauthorized` (forced-logout очищает сессию → всегда сюда). Любой throw внутри `execute` → `RepositoryResult.error` + лог; интерпретируется потребителем как «не разрешено».

## 5. Диаграмма переходов app-state

```text
                 (cold start, cache-only resolve)
   ┌──────┐  resolve   ┌──────────────┐
   │ init │ ─────────▶ │ unauthorized │ ◀─────────────┐
   └──────┘            └──────────────┘               │
      │                      │ signIn (new id)        │ logout(forced|ordinary)
      │ resolve              ▼                         │  (clear → fetchAppState)
      │            ┌─────────────────────┐            │
      ├──────────▶ │ registrationPending │ ───────────┤
      │            └─────────────────────┘ completeOnboarding
      │                      │                         │
      │ resolve              ▼ (or signIn registered)  │
      │            ┌──────────────┐                    │
      └──────────▶ │  authorized  │ ───────────────────┘
                   └──────────────┘
```

- Первый переход из `init` удержан за splash-анимацией (двухфазное применение); последующие — немедленно.
- `signIn` под `registeredIds` → сразу `authorized`; под прочим id → `registrationPending`.

## 6. App-level BLoC: расширение `AppRootState` / `AppRootEvent`

**Файлы** (правка существующих): `lib/presentation/app/bloc/app_root_state.dart`, `app_root_event.dart`, `app_root_bloc.dart`.

`AppRootState` (Freezed, дополняется):

| Поле | Тип | Default | Описание |
|---|---|---|---|
| `themeMode` | `ThemeMode` | `system` | (существующее) |
| `lastAppState` | `AppStateModel` | `AppStateModel.init()` | Свежайшее значение со стрима (обновляется на каждой эмиссии). |
| `appliedAppState` | `AppStateModel` | `AppStateModel.init()` | Значение, применённое к навигатору (только по `applyAppState`). |
| `isReady` | `bool` | `false` | Стало `true` на первой эмиссии с данными. |

`AppRootEvent` (Freezed sealed, дополняется): существующие `initialize()`, `setTheme(themeMode)` + новые `updateAppState(RepositoryResult<AppStateModel> result)`, `applyAppState()`.

Логика (миграционный гайд §5.1):
- `initialize` → подписка `getIt<AppStateRepository>().watchAppState().listen((r) => add(updateAppState(r)))` (идемпотентно, `_subscription ??=`).
- `updateAppState` → если `result.hasData`: `isNeedApply = state.isReady`; `emit(copyWith(lastAppState: data, isReady: true))`; если `isNeedApply` → `add(applyAppState())`.
- `applyAppState` → если `state.isReady`: `emit(copyWith(appliedAppState: state.lastAppState))`.
- `close()` отменяет `_subscription`.

## 7. Хранилище (ключи)

| Сигнал | Бэкенд | Ключ |
|---|---|---|
| `identifier` | `flutter_secure_storage` | `session.identifier` |
| `onboardingComplete` | `shared_preferences` (bool) | `session.onboarding_complete` |
| `label` (кэш) | `shared_preferences` (string) | `session.label` |

`clear()` (logout, полный wipe): `secureStorage.deleteAll()` + `prefs.remove('session.onboarding_complete')` + `prefs.remove('session.label')`. Конституция I — «Logout полностью стирает идентификатор и локальные данные».

## 8. Доменные контракты (сводно; детали — `contracts/`)

| Контракт | Файл | Члены |
|---|---|---|
| `AppStateRepository` | `lib/domain/repository/app/app_state_repository.dart` | `Stream<RepositoryResult<AppStateModel>> watchAppState()`; `Future<RepositoryResult<AppStateModel>> fetchAppState({bool sessionExpired = false})`; `AppStateType? get currentState` |
| `SessionRepository` | `lib/domain/repository/app/session_repository.dart` | `readSession()`; `saveIdentifier(...)`; `setOnboardingComplete(...)`; `clear()` |
| `AuthRepository` | `lib/domain/repository/app/auth_repository.dart` | `signIn({identifier})`; `completeOnboarding({label?})`; `logout({forced})` |

## 9. Ошибки

- Переиспользуется маркер `BaseRepositoryException` + enum `RepositoryException { unknown, internal, authentication, connection, unauthenticated, notFound }`.
- Для `sessionExpired` отдельный доменный тип ошибки НЕ нужен — это поле `AppStateModel`, а не исключение. (Будущий 401-триггер замапит `unauthenticated` → forced-logout — FR-017, отложено.)
- `BaseRepositoryHelper.execute` маппит `DioException → internal`, прочее → `unknown` (на этом этапе сети нет — актуально для будущего).

## 10. Валидационные правила (из требований)

- `identifier`: клиент не валидирует формат (FR-011); пустая строка ≠ сессия.
- `onboardingComplete`: ставится `true` при завершении `Set username` (2.3) или для `registeredIds` при sign-in (FR-019).
- `currentState == null` ≠ `unauthorized`: «не разрешено ещё» — деструктивные действия в этом окне подавляются (edge-case; FR-004/FR-016).
