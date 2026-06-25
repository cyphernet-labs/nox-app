---
description: "Task list for 009-app-state-flow implementation"
---

# Tasks: App-state flow (spine приложения)

**Input**: Design documents from `specs/009-app-state-flow/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/)

**Tests**: Включены — проектная конвенция NOX (`make gate` гоняет тесты; unit/bloc/widget по `/bloc-test`,`/widget-test`; `mockito`-only; deep-mirror `test/` ↔ `lib/`). Goldens не затрагиваются.

**Organization**: Задачи сгруппированы по user-story для независимой имплементации/проверки.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: можно параллелить (разные файлы, нет зависимостей на незавершённые задачи)
- **[Story]**: US1/US2/US3 (для фаз user-story)
- Точные пути — в описании

## Path Conventions

Один пакет `nox_app`, слои-папки: `lib/{domain,data,di,general,presentation}`, тесты — `test/` (deep-mirror). Native — `macos/Runner/`. Команды — `make generate|analyze|test|gate`, `fvm dart format -l 140 <paths>`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: нативные/проектные предусловия secure-storage.

- [X] T001 [P] Добавить Keychain Sharing entitlement `keychain-access-groups` (с `$(AppIdentifierPrefix)nox`) в `macos/Runner/DebugProfile.entitlements` и `macos/Runner/Release.entitlements` (обязательное предусловие `flutter_secure_storage` на macOS; сейчас отсутствует)
- [X] T002 [P] Sanity: подтвердить в `pubspec.yaml` наличие `flutter_secure_storage ^10.3.1`, `shared_preferences ^2.5.5`, `rxdart 0.28.0`; прогнать `make deps`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: доменный + data + DI backbone spine. Блокирует ВСЕ user-story.

**⚠️ CRITICAL**: ни одна user-story не стартует до завершения этой фазы.

### Domain

- [X] T003 [P] Создать `enum AppStateType { init, unauthorized, registrationPending, authorized }` в `lib/domain/model/app/app_state_type.dart`
- [X] T004 [P] Создать `@freezed SessionModel { String identifier, String? label, @Default(false) bool onboardingComplete }` (только `.freezed.dart`, без JSON) в `lib/domain/model/app/session_model.dart`
- [X] T005 Создать `@freezed AppStateModel { AppStateType state, SessionModel? session, @Default(false) bool sessionExpired }` + `factory AppStateModel.init()` в `lib/domain/model/app/app_state_model.dart` (зависит T003, T004)
- [X] T006 [P] Создать контракт `SessionRepository` (`readSession`/`saveIdentifier`/`setOnboardingComplete`/`clear`, все → `RepositoryResult<…>`) в `lib/domain/repository/app/session_repository.dart` (см. `contracts/repositories.md`)
- [X] T007 Создать контракт `AppStateRepository` (`watchAppState`/`fetchAppState({sessionExpired})`/`currentState`) в `lib/domain/repository/app/app_state_repository.dart` (зависит T003, T005)
- [X] T008 [P] Создать контракт `AuthRepository` (`signIn`/`completeOnboarding`/`logout({forced})`) в `lib/domain/repository/app/auth_repository.dart`

### DI / Data

- [X] T009 Создать `@module abstract class RegisterModule` (`FlutterSecureStorage get secureStorage`, `@preResolve Future<SharedPreferences> get prefs`) в `lib/di/register_module.dart`
- [X] T010 Реализовать `SessionRepositoryImpl with BaseRepositoryHelper` (`@LazySingleton(as: SessionRepository, env:[dev,prod,test])`; identifier → secure storage `session.identifier`; `onboardingComplete`/`label` → prefs `session.onboarding_complete`/`session.label`; `clear()` = `deleteAll()` + remove prefs-keys) в `lib/data/repository/app/session_repository_impl.dart` (зависит T004, T006, T009)
- [X] T011 Реализовать `AppStateRepositoryImpl with BaseRepositoryHelper` (`@LazySingleton(as: AppStateRepository, env:[…])`; один `BehaviorSubject<RepositoryResult<AppStateModel>>` кормится императивно в `fetchAppState`, БЕЗ DAO; резолюция по `data-model.md §4`; `watchAppState` lazy-resolve-then-forward; `currentState => _subject.valueOrNull?.data?.state`; `@disposeMethod close()`) в `lib/data/repository/app/app_state_repository_impl.dart` (зависит T005, T007, T010)
- [X] T012 Реализовать `AuthRepositoryImpl with BaseRepositoryHelper` (`@LazySingleton(as: AuthRepository, env:[…])`; `signIn` → `registeredIds`-маппинг `onboardingComplete`, save + `fetchAppState()`; `completeOnboarding` → setOnboardingComplete + fetch; `logout({forced})` → `clear()` + `fetchAppState(sessionExpired: forced)`) в `lib/data/repository/app/auth_repository_impl.dart` (зависит T008, T010, T011)
- [X] T013 Добавить global-алиасы `AppStateRepository get appStateRepository => getIt<AppStateRepository>();` и `AuthRepository get authRepository => getIt<AuthRepository>();` в `lib/di/global_aliases.dart`
- [X] T014 Прогнать `make generate` (freezed: `AppStateModel`/`SessionModel`; injectable: 3 repo + `RegisterModule`) → затем `make analyze` (zero errors)

### Tests (data layer)

- [X] T015 [P] Unit-тест `SessionRepositoryImpl` (round-trip save→read; read без identifier → `null`; `clear()` стирает secure + prefs; ошибка backend → `RepositoryResult.error`; mockito-моки `FlutterSecureStorage`/`SharedPreferences`) в `test/data/repository/app/session_repository_impl_test.dart`
- [X] T016 [P] Unit-тест `AppStateRepositoryImpl` (все ветки резолюции: нет id→`unauthorized`; id+`!onboardingComplete`→`registrationPending`; id+`onboardingComplete`→`authorized`; ошибка хранилища→`unauthorized`; `currentState==null` до резолюции; реплей последнего значения новому подписчику; `fetchAppState(sessionExpired:true)` несёт флаг только на `unauthorized`) в `test/data/repository/app/app_state_repository_impl_test.dart`
- [X] T017 [P] Unit-тест `AuthRepositoryImpl` (`signIn('registered')`→`authorized`; `signIn('newid')`→`registrationPending`; `completeOnboarding`→`authorized`; `logout(forced:false)`→`unauthorized`,`sessionExpired=false`; `logout(forced:true)`→`sessionExpired=true`) в `test/data/repository/app/auth_repository_impl_test.dart`

**Checkpoint**: spine-backend готов и протестирован; presentation-фазы могут начинаться.

---

## Phase 3: User Story 1 — Cold-start приводит на правильный экран (Priority: P1) 🎯 MVP

**Goal**: при запуске приложение само резолвит сессию и после splash-анимации открывает Login / Set username / Chats; launcher не показывается; первая навигация удержана за анимацией.

**Independent Test**: при трёх предзаданных состояниях хранилища (нет id / id+`!onboardingComplete` / id+`onboardingComplete`) запуск → соответственно Login (2.1) / Set username (2.3) / Chats shell (4.1); нет мелькания целевого экрана поверх splash.

### Implementation

- [X] T018 [US1] Расширить `AppRootState` полями `@Default(AppStateModel.init()) lastAppState`/`appliedAppState`, `@Default(false) bool isReady` (+ `factory AppRootState.initial()`) в `lib/presentation/app/bloc/app_root_state.dart`
- [X] T019 [US1] Добавить события `updateAppState(RepositoryResult<AppStateModel> result)` и `applyAppState()` в `lib/presentation/app/bloc/app_root_event.dart`
- [X] T020 [US1] Расширить `AppRootBloc`: в `_onInitialize` подписка `getIt<AppStateRepository>().watchAppState().listen((r)=>add(updateAppState(r)))` (идемпотентно `_subscription ??=`); `_onUpdateAppState` (two-phase: первый — без apply, `isReady=true`; последующий — `add(applyAppState())`); `_onApplyAppState` (`appliedAppState=lastAppState` при `isReady`); `close()` отменяет подписку — в `lib/presentation/app/bloc/app_root_bloc.dart` (зависит T011, T018, T019)
- [X] T021 [US1] Прогнать `make generate` (freezed `AppRootState`/`AppRootEvent`) + `make analyze`; обновить super-конструктор bloc на `AppRootState.initial()`
- [X] T022 [US1] Переработать `SplashPage`: добавить `demo`-флаг + `routeDemo()`; real-режим — по завершении reveal-анимации `context.read<AppRootBloc>().add(applyAppState())` (ждать `isReady` через `BlocListener` на флипе); dev-outcome-бар только `if (kDebugMode && widget.demo)`; demo-режим сохраняет текущий локальный placeholder-роутинг — в `lib/presentation/pages/splash_page/splash_page.dart`
- [X] T023 [US1] Подключить spine в `AppRoot`: `home: const HomePage()` → `home: const SplashPage()`; добавить routing-`BlocListener<AppRootBloc, AppRootState>` (`listenWhen` по `appliedAppState.state`; первый переход `previous.appliedAppState.state==init` → `_navigatorKey.currentState!.pushReplacement`, иначе `pushAndRemoveUntil(route,(_)=>false)`; маппинг `unauthorized→LoginPage.route()`, `registrationPending→SetUsernamePage.route()`, `authorized→TabBarShell.route()`) — в `lib/presentation/app/app_root.dart` (зависит T020, T022)
- [X] T024 [US1] Сохранить галерею как dev-вход: добавить `kDebugMode`-only affordance (dev-row), открывающий `ScreensGalleryPage.route()`, в `lib/presentation/pages/settings_root_page/settings_root_page.dart` (чтобы `HomePage`/`ScreensGalleryPage` остались достижимы после смены `home:`)

### Tests

- [X] T025 [P] [US1] bloc-тест `AppRootBloc` (двухфазное применение: первый `updateAppState` → `isReady=true`, БЕЗ apply; `applyAppState` → `appliedAppState` обновился; последующий `updateAppState` → немедленный авто-apply) в `test/presentation/app/bloc/app_root_bloc_test.dart`
- [X] T026 [US1] widget-тест `AppRoot` cold-start (test-env DI / mockito-сессия: пусто→Login через `pushReplacement` после splash; нет навигации до завершения анимации) в `test/presentation/app/app_root_test.dart`

**Checkpoint**: cold-start-роутинг работает end-to-end — **MVP**.

---

## Phase 4: User Story 2 — Изменения сессии немедленно переключают экран (Priority: P2)

**Goal**: login/set-username/logout мутируют сессию и spine немедленно заменяет верхнеуровневый экран с обнулением стека.

**Independent Test**: из Login войти под `newid` → Set username; задать имя → Chats; logout → Login (стек обнулён, «назад» не возвращает за границу); войти под `registered` → сразу Chats.

### Implementation

- [X] T027 [US2] `LoginBloc`/`LoginPage`: real-режим (`!widget.demo`) — `signInRequested` success → `authRepository.signIn(state.id)` (persist + `fetchAppState`); убрать placeholder-пуши `navNewId`/`navRegistered` в real-режиме; ошибка → inline `errorNetwork`; demo-режим сохраняет debug-outcome-обвязку — в `lib/presentation/pages/login_page/login_page.dart` (+ `bloc/login_bloc.dart`)
- [X] T028 [US2] `SetUsernameBloc`/`SetUsernamePage`: real-режим — `navSuccess`/skip → `authRepository.completeOnboarding(label)` (→ `authorized`); demo-режим сохраняет placeholder — в `lib/presentation/pages/set_username_page/set_username_page.dart` (+ bloc)
- [X] T029 [US2] `SettingsRootPage._logout`: real-режим (`!widget.demo`) — после подтверждения `AppLogoutDialogWidget.show` → `authRepository.logout(forced: false)` (заменить `Navigator.push(SplashPage.route())`); demo-режим сохраняет текущее — в `lib/presentation/pages/settings_root_page/settings_root_page.dart`
- [X] T030 [US2] `fvm dart format -l 140 <изменённые paths>` + `make analyze`

### Tests

- [X] T031 [P] [US2] widget/flow-тест: `signIn('newid')`→Set username; `signIn('registered')`→Chats; стек обнулён (`pushAndRemoveUntil`) — в `test/presentation/app/app_root_signin_flow_test.dart` (mockito-моки repo / test-env DI)
- [X] T032 [P] [US2] widget/flow-тест logout: из `authorized` → Settings logout → Login; перезапуск-резолюция (`SessionRepository` сохранил → cold-start даёт Chats; после `clear()` → Login) — в `test/presentation/app/app_root_logout_flow_test.dart`

**Checkpoint**: US1 + US2 работают; полный transition-флоу.

---

## Phase 5: User Story 3 — Контракт принудительного выхода / sessionExpired (Priority: P3)

**Goal**: forced-logout очищает сессию и один раз показывает `Your session expired` поверх свежего Login; обычный logout — без сообщения. Триггер 401 отложен (FR-017) — закладывается путь.

**Independent Test**: программный `authRepository.logout(forced:true)` → Login + один snackbar `Your session expired`; обычный logout → без сообщения; сообщение не повторяется при последующих переходах.

### Implementation

- [X] T033 [US3] Добавить `static const String sessionExpiredMessage = 'Your session expired';` в `lib/general/text_constants.dart`
- [X] T034 [US3] Добавить в `AppRoot` второй `BlocListener<AppRootBloc, AppRootState>` для `sessionExpired` (`listenWhen`: переход *в* `unauthorized` c `appliedAppState.sessionExpired==true` и `previous != unauthorized`; `addPostFrameCallback` → `showAppSnackBar(_navigatorKey.currentContext!, text: TextConstants.sessionExpiredMessage, error: true)`) в `lib/presentation/app/app_root.dart` (зависит T023, T033)
- [X] T035 [US3] Добавить `kDebugMode`-only dev-триггер `forceLogout` (вызывает `authRepository.logout(forced: true)`) — dev-row в `lib/presentation/pages/settings_root_page/settings_root_page.dart` (программный путь; 401-перехватчик — FR-017, отложен)

### Tests

- [X] T036 [US3] widget-тест: forced-logout → snackbar `Your session expired` ровно один раз; обычный logout → snackbar не показан; повторные переходы не дублируют — в `test/presentation/app/app_root_session_expired_test.dart`

**Checkpoint**: все три user-story независимо функциональны.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: drift-fix блюпринта, security-гард, финальный гейт.

- [X] T037 [P] Drift-fix блюпринта (Принцип II/III): в `docs/blueprints/mobile/05-presentation-layer.md` + `06-theming.md` заменить `AlertDialogHelper.showErrorSnackBar` → реальный `AppFeedbackHelper.showAppSnackBar` (`lib/presentation/helpers/app_feedback_helper.dart`); обогатить `05 §6.1` двухфазным splash-gate + `registrationPending`; снять отложенный gap `auth/app-state-spine` в `docs/blueprints/mobile/README.md`
- [X] T038 [P] Security-гард (Принцип I): ревью новых repo — `identifier` НЕ попадает в логи (логируются только исключения через `BaseRepositoryHelper`); подтвердить отсутствие `logRepository`-вызовов с сырым identifier
- [X] T039 Запустить `make gate` (generate → format → analyze → test, goldens исключены) — зелёный
- [X] T040 Прогнать `quickstart.md` сценарии 1–6 (mobile + macOS `fvm flutter run -d macos`; desktop secure-storage compile-smoke через `mise run build:<platform>:stage` / dispatched `compile-check`; Windows/Linux visual — отложен)
- [X] T041 [P] Отметить в `docs/roadmap-phase2.md` пункт app-state-spine как реализованный

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: без зависимостей — старт сразу (T001, T002 — параллельно).
- **Foundational (Phase 2)**: после Setup; **блокирует все user-story**. Внутри: domain (T003–T008) → DI/data (T009–T013) → codegen (T014) → data-тесты (T015–T017).
- **US1 (Phase 3)**: после Foundational. Доставляет MVP.
- **US2 (Phase 4)**: после Foundational; технически независима от US1, но реальная навигация наблюдается через routing-listener US1 (T023). Рекомендуется после US1.
- **US3 (Phase 5)**: после US1 (T023 — routing-listener в `AppRoot`, к которому добавляется sessionExpired-listener).
- **Polish (Phase 6)**: после всех желаемых user-story.

### User Story Dependencies

- **US1 (P1)**: только Foundational. Независимо тестируема (cold-start резолюция → экран).
- **US2 (P2)**: Foundational + `AppRoot` routing-listener (T023 из US1) для наблюдаемого перехода; сами мутации (T027–T029) независимы.
- **US3 (P3)**: Foundational + T023 (общий `AppRoot`-listener-сайт) + T033 (строка).

### Within Each Story

- Domain models (T003–T005) → контракты (T006–T008) → DI/data-impl (T009–T012).
- `AppRootState`/`Event` (T018–T019) → `AppRootBloc` (T020) → codegen (T021) → `SplashPage`/`AppRoot` (T022–T023).
- Реализация → тесты (тесты в конце фазы; NOX-конвенция — не строгий TDD).

### Parallel Opportunities

- **Setup**: T001, T002 — параллельно.
- **Domain**: T003, T004, T006, T008 — параллельно (разные файлы); T005 после T003/T004; T007 после T003/T005.
- **Data-тесты**: T015, T016, T017 — параллельно.
- **US2 мутации**: T027, T028, T029 — разные экраны, параллельно (но один общий `settings_root_page.dart` у T029/T024/T035 — не параллелить между собой).
- **Polish**: T037, T038, T041 — параллельно.

---

## Parallel Example: Phase 2 (Foundational domain)

```bash
# Доменные файлы без взаимозависимостей — параллельно:
Task: "AppStateType enum in lib/domain/model/app/app_state_type.dart"          # T003
Task: "SessionModel @freezed in lib/domain/model/app/session_model.dart"        # T004
Task: "SessionRepository contract in lib/domain/repository/app/session_repository.dart"  # T006
Task: "AuthRepository contract in lib/domain/repository/app/auth_repository.dart"        # T008

