# App-State Flow — Migration Guide

> **Purpose.** This document is a complete, domain-neutral specification of **one
> subsystem**: the *global app-state flow* built around `AppStateRepository`
> (`lib/domain/repository/app/app_state_repository.dart`) and its consumers across
> all three layers. It is written so that **Claude Code (or any engineer) can
> reimplement the exact same mechanism in a different Flutter project** — same
> reactive contract, same navigation gating, same integration points — without
> copying any business domain.
>
> This is *not* the generic cache-first repository pattern (that lives in
> `promts/migration/04-data-layer.md`). This subsystem is deliberately different:
> it holds an **in-memory, derived** state with **no Sembast persistence** (see
> §1.1). Read this whole file before writing any code.

---

## 0. TL;DR — what you are migrating

A single source of truth for "where is the app right now" — `init → unauthorized →
selectProfileType → authorized / authorizedGuest` — exposed as a **reactive stream**
plus a **synchronous getter**, that:

1. is **recomputed on demand** (`fetchAppState`) by reading three project signals
   (token present? guest? profile selected?), never auto-polled;
2. is **pushed onto a `BehaviorSubject`** so the latest value is always replayable;
3. **drives all top-level navigation** through one app-level BLoC, with the very
   first transition **gated behind a splash animation** and every later transition
   applied **immediately**;
4. is **re-derived after every auth/profile mutation** by the code that performed
   the mutation (the call-`fetchAppState()`-afterwards contract, §7);
5. exposes `currentState` **synchronously** so an HTTP auth interceptor can decide
   whether a 401 should force a logout (only for an already-established session).

The whole subsystem is ~5 small files + a handful of one-line call sites.

### 0.1 File manifest (source → what to create in the target project)

| Layer | Source file (this repo) | Role |
|---|---|---|
| Domain | `lib/domain/model/app/app_state_type.dart` | The state enum |
| Domain | `lib/domain/model/app/app_state_model.dart` | Freezed state value object |
| Domain | `lib/domain/repository/app/app_state_repository.dart` | The interface (3 members) |
| Data | `lib/data/repository/app_state_repository_impl.dart` | `BehaviorSubject` + resolution logic |
| Presentation | `lib/presentation/app/bloc/exist_live_app_bloc.dart` (+ `_event.dart`, `_state.dart`) | App-level BLoC: stream→navigation |
| Presentation | `lib/presentation/app/exist_live_app.dart` | Root widget: `AppStateType` → `Navigator` |
| Presentation | `lib/presentation/pages/onboarding/splash_page/splash_page.dart` | Bootstrap trigger + splash gate |
| Cross-cutting | `lib/data/remote/api/base/auth_interceptor.dart` (+ `_decision.dart`) | `currentState` logout gate |
| Cross-cutting | `auth_repository_impl.dart`, `choose_role_page_bloc.dart`, `profile_page_bloc.dart`, `guest_event_draft_repository_impl.dart` | `fetchAppState()` call sites |
| Bootstrap | `lib/main.dart` | DI → config → `runApp(App)` order |

### 0.2 Naming map (rename consistently when you migrate)

| Token in this doc / source | Meaning | Suggested generic name |
|---|---|---|
| `mouse_flutter` | the Dart package name | `my_app` |
| `AppStateRepository` / `…Impl` | the subsystem interface/impl | keep |
| `AppStateModel` / `AppStateType` | state value object / enum | keep |
| `ExistLiveAppBloc` | the app-level BLoC | `AppBloc` |
| `ExistLiveApp` | the root widget | `App` |
| `UserModel` | your signed-in user/account aggregate | `UserModel` |
| `ProfileRepository.getProfile` | cache-first read of the current user | your user-cache read |
| `SharedPreferencesRepository.authToken` | where the session token lives | your token store |
| `RepositoryResult<T>` | the result wrapper (`.success`/`.error`/`hasData`) | keep (see §4) |
| `BaseRepositoryHelper.execute` | try/catch→domain-error mapper mixin | keep (see §4) |

---

## 1. The concept

`AppStateType` is a **linear-ish lifecycle enum** describing the *only* states the
top-level navigator cares about:

```
enum AppStateType { init, unauthorized, selectProfileType, authorized, authorizedGuest }
```

| State | Meaning | Top-level screen |
|---|---|---|
| `init` | not resolved yet (boot) | Splash |
| `unauthorized` | no valid session | Login |
| `selectProfileType` | authenticated, but no profile/role chosen | Choose-role |
| `authorized` | full authenticated session | Main |
| `authorizedGuest` | guest session (anonymous, limited) | Main |

`AppStateModel` wraps that enum together with the resolved user and a **one-shot
reason flag** (`sessionExpired`). `AppStateRepository` exposes it three ways
(stream / one-shot future / sync getter). One app-level BLoC subscribes to the
stream and turns each state into a `Navigator` stack replacement.

### 1.1 Why there is NO Sembast DAO here (read this — it is the key distinction)

