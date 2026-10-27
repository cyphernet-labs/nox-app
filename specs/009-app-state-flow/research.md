# Research: App-state flow (spine приложения)

**Feature**: `009-app-state-flow` | **Date**: 2026-06-25 | **Phase**: 0 (Outline & Research)

Источник подхода — `docs/app-state-flow-migration.md` (проверенный spine из другого приложения). Ниже — решения адаптации под NOX, сверенные с реальным кодом `lib/` и блюпринтом `docs/blueprints/mobile/`. Формат: **Decision / Rationale / Alternatives**.

---

## R1. App-level потребитель: расширить `AppRootBloc` (а не вводить второй BLoC)

- **Decision**: Spine-навигацию ведёт существующий `AppRootBloc` (`lib/presentation/app/bloc/`). В `AppRootState` добавляются поля `lastAppState`, `appliedAppState`, `isReady` рядом с `themeMode`; добавляются события `updateAppState(RepositoryResult<AppStateModel>)` и `applyAppState()`. Пустой хук `_onInitialize` (`app_root_bloc.dart:20`) подписывается на `getIt<AppStateRepository>().watchAppState()`.
- **Rationale**: Блюпринт `05 §6.1` («Опциональный auth/splash-флоу») прямо предписывает реализовать top-level навигацию как **nullable app-state-поле в `AppRootState` + событие `UpdateAppState`, питаемое подпиской на app-state-репозиторий**, со свапом корневого маршрута через `_navigatorKey`. `AppRootBloc` уже описан как «the app-level BLoC», уже провайдится в `AppRoot` и уже владеет `_navigatorKey`. Это минимизирует дрейф и новую обвязку.
- **Alternatives**: Отдельный `AppBloc` (как `ExistLiveAppBloc` в исходнике). Отклонено: в NOX `AppRootBloc` уже занимает роль app-level-блока; два app-level-блока с пересекающимися именами запутывают и дублируют провайдер/wiring. Блюпринт явно кладёт это в `AppRootState`.

## R2. Двухфазное применение (splash-gate) — сохраняем

- **Decision**: `AppRootState` несёт **две** копии состояния: `lastAppState` (обновляется на каждой эмиссии стрима) и `appliedAppState` (обновляется только по `applyAppState`), плюс `isReady`. Первая резолюция садится в `lastAppState`, но НЕ применяется; `SplashPage` диспатчит `applyAppState()` по завершении reveal-анимации. Последующие эмиссии (`isReady==true`) применяются немедленно (`updateAppState` сам ре-диспатчит `applyAppState`).
- **Rationale**: FR-006/FR-007 — первый переход удержан за splash, нет гонки/мелькания; проверенный механизм миграционного гайда (§5.1). Блюпринтовый скетч `05 §6.1` показывает одно nullable-поле — обогащаем его двухфазностью, что является оправданным расширением паттерна под требование splash-гейта (drift-fix: довести блюпринт до этой формы, см. R9).
- **Alternatives**: Одно поле + применять на каждой эмиссии. Отклонено: первая навигация будет гонять splash-анимацию (миграционный гайд, pitfall №9). Декларативный `home: pageFor(state)` — отклонён в R3.

## R3. Навигация: императивный route-swap через `BlocListener` (без NavigatorObserver)

- **Decision**: В `AppRoot` `MaterialApp(navigatorKey: _navigatorKey, home: SplashPage())` оборачивается в `BlocListener<AppRootBloc, AppRootState>`, `listenWhen` по смене `appliedAppState.state`. Первый переход (когда `previous.appliedAppState.state == AppStateType.init`) → `_navigatorKey.currentState!.pushReplacement(route)`; любой последующий → `pushAndRemoveUntil(route, (_) => false)`. Маппинг: `unauthorized→LoginPage.route()`, `registrationPending→SetUsernamePage.route()`, `authorized→TabBarShell.route()`.
- **Rationale**: Соответствует `05 §6.1`. Различение «первого перехода со splash» по `previous == init` **устраняет необходимость в `HistoryNavigationObserver`** (которого в NOX нет и который блюпринт не вводит). `pushAndRemoveUntil(...(_) => false)` обнуляет стек через авторизационную границу (FR-007), чего декларативный свап `home` не гарантирует (pushed-маршруты над `home` переживают смену `home`).
- **Alternatives**: (1) NavigatorObserver для чтения текущего маршрута (как в исходнике) — лишняя сущность, не нужна. (2) Декларативный `home: pageFor(appliedAppState)` — проще, но не сносит глубокий стек на logout (FR-007). Отклонено.

## R4. Доменный spine: `AppStateType` / `AppStateModel` / `SessionModel` + 3 контракта

