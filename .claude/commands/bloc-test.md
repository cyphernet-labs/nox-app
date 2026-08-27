Generate or update BLoC unit tests for a `nox_app` Freezed-BLoC.

> **Scope:** the single Dart package `nox_app` (layers-as-folders per `docs/blueprints/mobile/`). Run every command from the
> repo root via the **`fvm` CLI** (`fvm flutter` / `fvm dart`; SDK pinned in `.fvmrc`).

## Input

$ARGUMENTS

The first argument is the path to the BLoC file (e.g. `lib/presentation/pages/chats_list_page/bloc/chats_list_bloc.dart`).
Any additional text describes specific events to focus on, scenarios to cover, or criteria. If none, generate tests for all
event handlers.

## Instructions

1. **Read the target BLoC and all its dependencies:**
   - The BLoC file (`*_bloc.dart` — extends `BaseBloc<Event, State>` from `lib/presentation/base/base_bloc.dart`).
   - Its event/state, Freezed `part of` the bloc file (`*_event.dart` / `*_state.dart`, `@freezed sealed`). Substates are **bare**:
     `Initializing` / `Initialized` / `Error` (const-factory redirects, e.g. `const factory ChatsListState.initialized({...}) = Initialized;`).
     Event variants are bare too (`Initialize`, `LoadChats`, `SearchChanged`). **Read `*_state.dart`/`*_event.dart` to confirm the exact bare names**
     — nox-app does NOT page-prefix them (page-prefixing is only a collision fallback per CLAUDE.md, and is not used here; `Error`
     intentionally shadows `dart:core.Error`).
   - How the BLoC obtains its dependencies. Repositories are resolved via `getIt<XxxRepository>()` (service-location), not
     constructor injection — note every `getIt<...>()` call. Product repositories (chat / message) are **cache-first over a real
     Sembast `AppDatabase`** seeded from mock sources, and several expose reactive `watch*` streams the BLoC subscribes to, so the
     test must reset the DB per test (see Rules). Only the unmounted verification `Item` slice is network-only.
   - Domain models referenced by events/state (`lib/domain/model/...`).
   - Whether handlers wrap work in `BaseBloc.executeLogic(logic, onError:)`. **Without an `onError`, a thrown error is swallowed
     by design** (no emit, no rethrow) — so only assert an `Error`-state emission when the handler passes `onError`.
   - Only if present: a one-shot side-effect exposed as a **public `Stream` getter** backed by a private `rxdart` subject. **No BLoC
     in the repo currently exposes one** — do not invent `navigateToDetails`/`EffectsMixin`/`bloc.effects` (they don't exist here).
     Note the reverse is common: several BLoCs *consume* repository streams (`watchChats`/`watchMessages`/`watchOnline`) through a
     `StreamSubscription` field, which is what makes the per-test DB reset necessary.

2. **Place the test mirroring the lib/ path under `test/`** (nox-app convention — deep-mirror the source tree, NOT flat; the
   `bloc/` folder is part of the mirrored path): `test/presentation/pages/<page>/bloc/<bloc_name>_test.dart` (alongside the live
   `test/presentation/pages/chats_list_page/bloc/chats_list_bloc_test.dart`); data tests in `test/data/<...>/<name>_test.dart`
   (e.g. `test/data/mapper/item/item_mapper_test.dart`). If a test file already exists:
   - Read it; list which events have coverage and which are untested or have drifted.
   - Propose each add/update before applying; never silently remove or overwrite hand-written tests.

   If none exists, create one.

3. **Review the BLoC implementation for issues** (always runs before writing tests). Check every handler for:
   - **Missing error handling:** `executeLogic()` for fallible async work (repo calls) that omits `onError` (so an `Error` state is
     never emitted) where it should surface one.
   - **Missing state guards:** reading `Initialized` fields without first narrowing the sealed union (pattern match or
     `if (state is! Initialized) return;`).
   - **`RepositoryResult` handling:** unguarded `result.data!` outside an `if (result.hasData)` / `match()` guard is forbidden
     (blueprint golden rule); error branch must surface the error (state `exception` field / `pagingState.error`).
   - **Pagination:** list folding must go through `PagingStateExt.applyPage`; page numbers via `GetItemsConfig.defaultPage` /
     config helpers, not magic numbers.
   - **Logic bugs:** wrong `copyWith` fields, missing `emit()`, incorrect substate transitions.

   Present findings as a numbered list (handler, issue, fix snippet). Apply accepted fixes before writing tests.

4. **Generate or update the test file:** one `group` per event type plus an "Initial state" group; per event a success path, an
   error path (only if the handler passes `onError`), and edge cases. Read the live
   `test/presentation/pages/chats_list_page/bloc/chats_list_bloc_test.dart` (DB-backed + reactive) and
   `test/presentation/pages/create_chat_page/bloc/create_chat_bloc_test.dart` (mockito error path) for the repo's DI/assertion
   style first.

## Test file conventions

The **primary** pattern — run the BLoC against the test-env DI (mock sources over the real Sembast DB), no mocks. Reset the DB per
test so a BLoC that writes (create chat, send message) cannot leak into the next one:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/presentation/pages/chats_list_page/bloc/chats_list_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Per-test isolation — the reactive tests mutate the DB, so each test starts from a
  // clean, freshly-seeded store.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase();
  });

  tearDown(() async => getIt.reset());

  group('ChatsListBloc', () {
    group('Initial state', () {
      test('initial state is Initializing', () {
        final bloc = ChatsListBloc();
        addTearDown(bloc.close);
        expect(bloc.state, isA<Initializing>()); // bare substate name — see chats_list_state.dart
      });
    });

    group('Initialize', () {
      blocTest<ChatsListBloc, ChatsListState>(
        'Initialize -> Initialized, then a page of mock chats loads',
        build: ChatsListBloc.new,
        act: (bloc) => bloc.add(const ChatsListEvent.initialize()),
        wait: const Duration(milliseconds: 500),
        verify: (bloc) {
          final state = bloc.state;
          expect(state, isA<Initialized>());
          expect((state as Initialized).items, isNotEmpty);
          expect(state.loadingInProgress, isFalse);
        },
      );
    });
  });
}
```

The **error-path** pattern — force a repository error with **mockito** (the test-env mock source returns data, so an error
must be injected). Reset DI, allow reassignment, register the mock:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/presentation/pages/create_chat_page/bloc/create_chat_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'create_chat_bloc_test.mocks.dart'; // generated by `make generate` — gitignored, never committed

@GenerateMocks([ChatRepository])
void main() {
  late MockChatRepository mockChatRepository;

  setUpAll(() {
    // REQUIRED for every non-nullable generic the mock returns — without it an
    // unstubbed call throws instead of yielding a benign default.
    provideDummy<RepositoryResult<ChatModel>>(const RepositoryResult<ChatModel>.error(exception: RepositoryException.unknown));
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase();
    getIt.allowReassignment = true;
    mockChatRepository = MockChatRepository();
    getIt.registerSingleton<ChatRepository>(mockChatRepository);
  });
  tearDown(() async => getIt.reset());

  blocTest<CreateChatBloc, CreateChatState>(
    'emits the error status when the repository create fails (handler must pass onError)',
    build: () {
      when(mockChatRepository.createChat(name: anyNamed('name'))).thenAnswer(
        (_) async => const RepositoryResult<ChatModel>.error(exception: RepositoryException.unknown),
      );
      return CreateChatBloc();
    },
    act: (bloc) => bloc.add(const CreateChatEvent.createRequested()),
    wait: const Duration(milliseconds: 500),
    expect: () => [/* mirror the handler's REAL emission sequence — read the bloc first */],
  );
}
```