The generic cache-first repositories in this codebase pair a `BehaviorSubject`
with a Sembast DAO so the resource survives an app restart. **`AppStateRepository`
does not.** Its `BehaviorSubject` is **purely in-memory** and is *derived* every
time from sources that *are* already persisted:

- the **token** (in `SharedPreferences`), and
- the **cached user/profile** (owned by `ProfileRepository`'s own DAO).

So app state is **never the source of truth** — it is a *projection*. On every cold
start it is recomputed from scratch (cache-only, no network — see §6.4). Do **not**
add a DAO for it; doing so would create two competing sources of truth for auth
status. This is an intentional Constitution-VII exclusion ("auth state is
stale-while-revalidate-unsafe").

### 1.2 Data-flow at a glance

```
  signals                    AppStateRepositoryImpl                 ExistLiveAppBloc        ExistLiveApp (root)
 ┌────────────┐   fetch    ┌────────────────────────┐   stream    ┌───────────────┐  state ┌──────────────────┐
 │ token?     │──────────▶ │ resolve → AppStateModel │──────────▶ │ watchAppState │──────▶ │ AppStateType →   │
 │ guest?     │            │   │                      │ (replay+   │  .listen      │        │ Navigator        │
 │ profile    │            │   ▼                      │  forward)  │   │            │        │ pushAndRemove…   │
 │  selected? │            │ BehaviorSubject<Result> ─┼────────────┘   ▼            │        │ (Login/Choose/   │
 └────────────┘            └──────────┬───────────────┘            UpdateAppState   │        │  Main/Splash)    │
        ▲                             │ valueOrNull?.data?.state    ApplyAppState ──┘        └──────────────────┘
        │ fetchAppState()             ▼  (synchronous)
   after every auth/         AuthInterceptor.currentState ── gate ──▶ forceLogout only if authorized/authorizedGuest
   profile mutation (§7)
```

---

## 2. Prerequisites in the target project

This subsystem leans on a small set of primitives. If the target project already
follows the blueprint in `promts/migration/`, you have them all. Otherwise create
these first (full templates are in `promts/migration/03/04/06`):

1. **`RepositoryResult<T>`** — `.success({data})` / `.error({exception})` / `hasData`
   / `data` / `exception`. (`lib/domain/repository/base/repository_result.dart`.)
2. **`BaseRepositoryException`** + a `RepositoryException` enum; **`BaseRepositoryHelper`**
   mixin exposing `Future<RepositoryResult<T>> execute<T>(fn)` that try/catches and
   maps framework errors to domain errors.
3. **rxdart** (`BehaviorSubject`), **injectable + get_it** (`@LazySingleton`,
   `getIt<T>()`), **freezed** (for `AppStateModel`).
4. **A user/account model** with: a way to read it **from cache only**, a **guest
   sentinel** (`UserModel.guestId`), and whatever predicate answers "has the user
   chosen a profile/role?" — in this app `user.profiles.any((p) => p.isLastUsedProfile)`.
   Replace with your own predicate; if you have no role-selection step, drop the
   `selectProfileType` branch entirely.
5. **A token store** — any read of "is there a session token?" In this app:
   `SharedPreferencesRepository` with `static const authToken = 'AUTH_TOKEN'`,
   `isKeyExist(key:)`, `read(key:)`.
6. **`LogRepository`** (single logging channel; `execute` logs through it).
7. **An app-level BLoC + root widget + splash page** entry point you control
   (`main.dart` → `runApp`).

> **Adaptation note.** Items 4–5 are this app's *specific* answers to "what state
> are we in?". The **mechanism** (recompute → push onto subject → watch) is what
> transfers; the **predicates** are yours to define. §6.3 isolates them.

---

## 3. Domain layer (verbatim templates)

### 3.1 `lib/domain/model/app/app_state_type.dart`

```dart
enum AppStateType { init, unauthorized, selectProfileType, authorized, authorizedGuest }
```

> Keep `init` (boot sentinel) and at least one `authorized*` value. `selectProfileType`
> and the guest split are optional — delete the branches you don't need everywhere
> they appear (resolution in §6, navigation in §5).

### 3.2 `lib/domain/model/app/app_state_model.dart`

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:my_app/domain/model/app/app_state_type.dart';
import 'package:my_app/domain/model/profile/user_model.dart';

part 'app_state_model.freezed.dart';

@freezed
abstract class AppStateModel with _$AppStateModel {
  const factory AppStateModel({
    required AppStateType state,
    required UserModel? user,
    // One-shot reason flag — true ONLY on the `unauthorized` model emitted by a
    // forced (session-expiry) logout. Consumed once by the app-level listener to
    // show a "session expired" message; false for every ordinary logout.
    @Default(false) bool sessionExpired,
  }) = _AppStateModel;

  factory AppStateModel.init() => AppStateModel(state: AppStateType.init, user: null);
}
```

Run codegen (`make generate` / `dart run build_runner build`) to produce
`app_state_model.freezed.dart`.

> The `user` field lets navigation/consumers read the resolved user without a second
> fetch. If your app doesn't need it at the app level, you may drop it — but it is
> cheap and frequently handy.

### 3.3 `lib/domain/repository/app/app_state_repository.dart`

```dart
import 'dart:core';

import 'package:my_app/domain/model/app/app_state_model.dart';
import 'package:my_app/domain/model/app/app_state_type.dart';
import 'package:my_app/domain/repository/base/repository_result.dart';

abstract class AppStateRepository {
  /// Reactive stream of the current app state. Replays the last resolved value
  /// to new subscribers, then forwards every subsequent resolution.
  Stream<RepositoryResult<AppStateModel>> watchAppState();

  /// Resolves and emits the current app state. When [sessionExpired] is true, the
  /// emitted (unauthorized) model carries the one-shot session-expiry reason so the
  /// app can show the "session expired" message.
  Future<RepositoryResult<AppStateModel>> fetchAppState({bool sessionExpired = false});

  /// The last emitted app-state type, read SYNCHRONOUSLY from the cached stream
  /// value (null before the first resolution). Used by the auth interceptor's
  /// suppression gate so a forced logout fires only for an already-established
  /// session (`authorized` / `authorizedGuest`).
  AppStateType? get currentState;
}
```

> These three members are the entire public contract. `watchAppState` (reactive),
> `fetchAppState` (imperative re-derive), `currentState` (synchronous peek).

---

## 4. The result/error primitives (reference)

The subsystem returns everything wrapped. These already exist in the blueprint;
shown here so the templates compile in isolation.

`RepositoryResult<T>` — `lib/domain/repository/base/repository_result.dart`:

```dart
import 'package:my_app/domain/exception/base_repository_exception.dart';

class RepositoryResult<T> {
  RepositoryResult.success({this.data}) : assert(data != null);
  RepositoryResult.error({this.exception}) : assert(exception != null);

  T? data;
  BaseRepositoryException? exception;

  bool get hasData => data != null;
}
```

`BaseRepositoryHelper` — `lib/data/exception/base_repository_helper.dart` (mixin used
by the impl; maps `DioException`/anything → domain `RepositoryException`, logs via
`logRepository`). See `promts/migration/04-data-layer.md` §4.9 for the full body.

---

## 5. Presentation layer

Three pieces: the **app-level BLoC** (stream → state with a two-phase apply), the
**root widget** (state → navigation), and the **splash page** (bootstrap trigger +
the gate that holds the first transition until the splash animation finishes).

### 5.1 The app-level BLoC — `exist_live_app_bloc.dart`

The BLoC keeps **two** copies of the state and an `isReady` flag. This is the crux:

- `lastAppState` — the most recent value off the stream (updated on **every** emission).
- `appliedAppState` — the value currently **applied to the navigator** (updated only
  when an `ApplyAppState` event fires).
- `isReady` — becomes `true` on the first emission that carries data.

```dart
import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:my_app/di/configure_dependencies.dart';
import 'package:my_app/domain/model/app/app_state_model.dart';
import 'package:my_app/domain/repository/app/app_state_repository.dart';
import 'package:my_app/domain/repository/base/repository_result.dart';

part 'exist_live_app_event.dart';
part 'exist_live_app_state.dart';

class AppBloc extends Bloc<AppEvent, AppState> {
  AppBloc() : super(AppState(lastAppState: AppStateModel.init(), appliedAppState: AppStateModel.init())) {
    on<Initialize>(_onInitialize);
    on<UpdateAppState>(_onUpdateAppState);
    on<ApplyAppState>(_onApplyAppState);
  }

  final _appStateRepository = getIt<AppStateRepository>();
  StreamSubscription? _subscriptionAppState;

  @override
  Future<void> close() {
    _subscriptionAppState?.cancel();
    _subscriptionAppState = null;
    return super.close();
  }

  // Subscribe ONCE to the reactive app state. Each emission becomes an UpdateAppState.
  FutureOr<void> _onInitialize(Initialize event, Emitter<AppState> emit) async {
    _subscriptionAppState ??= _appStateRepository.watchAppState().listen((response) {
      add(UpdateAppState(result: response));
    });
  }

  FutureOr<void> _onUpdateAppState(UpdateAppState event, Emitter<AppState> emit) async {
    if (event.result.hasData) {
      final isNeedApply = state.isReady;           // already past first boot?
      emit(state.copyWith(lastAppState: event.result.data, isReady: true));
      if (isNeedApply) {
        add(const ApplyAppState());                // later transitions apply immediately
      }
      // First emission: isReady was false → do NOT auto-apply. The splash animation
      // dispatches ApplyAppState when it finishes (see §5.3). This holds the very
      // first navigation behind the splash.
    }
  }

  FutureOr<void> _onApplyAppState(ApplyAppState event, Emitter<AppState> emit) async {
    if (state.isReady) {
      emit(state.copyWith(appliedAppState: state.lastAppState));
    }
  }
}
```

> **The two-phase apply, explained.** The *first* resolved state lands in
> `lastAppState` but is intentionally **not** applied — the splash animation owns the
> moment of application, so the user sees the splash play out and *then* lands on the
> right screen. Every *subsequent* state change (login, logout, role switch) arrives
> with `isReady == true`, so `_onUpdateAppState` immediately re-dispatches
> `ApplyAppState` and navigation reacts at once. If you don't want a splash gate,
> collapse this to one field and apply on every emission.

`exist_live_app_event.dart`:

```dart
part of 'exist_live_app_bloc.dart';

sealed class AppEvent extends Equatable {
  const AppEvent();
  @override
  List<Object> get props => [];
}

class Initialize extends AppEvent {
  const Initialize();
}

class UpdateAppState extends AppEvent {
  const UpdateAppState({required this.result});
  final RepositoryResult<AppStateModel> result;
  @override
  List<Object> get props => [result];
}

class ApplyAppState extends AppEvent {
  const ApplyAppState();
}
```

`exist_live_app_state.dart`:

```dart
part of 'exist_live_app_bloc.dart';

class AppState extends Equatable {
  const AppState({required this.lastAppState, required this.appliedAppState, this.isReady = false});

  final AppStateModel lastAppState;
  final AppStateModel appliedAppState;
  final bool isReady;

  @override
  List<Object?> get props => [isReady, lastAppState, appliedAppState];

  AppState copyWith({AppStateModel? lastAppState, AppStateModel? appliedAppState, bool? isReady}) {
    return AppState(
      lastAppState: lastAppState ?? this.lastAppState,
      appliedAppState: appliedAppState ?? this.appliedAppState,
      isReady: isReady ?? this.isReady,
    );
  }
}
```

> The original `ExistLiveAppBloc` also handles deep links (`InitializeDeepLinks`,
> `OnDeepLink`). Those are **orthogonal** to app-state and intentionally omitted
> here — add them back only if you are also migrating deep linking.

### 5.2 The root widget — `exist_live_app.dart` (navigation mapping)

A `BlocListener` keyed on `appliedAppState.state` turns each state into a top-level
`Navigator` stack replacement. Two paths: from the splash route use
`pushReplacement`; from anything else use `pushAndRemoveUntil(..., (r) => false)` so
no back-stack survives an auth boundary.

```dart
// Inside the root widget's build(), wrapping MaterialApp:
BlocListener<AppBloc, AppState>(
  listenWhen: (previous, current) =>
      previous.appliedAppState.state != current.appliedAppState.state,
  listener: (context, state) {
    final currentRoute = getIt<HistoryNavigationObserver>().currentRoute;
    final name = currentRoute?.settings.name ?? '';

    if (SplashPage.routeName == name) {
      // First navigation away from the splash: replace it.
      Widget page = SplashPage(key: _splashKey, bloc: _bloc);
      switch (state.lastAppState.state) {
        case AppStateType.unauthorized:      page = LoginPage();      break;
        case AppStateType.selectProfileType: page = ChooseRolePage(); break;
        case AppStateType.authorized:        page = MainPage();       break;
        case AppStateType.authorizedGuest:   page = MainPage();       break;
        case AppStateType.init:              page = SplashPage(key: _splashKey, bloc: _bloc); break;
      }
      _navigator.pushReplacement(PlatformAwarePageRoute(child: page));
    } else {
      // Any later auth transition: blow away the whole stack.
      Route page = SplashPage.route(bloc: _bloc);
      switch (state.lastAppState.state) {
        case AppStateType.unauthorized:      page = LoginPage.route();      break;
        case AppStateType.selectProfileType: page = ChooseRolePage.route(); break;
        case AppStateType.authorized:        page = MainPage.route();       break;
        case AppStateType.authorizedGuest:   page = MainPage.route();       break;
        case AppStateType.init:              page = SplashPage.route(key: _splashKey, bloc: _bloc); break;
      }
      _navigator.pushAndRemoveUntil(page, (route) => false);
    }
  },
),
```

Navigation mapping (the contract):

| `AppStateType` | Screen |
|---|---|
| `init` | `SplashPage` |
| `unauthorized` | `LoginPage` |
| `selectProfileType` | `ChooseRolePage` |
| `authorized` | `MainPage` |
| `authorizedGuest` | `MainPage` |

Key implementation details to preserve:

- The widget owns a `GlobalKey<NavigatorState>` (`_navigatorKey`); `_navigator`
  resolves `currentState!`. The `MaterialApp` is given `navigatorKey: _navigatorKey`
  and `home: SplashPage(...)`.
- `listenWhen` keys on **`appliedAppState`** (the gated value); the `switch` reads
  **`lastAppState`** (the freshest target). At apply time they are equal — using
  `lastAppState` just guarantees you route to the newest resolution.
- The `init → non-init` first transition can also kick off side effects (the original
  starts deep-link handling there) — optional.
- A `HistoryNavigationObserver` (registered in `MaterialApp.navigatorObservers`) is
  what lets the listener read "what route am I on?" Provide any equivalent, or track
  the current route yourself.

> **The real widget's `listenWhen` is gated — and there are more listeners.** The
> template above is the *core* contract; the production `ExistLiveApp` wires three
> app-state `BlocListener`s, and the routing one consults a **suppression gate**
> before allowing a stack replacement. These are intentionally generalized out here
> because they are feature concerns, but you must know they exist:
>
> 1. **Routing-suppression gate.** The routing `listenWhen` first calls
>    `CheckoutRoutingGuard.shouldSuppressTopLevelRouting(previous, current, route)` and
>    returns `false` (suppressing the `pushAndRemoveUntil`) when a *guest→account
>    conversion* (`authorizedGuest → authorized | selectProfileType`) happens **while
>    a checkout flow is on screen**. The lesson that transfers: **if your app has an
>    in-progress flow that owns its own navigation (a Stripe sheet, a multi-step
>    wizard), add a predicate that vetoes the top-level stack replacement while that
>    flow is active** — otherwise an app-state change mid-flow blows away the running
>    UI. Keep this gate as a pure, unit-testable function.
> 2. **Feature side-effect listeners.** A separate listener fires on the
>    `init → non-init` edge to start deep-link handling; another fires on the
>    transition *into* `authorized` to materialize a pending draft. These are
>    orthogonal app-state *consumers* (like deep linking) — add your own as needed;
>    none are required for the core flow.

#### 5.2.1 The `sessionExpired` one-shot surface

A separate `BlocListener` shows the expiry message **once**, over the freshly-pushed
login screen. It must run *after* the routing listener on the same transition — hence
the post-frame callback.

```dart
BlocListener<AppBloc, AppState>(
  listenWhen: (previous, current) =>
      current.appliedAppState.state == AppStateType.unauthorized &&
      current.appliedAppState.sessionExpired &&
      previous.appliedAppState.state != AppStateType.unauthorized,
  listener: (context, state) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigatorContext = _navigatorKey.currentContext; // below MaterialApp → has ScaffoldMessenger
      if (navigatorContext != null && navigatorContext.mounted) {
        AlertDialogHelper.showErrorSnackBar(navigatorContext, TextConstants.sessionExpiredMessage);
      }
    });
  },
),
```

> Use the **navigator's** context (below `MaterialApp`), not the widget's `context`
> (above it), so a `ScaffoldMessenger` ancestor is in scope for the snackbar.

### 5.3 The splash page — bootstrap trigger + first-transition gate

The splash does two things in order:

1. on first frame / when the splash asset is ready → `bloc.add(Initialize())`
   (this is what subscribes the BLoC to `watchAppState`, kicking off the first
   `fetchAppState`);
2. it starts its animation **only after `isReady` flips true** (i.e. the first state
   has resolved), and **partway through that animation** (in the real app, during the
   fade-out at ~0.6× of the Lottie duration — not strictly at completion) it dispatches
   `bloc.add(ApplyAppState())` — releasing the first navigation.

```dart
// 1) trigger resolution once the splash is mounted/loaded:
widget.bloc.add(const Initialize());