# Data-тесты — параллельно (разные файлы):
Task: "Unit test SessionRepositoryImpl ..."   # T015
Task: "Unit test AppStateRepositoryImpl ..."  # T016
Task: "Unit test AuthRepositoryImpl ..."      # T017
```

---

## Implementation Strategy

### MVP First (US1)

1. Phase 1 Setup → 2. Phase 2 Foundational (backbone spine) → 3. Phase 3 US1 → **STOP & VALIDATE** cold-start-роутинг (quickstart сценарий 1) → демо.

### Incremental Delivery

1. Setup + Foundational → backbone готов (data-тесты зелёные).
2. US1 → cold-start-роутинг → демо (MVP).
3. US2 → login/set-username/logout-переходы → демо.
4. US3 → sessionExpired one-shot → демо.
5. Polish → drift-fix блюпринта + `make gate` + quickstart.

---

## Notes

- `[P]` = разные файлы, нет зависимостей. `settings_root_page.dart` трогают T024/T029/T035 — выполнять последовательно.
- `[Story]`-метка — трассировка к user-story; Setup/Foundational/Polish — без метки.
- Codegen (`make generate`) — после правки любого freezed/injectable-файла (T014 для domain+data, T021 для `AppRootState`/`Event`).
- demo-vs-real split: demo-превью не пишут в хранилище и не дёргают spine (SC-008).
- `mockito`-only; тесты против test-env DI (`Environment.test`) либо с `getIt.allowReassignment` + mock-репо.
- Коммитить после логической группы; останавливаться на checkpoint'ах для независимой проверки.