## Rules

- **DI via `configureDependencies(Environment.test)` + `getIt.reset()`** — always wired explicitly by the test.
  `test/flutter_test_config.dart` IS auto-loaded by `flutter test`, but it only installs in-memory `SharedPreferences` /
  `FlutterSecureStorage` mock backends so the DI graph can resolve; it does **not** build the container. `setUpAll`/`tearDownAll`
  suffices for a read-only BLoC; use `setUp`/`tearDown` plus `SharedPreferences.setMockInitialValues({})` and
  `await getIt<AppDatabase>().clearEntireDatabase()` for any BLoC touching the Sembast-backed chat/message repositories, or when a
  test needs a fresh mock override.
- **Prefer the test-env DI (no mocks)** for success/happy-path coverage (it serves the deterministic mock data set). Use **mockito**
  only to control a specific repository (e.g. force an error path): `@GenerateMocks([XxxRepository])` → `import '<test>.mocks.dart'`
  (generated by `make generate`, gitignored), then `getIt.allowReassignment = true` + `getIt.registerSingleton<XxxRepository>(mock)`
  after `configureDependencies`. Add `provideDummy<RepositoryResult<T>>(...)` in `setUpAll` for every non-nullable generic the mock
  returns — without it an unstubbed call throws instead of returning a benign default. A **hand-written fake implementing the domain
  interface** is the equally accepted alternative for services and streams (`_FakeConnectivity` in the chats/thread bloc tests;
  `FakeSessionRepository` + `registerFakeSession()` in `test/utils/fake_session_repository.dart`). No mocktail / `registerFallbackValue`.