- **Decision** (Freezed, только `.freezed.dart`, без JSON — блюпринт `03 §6`):
  - `enum AppStateType { init, unauthorized, registrationPending, authorized }` (без `authorizedGuest`/`selectProfileType`).
  - `AppStateModel { AppStateType state, SessionModel? session, @Default(false) bool sessionExpired }` + `factory AppStateModel.init()`.
  - `SessionModel { String identifier, String? label, @Default(false) bool onboardingComplete }`.
  - Контракты: `AppStateRepository` (`watchAppState`/`fetchAppState`/`currentState`), `SessionRepository` (cache-only чтение + мутации хранилища), `AuthRepository` (оркестрация мутация→`fetchAppState`).
- **Rationale**: NOX-адаптация исходника: `user: UserModel?` → `session: SessionModel?` (доменной `UserModel` в NOX нет). Дискриминатор `registrationPending`↔`authorized` — флаг `onboardingComplete` (clarify-решение). Контракты возвращают `RepositoryResult<T>` / `Stream<RepositoryResult<T>>` (`03 §4.1`, никогда голый `Future<T>`).
- **Alternatives**: Без `SessionModel`, резолвер читает сырые ключи; различать по наличию label. Отклонено в clarify (нет единого идентичностного объекта, «label есть, но онбординг не завершён» неразличим).

## R5. `AppStateRepositoryImpl`: in-memory `BehaviorSubject`, БЕЗ Sembast-DAO

- **Decision**: `@LazySingleton(as: AppStateRepository, env: [dev,prod,test]) with BaseRepositoryHelper`. Один `BehaviorSubject<RepositoryResult<AppStateModel>>`, кормимый **императивно** в `fetchAppState` (`_subject.add(result)`), без DAO/entity/mapper. `watchAppState` — lazy-resolve-then-replay-and-forward (`async*`: если subject пуст → `await fetchAppState()`, затем `await for` форвардит навсегда). `currentState => _subject.valueOrNull?.data?.state`. `@disposeMethod` закрывает subject. Зависит от `SessionRepository` (constructor inject).
- **Rationale**: App-state — **проекция** сигналов сессии, не источник правды (миграционный гайд §1.1; конституция I — auth-state stale-unsafe). Блюпринт `04 §8.1` даёт BehaviorSubject-репо TARGET-шаблон, но DAO-backed; для derived in-memory состояния адаптируем его, **выкинув `_initSubscription` на DAO** (кормим subject вручную). `BaseRepositoryHelper.execute` (`lib/data/exception/base_repository_helper.dart`) оборачивает резолюцию: любой throw → `RepositoryResult.error` + лог через `logRepository`.
- **Alternatives**: Sembast-DAO для app-state — отклонено (создаёт второй конкурирующий источник правды для auth-статуса; pitfall №1). Резолюция с сетевым вызовом — отклонено (cold-start должен быть cache-only/offline, иначе спурьёзные логауты; pitfall №3).
- **Note**: `BehaviorSubject` сейчас не используется нигде в `lib/` (только doc-comment в `item_repository.dart`); `rxdart 0.28.0` — прямая зависимость, уже используется в `bloc_transformers.dart`. Spine — первый реальный потребитель `BehaviorSubject` (консистентно).

## R6. `SessionRepository`: secure storage (identifier) + SharedPreferences (флаги)

- **Decision**: `@LazySingleton(as: SessionRepository, env:[dev,prod,test]) with BaseRepositoryHelper`. Зависит от `FlutterSecureStorage` + `SharedPreferences` (через injectable-модуль, см. R7). 
  - `identifier` → `flutter_secure_storage` (ключ `session.identifier`).
  - `onboardingComplete` (bool) + кэш `label` (string) → `SharedPreferences` (ключи `session.onboarding_complete`, `session.label`).
  - `readSession()` → `RepositoryResult<SessionModel?>` cache-only (null, если identifier пуст/нет).
  - `saveIdentifier({identifier, onboardingComplete, label?})`, `setOnboardingComplete({label?})`, `clear()` = `secureStorage.deleteAll()` + удаление prefs-ключей (полный wipe, FR-010 / конституция I).
- **Rationale**: clarify-решение + проектная политика хранилища (security-чувствительный identifier → secure storage; несекретные флаги → SharedPreferences). `flutter_secure_storage ^10` покрывает все 5 платформ (Keychain/KeyStore/DPAPI/libsecret — `14 §4.3`). Единый путь wipe без платформенных веток.
- **Alternatives**: Всё в SharedPreferences — отклонено (identifier — секрет). Всё в secure storage — допустимо, но избыточно для несекретных флагов; политика проекта — несекретное в SharedPreferences.

## R7. DI-модуль для `FlutterSecureStorage` + `SharedPreferences`