// 2) play the splash animation only once the first state is ready:
BlocListener<AppBloc, AppState>(
  bloc: widget.bloc,
  listenWhen: (previous, current) => previous.isReady == false && current.isReady == true,
  listener: (context, state) => _playSplashAnimation(),
  child: /* splash animation widget */,
);

// 3) when the animation finishes, apply the (already-resolved) first state:
//    widget.bloc.add(const ApplyAppState());
```

> The exact animation plumbing is yours (this app uses Lottie with status-listener
> timings). The **contract** is: `Initialize` early → wait for `isReady` →
> `ApplyAppState` at the end. A minimal version: dispatch `Initialize` in
> `initState`, and on the `isReady` listener `await` a fixed delay then dispatch
> `ApplyAppState`.

---

## 6. Data layer — `app_state_repository_impl.dart`

This is the heart. Reproduced below (one redundant always-true ternary in the
`authorized` branch is collapsed for clarity — the real source writes
`state: isAuthenticated.data == true ? AppStateType.authorized : AppStateType.unauthorized`,
which is always `authorized` inside the enclosing `if`), then dissected.

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:injectable/injectable.dart';
import 'package:my_app/data/exception/base_repository_helper.dart';
import 'package:my_app/di/global_aliases.dart';
import 'package:my_app/domain/model/app/app_state_model.dart';
import 'package:my_app/domain/model/app/app_state_type.dart';
import 'package:my_app/domain/model/profile/user_model.dart';
import 'package:my_app/domain/repository/app/app_state_repository.dart';
import 'package:my_app/domain/repository/base/repository_result.dart';
import 'package:my_app/domain/repository/general/shared_preferences_repository.dart';
import 'package:my_app/domain/repository/profile/get_profile_config.dart';
import 'package:rxdart/rxdart.dart';

@LazySingleton(as: AppStateRepository)
class AppStateRepositoryImpl with BaseRepositoryHelper implements AppStateRepository {
  final _appStateMapperStreamController = BehaviorSubject<RepositoryResult<AppStateModel>>();

  @override
  AppStateType? get currentState => _appStateMapperStreamController.valueOrNull?.data?.state;

  @override
  Future<RepositoryResult<AppStateModel>> fetchAppState({bool sessionExpired = false}) async {
    final response = await execute<AppStateModel>(() async {
      late RepositoryResult<AppStateModel> result;

      // (A) one-time platform init, idempotent
      await Firebase.initializeApp();
      // await <remote config init>();

      // (B) read the current user FROM CACHE ONLY (no network on cold start)
      final user = await profileRepository.getProfile(config: GetProfileConfig(cacheOnly: true));

      if (user.data?.id == UserModel.guestId) {
        // (C) guest session
        result = RepositoryResult.success(data: AppStateModel(state: AppStateType.authorizedGuest, user: null));
      } else {
        final isAuthenticated = await _isAuthenticated();
        if (isAuthenticated.data == true) {
          final bool isProfileSelected = user.data?.profiles.any((p) => p.isLastUsedProfile) ?? false;
          if (isProfileSelected) {
            // (D) full authorized session
            result = RepositoryResult.success(data: AppStateModel(state: AppStateType.authorized, user: user.data));
          } else {
            // (E) authenticated but no role chosen yet
            result = RepositoryResult.success(data: AppStateModel(state: AppStateType.selectProfileType, user: user.data));
          }
        } else {
          // (F) no token → unauthorized. `sessionExpired` rides ONLY this branch — a
          // forced (session-expiry) logout clears token + user cache, so it always
          // resolves here.
          result = RepositoryResult.success(
            data: AppStateModel(state: AppStateType.unauthorized, user: user.data, sessionExpired: sessionExpired),
          );
        }
      }

      _appStateMapperStreamController.add(result); // push onto the subject
      return result;
    });

    return response;
  }

  @override
  Stream<RepositoryResult<AppStateModel>> watchAppState() async* {
    // Lazy first resolution: if nothing has been resolved yet, resolve now.
    if (_appStateMapperStreamController.hasValue) {
      yield _appStateMapperStreamController.value;
    } else {
      await fetchAppState();
    }
    // Then forward every subsequent push forever.
    await for (final event in _appStateMapperStreamController.stream) {
      yield event;
    }
  }

  Future<RepositoryResult<bool>> _isAuthenticated() async {
    final response = await execute<bool>(() async {
      final isExist = await sharedPreferencesRepository.isKeyExist(key: SharedPreferencesRepository.authToken);
      if (isExist.data == true) {
        final value = await sharedPreferencesRepository.read(key: SharedPreferencesRepository.authToken);
        if (value.data != null && value.data!.isNotEmpty) {
          return RepositoryResult<bool>.success(data: true);
        }
      }
      return RepositoryResult<bool>.success(data: false);
    });
    return response;
  }
}
```

