# Contract: Repository-интерфейсы spine

**Feature**: `009-app-state-flow` | **Phase**: 1

Публичные доменные контракты, экспонируемые фичей. Все методы возвращают `RepositoryResult<T>` / `Stream<RepositoryResult<T>>` (никогда голый `Future<T>` — блюпринт `03 §4.1`). Сигнатуры — целевые; тела — в `tasks.md`/реализации.

---

## `AppStateRepository`

`lib/domain/repository/app/app_state_repository.dart`

```dart
abstract class AppStateRepository {
  /// Реактивный стрим app-state. Реплеит последнее разрешённое значение новым
  /// подписчикам, затем форвардит каждую последующую резолюцию.
  Stream<RepositoryResult<AppStateModel>> watchAppState();

  /// Резолвит и эмитит текущий app-state (cache-only, без сети). При
  /// [sessionExpired] == true эмитнутая unauthorized-модель несёт одноразовый
  /// признак истёкшей сессии.
  Future<RepositoryResult<AppStateModel>> fetchAppState({bool sessionExpired = false});

  /// Последний эмитнутый тип состояния, читаемый СИНХРОННО из кэша subject'а
  /// (null до первой резолюции). Для будущего auth-перехватчика (FR-017).
  AppStateType? get currentState;
}
```

**Контракт поведения**:
- `watchAppState`: lazy-resolve — если subject пуст, `fetchAppState()` вызывается при первой подписке; далее форвард навсегда.
- `fetchAppState`: cache-only; каждая ветка завершается `_subject.add(result)`; любой throw → `RepositoryResult.error` (через `BaseRepositoryHelper.execute`).
- `currentState`: `null` означает «не разрешено ещё» (≠ `unauthorized`); потребители подавляют деструктив в этом окне.
- Реализация — `@LazySingleton` (singleton обязателен: `BehaviorSubject` должен пережить каждую страницу).

**Тесты-контракта**: резолюция всех веток; `currentState == null` до первой резолюции; реплей последнего значения новому подписчику; ошибка хранилища → `unauthorized`.

---

## `SessionRepository`

`lib/domain/repository/app/session_repository.dart`

```dart
abstract class SessionRepository {
  /// Cache-only чтение сессии (identifier из secure storage + флаги из prefs).
  /// data == null ⇒ сессии нет.
  Future<RepositoryResult<SessionModel?>> readSession();

  /// Пишет identifier (secure storage) + onboardingComplete/label (prefs).
  Future<RepositoryResult<bool>> saveIdentifier({
    required String identifier,
    required bool onboardingComplete,
    String? label,
  });

  /// Помечает онбординг завершённым (+ опционально кэширует label).
  Future<RepositoryResult<bool>> setOnboardingComplete({String? label});

  /// Полный wipe: secureStorage.deleteAll() + удаление prefs-ключей.
  Future<RepositoryResult<bool>> clear();
}
```

**Контракт поведения**:
- `readSession`: пустой/отсутствующий identifier ⇒ `success(data: null)` (НЕ ошибка).
- `clear`: единственный путь полного стирания идентичности (конституция I).
- Реализация `@LazySingleton with BaseRepositoryHelper`; зависит от `FlutterSecureStorage` + `SharedPreferences` (DI-модуль `RegisterModule`).

**Тесты-контракта**: round-trip save→read; read без identifier → null; clear убирает все ключи (secure + prefs); ошибка backend хранилища → `RepositoryResult.error`.

---

## `AuthRepository`

`lib/domain/repository/app/auth_repository.dart`

```dart
abstract class AuthRepository {
  /// Стаб входа (бэкенд TBD): пишет сессию, затем re-deriv'ит app-state.
  /// registeredIds ⇒ onboardingComplete=true (→ authorized); иначе false
  /// (→ registrationPending). Клиентской валидации формата нет (FR-011).
  Future<RepositoryResult<bool>> signIn({required String identifier});

  /// Завершение first-login (Set username 2.3): onboardingComplete=true → fetchAppState.
  Future<RepositoryResult<bool>> completeOnboarding({String? label});

  /// Единственный путь выхода. Только forced передаёт sessionExpired=true.
  /// forceLogout == logout(forced: true) (программный/dev; 401-триггер — FR-017).
  Future<RepositoryResult<bool>> logout({bool forced = false});
}
```

**Контракт поведения** (паттерн «мутируй источник правды → `fetchAppState()`» — миграционный гайд §7.1):
- `signIn`: `session.saveIdentifier(...)` → `appState.fetchAppState()`.
- `completeOnboarding`: `session.setOnboardingComplete(...)` → `appState.fetchAppState()`.
- `logout`: `session.clear()` → `appState.fetchAppState(sessionExpired: forced)`. **Единственное** место, передающее `sessionExpired=true` (FR-012).
- Реализация `@LazySingleton with BaseRepositoryHelper`; зависит от `SessionRepository` + `AppStateRepository`.

**Тесты-контракта**: `signIn('registered')` → resolver даёт `authorized`; `signIn('newid')` → `registrationPending`; `completeOnboarding` → `authorized`; `logout(forced:false)` → `unauthorized`, `sessionExpired=false`; `logout(forced:true)` → `unauthorized`, `sessionExpired=true`.

---

## DI / алиасы

- Все три impl: `@LazySingleton(as: <Interface>, env: [Environment.dev, Environment.prod, Environment.test])` (env-список обязателен).
- `lib/di/register_module.dart` (`@module`): `FlutterSecureStorage get secureStorage`, `@preResolve Future<SharedPreferences> get prefs`.
- `lib/di/global_aliases.dart`: добавить `AppStateRepository get appStateRepository => getIt<AppStateRepository>();` и `AuthRepository get authRepository => getIt<AuthRepository>();` (блоки резолвят напрямую — `02 §6.4`).