- **Decision**: Новый `@module abstract class RegisterModule` (`lib/di/register_module.dart`): `FlutterSecureStorage get secureStorage => const FlutterSecureStorage(...)` (+ платформенные опции) и `@preResolve Future<SharedPreferences> get prefs => SharedPreferences.getInstance()`. Регистрация попадёт в `configure_dependencies.config.dart` за один прогон `build_runner`.
- **Rationale**: `SharedPreferences.getInstance()` асинхронен → `@preResolve` + уже вызываемый в `main.dart` `getIt.allReady()`. Внешние пакеты нельзя аннотировать — стандартный injectable-паттерн. Иначе `SessionRepositoryImpl` не получит зависимости.
- **Alternatives**: Прямое создание `FlutterSecureStorage()` внутри impl без DI — отклонено (хуже тестируемость; mockito не подменит). 

## R8. Оркестрация мутаций: `AuthRepository` как единый «mutate → fetchAppState»

- **Decision**: `@LazySingleton(as: AuthRepository, env:[...]) with BaseRepositoryHelper`, зависит от `SessionRepository` + `AppStateRepository`:
  - `signIn({identifier})` (стаб): `isRegistered = OnboardingMockData.registeredIds.contains(identifier.trim())`; `session.saveIdentifier(identifier, onboardingComplete: isRegistered)`; `appState.fetchAppState()`. Клиентской валидации нет (FR-011).
  - `completeOnboarding({label?})`: `session.setOnboardingComplete(label)`; `appState.fetchAppState()`.
  - `logout({bool forced = false})`: `session.clear()`; `appState.fetchAppState(sessionExpired: forced)`. **Единственный** путь выхода; только `forced` передаёт `true` (FR-011/FR-012). `forceLogout` = `logout(forced: true)` (программный/dev; 401-триггер отложен — FR-017).
- **Rationale**: Контракт «сначала мутируй источник правды, затем `fetchAppState()`» (миграционный гайд §7.1). Централизация в `AuthRepository` = единый logout-путь (FR-012), будущий дом реального sign-in/refresh (`14 §4–5`, TBD), тестируемость. Глобальные алиасы `appStateRepository`, `authRepository` добавляются в `global_aliases.dart` (паттерн `X get x => getIt<X>();`) — блоки резолвят их напрямую (`02 §6.4`, блоки не в DI).
- **Alternatives**: Блоки вызывают `SessionRepository` + `fetchAppState` напрямую. Отклонено: размазывает logout-путь (нарушает FR-012), дублирует registered-set-логику.

## R9. Реконсиляция презентации (demo-vs-real split)

- **Decision**: Существующие экраны переключаются на spine **только в реальном режиме**; demo-режим (галерея) сохраняет текущее preview-поведение и **не пишет в хранилище** (чистота превью, FR-014/SC-008):
  - `SplashPage` — добавить `demo` + `routeDemo()`. Real: dev-бар скрыт, по завершении анимации → `applyAppState()` (если `isReady`, иначе ждать флипа `isReady`). Demo: текущий dev-outcome-бар + локальный placeholder-роутинг.
  - `LoginPage`/`LoginBloc` — real: `signInRequested` success → `authRepository.signIn(id)` (persist + fetchAppState), spine навигирует, placeholder-пуши (`navNewId`/`navRegistered`) убираются. Demo: текущая debug-outcome-обвязка.
  - `SetUsernamePage`/`SetUsernameBloc` — real: `navSuccess`/skip → `authRepository.completeOnboarding(label)` → `authorized`. Demo: placeholder.
  - `SettingsRootPage._logout` — real (не demo): после подтверждения `AppLogoutDialogWidget.show` → `authRepository.logout(forced:false)` → spine → Login (вместо `Navigator.push(SplashPage.route())`). Demo: текущее.
  - `TextConstants` — добавить `sessionExpiredMessage = 'Your session expired'` (строки сейчас нет).
  - `AppRoot` — `home: HomePage` → `home: SplashPage()`; добавить routing-`BlocListener` + sessionExpired-`BlocListener` (post-frame, `_navigatorKey.currentContext`, `showAppSnackBar(error:true)`).
  - Launcher/галерея — `HomePage`/`ScreensGalleryPage` остаются доступны как **dev-вход** (`kDebugMode`-only affordance, напр. dev-row в Settings, открывающий `ScreensGalleryPage.route()`).
- **Rationale**: SC-008 — preview-обвязка не ломается; SplashPage под реальным `AppRootBloc` нельзя оставлять с dev-роутингом (хайджекнет реальный флоу), поэтому `demo`-флаг гейтит. Все экраны уже несут `demo`-флаг (кроме Splash) — паттерн консистентен.
- **Alternatives**: Удалить галерею/preview-обвязку — отклонено пользователем (точка входа: «галерею оставить»).

## R10. Error-surfacing для `sessionExpired`