### 6.1 `fetchAppState` — the resolution algorithm

Decision order (first match wins):

1. cached user id == guest sentinel → **`authorizedGuest`**;
2. else token present →
   - profile/role chosen → **`authorized`**;
   - not chosen → **`selectProfileType`**;
3. else (no token) → **`unauthorized`** (carrying `sessionExpired`).

Every branch ends by **pushing the result onto the `BehaviorSubject`**. `execute<T>`
wraps the whole thing so any throw becomes a `RepositoryResult.error` (and is logged)
instead of crashing the stream.

### 6.2 `watchAppState` — lazy-resolve then replay-and-forward

- If the subject already has a value, `yield` it immediately (replay).
- Otherwise `await fetchAppState()` — the first subscription triggers the first
  resolution (this is why the splash dispatching `Initialize` is what boots the app).
- Then `await for` the subject stream forever, forwarding every later push.

> `BehaviorSubject` is what makes "replay the latest to a new subscriber" free. A
> plain `StreamController` would lose the value emitted before subscription.

### 6.3 `currentState` — the synchronous peek

`valueOrNull?.data?.state` returns the last resolved `AppStateType` without awaiting,
or `null` before the first resolution. The auth interceptor (§7.2) needs a *sync*
read because it runs inside Dio's error callback. **`null` is meaningful**: it is the
"not resolved yet" window and must be treated as *not established* (don't force a
logout). Don't paper over it with a default.