- **Substates are bare — mirror the target's `*_state.dart`.** Assert `isA<Initialized>().having((s) => s.field, 'field', value)` /
  `isA<Error>()` / `isA<Initializing>()`. Do NOT use page-prefixed names (`ItemListInitialized`) — nox-app uses bare names. Dispatch
  events via factories (`ItemListEvent.loadItems()`).
- **`RepositoryException`** lives in `lib/domain/exception/repository_exception.dart` (an enum implementing `BaseRepositoryException`);
  the `Error` substate carries `exception`. **Read that file for the exact values** and build errors as
  `RepositoryResult.error(exception: <value>)`.
- **Naming — descriptive sentences** (match `test/presentation/pages/chats_list_page/bloc/chats_list_bloc_test.dart`). Do NOT use a
  `test_should{X}_when{Y}` prefix.
- **No `@Tags`** on BLoC tests (the `golden` tag is for golden tests only).
- **Group structure:** top-level group = BLoC class name; "Initial state" first (plain `test()` + `addTearDown(bloc.close)`), then a
  group per event type, then "Error handling" / "Edge cases" if needed; sub-groups per mode if a ctor param changes behavior.
- **Side-effects** (only if the target BLoC has them): public `Stream` getter backed by a private subject — `expectLater(bloc.<getter>, emits(...))`
  set up in `build:` **before** `act` (the subject is hot, no replay). No BLoC has one today — skip this otherwise.
- **`seed:`** for a specific starting state; **`skip: N`** when `build` dispatches prerequisites; **`wait:`** for async loads /
  debounced events (the live test uses `wait: const Duration(milliseconds: 500)`).
- **Pagination:** test the pure `PagingStateExt.applyPage` fold in its own unit test (`test/presentation/pagination/...`); see
  `docs/blueprints/mobile/07-pagination.md`.
- **Style:** line length **140**, single quotes, `const` wherever possible. **Cleanup:** close the BLoC (`addTearDown(bloc.close)`).

5. **Generate mocks (if any), then run:**
   ```bash
   make generate                                  # build_runner: *.mocks.dart + *.freezed.dart (only if the test uses mocks)
   fvm flutter test <test_file_path>              # or: make test FILE=<test_file_path>
   ```
   If tests fail, investigate and fix; re-run until green.

6. **Format the file you created/changed, with explicit paths** (line length 140):
   ```bash
   fvm dart format -l 140 <test_file_path>
   ```
   Never whole-repo format as a completion step.