- **Decision**: Использовать **реальный** хелпер `lib/presentation/helpers/app_feedback_helper.dart` → `showAppSnackBar(context, text: TextConstants.sessionExpiredMessage, error: true)`, вызываемый из sessionExpired-`BlocListener` через `WidgetsBinding.instance.addPostFrameCallback` с `_navigatorKey.currentContext` (ниже `MaterialApp` → `ScaffoldMessenger` в scope).
- **Rationale**: `06`/`05 §8` — токенизированный канал ошибки; строка предпереводится (`TextConstants`), сырой текст не показывается (конституция I — без PII). Post-frame гарантирует, что snackbar ляжет ПОСЛЕ routing-пуша на том же переходе (миграционный гайд §5.2.1).
- **Drift-fix (Принцип II/III)**: Блюпринт `05/06` ссылается на `AlertDialogHelper.showErrorSnackBar` — в реальном коде хелпер называется `AppFeedbackHelper.showAppSnackBar` (`app_feedback_helper.dart`). Привести прозу блюпринта к реальному имени в том же change-set.

## R11. Secure-storage native setup (desktop-native gate, конституция III)

- **Decision**: Включаем secure storage на всех 5 таргетах (расширяем подсистему, а не stub'аем — удовлетворяет гейту Принципа III):
  - **macOS**: добавить `keychain-access-groups` (Keychain Sharing) в `macos/Runner/DebugProfile.entitlements` + `Release.entitlements` (сейчас отсутствует — обязательное предусловие `flutter_secure_storage` на macOS).
  - **Linux**: CI `compile-check.yml` linux-job **уже** ставит `libsecret-1-dev libjsoncpp-dev` (проверено, строка 58) — compile-smoke покрыт; рантайм требует libsecret + Secret Service (gnome-keyring) на машине (launch-deferred Windows/Linux — visual отложен, как в 008).
  - **Windows**: DPAPI/wincreds — доп. настройка не нужна. **iOS/Android**: Keychain/KeyStore — из коробки.
- **Rationale**: Конституция III — платформенно-специфичную нативную часть (secure storage) перед desktop-работой расширяем на desktop либо документируем fallback; здесь — расширяем (включаем). `14 §4.3`.
- **Risk/Gap**: macOS hardened-runtime/keychain-sharing конкретику блюпринт не описывает (`09`/`14` gap) — фиксируем как known-risk; visual-проверка secure-storage на Windows/Linux отложена (только compile-smoke).

## R12. Bootstrap и тестирование

- **Decision (bootstrap)**: `main.dart` не меняется по структуре (`configureDependencies(env)` → `getIt.allReady()` → `AppConfigRepository.initialize` → `runApp(AppRoot())`). Spine резолвится из `AppRoot.initState` (`AppRootBloc()..add(initialize())` уже там) через `watchAppState` lazy-resolve. Явный seed `fetchAppState()` до `runApp` не нужен.
- **Decision (тесты)**: unit — резолвер `AppStateRepositoryImpl.fetchAppState` (все ветки: нет id → `unauthorized`; id + `onboardingComplete=false` → `registrationPending`; id + `true` → `authorized`; ошибка хранилища → `unauthorized`/error), `SessionRepository` (save/read/clear), `AuthRepository` (signIn registered/new, logout forced/ordinary). bloc-test — `AppRootBloc` двухфазное применение (первый `updateAppState` без apply; `applyAppState` после; последующий `updateAppState` → немедленный apply). widget — `AppRoot` маппинг state→экран (`pushReplacement` первый, `pushAndRemoveUntil` далее), sessionExpired-snackbar один раз. mockito для подмены `SessionRepository`/secure-storage. Goldens не затрагиваются.
- **Rationale**: `08`/Testing-конвенции; `BaseBloc.executeLogic` без `onError` глотает — в тестах ассертить `Error` только где передан `onError`.

---

## Сводка нерешённого / отложенного (не блокирует план)

| # | Пункт | Статус |
|---|---|---|
| 1 | Реальный сетевой sign-in / refresh / token-bridge (`AppConfigRepository.getUserAuthIdToken`) | TBD — бэкенд не выбран (`14 §4–5`); стаб `AuthRepository.signIn` |
| 2 | 401-перехватчик → forced-logout триггер (`currentState`-гейт) | FR-017 — контракт заложен, триггер в бэкенд-фазе |
| 3 | macOS hardened-runtime / keychain-sharing конкретика | known-risk; блюпринтовый gap |
| 4 | Visual-проверка secure-storage на Windows/Linux | отложено (compile-smoke only), как в 008 |
| 5 | Drift-fix блюпринта: `AppFeedbackHelper` имя + двухфазный splash-gate в `05 §6.1`; снять gap `auth/app-state-spine` | в том же change-set (Принцип II/III) |

Все `NEEDS CLARIFICATION` спеки закрыты на этапе `/speckit-clarify`; новых не возникло.