### 6.4 Adaptation points (what is project-specific vs. mechanism)

| Code | This app's choice | What to change |
|---|---|---|
| (A) `Firebase.initializeApp()` + remote-config init | Firebase | your platform/SDK init, or remove |
| (B) `profileRepository.getProfile(cacheOnly: true)` | cache-only user read | your "read current user from cache" |
| (C) guest check `id == UserModel.guestId` | guest sentinel | your guest concept, or delete the branch |
| (D/E) `profiles.any((p) => p.isLastUsedProfile)` | role-selection step | your predicate, or delete `selectProfileType` |
| (F) `_isAuthenticated()` via `SharedPreferences` token | token presence | your "is there a session?" check |

The **mechanism** — resolve → `subject.add(result)` → lazy `watchAppState` →
synchronous `currentState` — is invariant. Keep it exactly.

> **Cold-start guarantee (important).** Resolution is **cache-only / no network**, so
> it completes fast and synchronously-enough that the app state is `authorized`
> *before* any feature page fires its first authenticated request. The auth
> interceptor relies on this (§7.2): a real cold-start 401 then sees `authorized` and
> can act. Do not make `fetchAppState` await a network call.

### 6.5 DI registration

`@LazySingleton(as: AppStateRepository)` registers the impl as an app-wide singleton
(generated into `configure_dependencies.config.dart` by injectable). The singleton
lifetime is essential — the `BehaviorSubject` must outlive every page. Add a global
alias for ergonomic access from other repositories:

```dart
// lib/di/global_aliases.dart
final appStateRepository = getIt<AppStateRepository>();
```

BLoCs/interceptors resolve via `getIt<AppStateRepository>()` directly.

---

## 7. Cross-cutting integration (the part people forget)

The repository is inert on its own. Two contracts make it work:

### 7.1 The "call `fetchAppState()` after every auth/profile mutation" contract

`AppStateRepository` does **not** observe the token or the user cache. Any code that
changes them **must** re-derive afterward by calling `fetchAppState()`. That push is
what drives navigation. Source call sites to replicate:

| When | Call | Where (this repo) |
|---|---|---|
| after login / sign-up / social sign-in succeeds | `fetchAppState()` | `auth_repository_impl.dart` (multiple) |
| after **ordinary** logout | `fetchAppState()` | `auth_repository_impl.dart` `_performLogout(sessionExpired: false)` |
| after **forced/session-expiry** logout | `fetchAppState(sessionExpired: true)` | `auth_repository_impl.dart` `_performLogout(sessionExpired: true)` |
| after choosing a role/profile | `fetchAppState()` | `choose_role_page_bloc.dart` |
| after switching/updating profile | `fetchAppState()` | `profile_page_bloc.dart` |
| after converting a guest into a real account | `fetchAppState()` | `auth_repository_impl.dart` `createGuestAccount` |
| after activating the organizer profile to materialize a guest event draft | `fetchAppState()` | `guest_event_draft_repository_impl.dart` `materialize()` |

> Pattern: **mutate the source of truth (token / user cache) FIRST, then call
> `fetchAppState()`**. The single canonical logout path takes a `sessionExpired`
> bool and is the only place that passes `true` — so the expiry message fires
> exactly once, only on a forced logout.
>
> **Sub-lesson — if your resolution depends on a role/profile being selected, set it
> before re-deriving.** Because resolution distinguishes `authorized` from
> `selectProfileType` by "is a profile flagged as last-used?" (§6.1 D/E), a flow that
> creates a *fresh* account (e.g. `createGuestAccount`) or activates a specific
> profile (e.g. the organizer draft path) must **force-select the intended profile
> via the profile API *before* calling `fetchAppState()`** — otherwise the fresh
> account has no `isLastUsedProfile` flag and resolution lands on `selectProfileType`
> instead of `authorized`. This is the §6.4-(D/E) predicate biting back; drop it if
> your app has no role-selection step.

### 7.2 `currentState` as the forced-logout suppression gate

The authenticated Dio interceptor reads `currentState` **synchronously** on a 401 to
decide whether to force a logout. It must only do so for an **already-established**
session, never during interactive sign-in or the boot window:

```dart
// inside Dio onError:
final appState = getIt<AppStateRepository>().currentState;
// ... passed into a pure decision function:
final isEstablishedSession =
    appState == AppStateType.authorized || appState == AppStateType.authorizedGuest;
if (!isEstablishedSession) return AuthAction.passThrough; // suppress logout
```

Rationale to preserve: a 401 during sign-in (state `unauthorized`/`selectProfileType`)
or during boot (state `null`/`init`) must **not** trigger "session expired". Only a
401 against an established session does. Extract the branching into a **pure
function** (`decideAuthAction`) so it is unit-testable without Dio/Firebase — see
`auth_interceptor_decision.dart`. Resolve `AppStateRepository` *lazily* (`getIt` at
error-time, not at interceptor construction) to avoid a DI cycle, because the
repository transitively depends on the Dio client.

---

## 8. Bootstrap order — `main.dart`

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final flavor = AppFlavor.getFlavor();
  await configureDependencies(/* prod|dev env */);   // 1) DI graph (registers AppStateRepository)
  await getIt<AppConfigRepository>().initialize(...); // 2) config / observability
  runApp(const ExistLiveApp(initialRoute: SplashPage.routeName)); // 3) root widget → SplashPage
}
```

Order matters: **DI before `runApp`** (so `getIt<AppStateRepository>()` resolves), and
the **splash is the initial route** (so `Initialize → watchAppState → fetchAppState`
fires from there).

---

## 9. End-to-end sequence (cold start → login → forced logout)

```
COLD START
  main() → configureDependencies() → runApp(App) → MaterialApp(home: SplashPage)
  SplashPage ready → bloc.add(Initialize)
    → AppBloc subscribes watchAppState()
      → subject empty → fetchAppState() (cache-only)
        → reads token + cached user → resolves e.g. `unauthorized`
        → subject.add(result)
    → stream emits → UpdateAppState(hasData) → isReady was false → set lastAppState, isReady=true (NO apply yet)
  SplashPage sees isReady flip → plays animation → on end → bloc.add(ApplyAppState)
    → appliedAppState = lastAppState (`unauthorized`)
  App routing listener: appliedAppState changed from init → on Splash route → pushReplacement(LoginPage)

LOGIN succeeds
  AuthRepository writes token + user cache → calls appStateRepository.fetchAppState()
    → resolves `authorized` → subject.add
  AppBloc UpdateAppState → isReady already true → immediately add(ApplyAppState)
    → appliedAppState = `authorized`
  App routing listener: not on Splash route → pushAndRemoveUntil(MainPage, (_)=>false)

FORCED LOGOUT (interceptor sees 401 on an established session)
  interceptor reads currentState == authorized (established) → decideAuthAction → refreshAndRetry
    → forced token refresh fails (authDead), OR the retried request still returns 401
    → decideAuthAction → forceLogout   (a single first 401 never logs out directly)
  AuthRepository.forceLogout() → clears token + cache → fetchAppState(sessionExpired: true)
    → resolves `unauthorized` + sessionExpired=true → subject.add
  AppBloc → ApplyAppState → appliedAppState = unauthorized(sessionExpired)
  App: routing listener → pushAndRemoveUntil(LoginPage); sessionExpired listener →
       postFrame → showErrorSnackBar("Your session expired…")
```

---

## 10. Migration checklist (ordered, executable)

**Domain**
- [ ] `AppStateType` enum (trim states you don't need).
- [ ] `AppStateModel` freezed (`state`, `user?`, `sessionExpired=false`, `.init()`); run codegen.
- [ ] `AppStateRepository` interface (`watchAppState`, `fetchAppState`, `currentState`).

**Prereqs (skip if already present)**
- [ ] `RepositoryResult<T>`, `BaseRepositoryException`, `RepositoryException`, `BaseRepositoryHelper.execute`.
- [ ] rxdart, injectable+get_it, freezed wired.
- [ ] cache-only user read; guest sentinel; role-selected predicate; token store; `LogRepository`.

**Data**
- [ ] `AppStateRepositoryImpl` `@LazySingleton(as: AppStateRepository) with BaseRepositoryHelper`.
- [ ] In-memory `BehaviorSubject<RepositoryResult<AppStateModel>>` (NO Sembast DAO).
- [ ] `fetchAppState` resolution (adapt predicates §6.4) — every branch ends with `subject.add(result)`.
- [ ] `watchAppState` lazy-resolve-then-replay-and-forward.
- [ ] `currentState => valueOrNull?.data?.state`.
- [ ] global alias `appStateRepository`; run injectable codegen.

**Presentation**
- [ ] `AppBloc` trio with two-phase `lastAppState`/`appliedAppState` + `isReady`.
- [ ] Root widget routing `BlocListener` (splash → `pushReplacement`; else → `pushAndRemoveUntil`).
- [ ] `MaterialApp` with `navigatorKey` + a navigation observer that exposes the current route.
- [ ] `sessionExpired` one-shot snackbar listener (post-frame, navigator context).
- [ ] Splash: `Initialize` early → animate on `isReady` → `ApplyAppState` at end.

**Cross-cutting**
- [ ] Call `fetchAppState()` after every auth/profile mutation (§7.1 table).
- [ ] Single logout path with a `sessionExpired` bool; only forced logout passes `true`.
- [ ] Auth interceptor reads `currentState` synchronously; suppress logout unless established session; lazy `getIt`; pure `decideAuthAction`.

**Bootstrap**
- [ ] `main.dart`: DI → config → `runApp(App)` with splash as initial route.

---

## 11. Pitfalls & gotchas

1. **Don't add a Sembast DAO** for app state — it is derived, not stored (§1.1).
2. **Keep the impl a singleton** — a fresh instance per page would have an empty
   `BehaviorSubject` and break replay + `currentState`.
3. **`fetchAppState` must be cache-only / no network** or the cold-start interceptor
   guarantee (§6.4) breaks and you get spurious logouts.
4. **`currentState == null` ≠ unauthorized.** Treat `null` as "not resolved yet" and
   suppress destructive actions (logout) in that window.
5. **Mutate the source of truth *before* calling `fetchAppState()`**, never after, or
   resolution reads stale token/user.
6. **`sessionExpired` is one-shot** — only the forced-logout path sets it, and the
   snackbar listener keys on the transition *into* `unauthorized`, so it fires once.
7. **Snackbar needs the navigator's context** (below `MaterialApp`), and a post-frame
   callback so it lands *after* the routing push on the same transition.
8. **Resolve `AppStateRepository` lazily in the interceptor** (`getIt` at error-time)
   to avoid the DI cycle through the Dio client.
9. **Two-phase apply is deliberate** — removing it makes the first navigation race the
   splash animation. Keep `lastAppState`/`appliedAppState`/`isReady` if you keep a splash.
```
