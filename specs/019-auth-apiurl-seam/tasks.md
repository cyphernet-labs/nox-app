---
description: "Task list for 019-auth-apiurl-seam"
---

# Tasks: Auth token + apiUrl seam (S5)

**Input**: design docs in `specs/019-auth-apiurl-seam/`
**Tests**: INCLUDED (config token read, interceptor onRequest/onError, apiUrl-null inert).
**Organization**: US1 (config apiUrl + token), US2 (interceptor attaches token), US3 (401→logout).

## Path Conventions

Single package `nox_app`: `lib/`, tests deep-mirror under `test/`.

---

## Phase 1: Setup

- [X] T001 Confirm baseline green on `019-auth-apiurl-seam`: `make gate` + `make golden-verify`.

---

## Phase 2: US1 — AppConfig.apiUrl + token contract (Priority: P1)

- [X] T002 [US1] Edit `lib/domain/model/app_config/app_config.dart`: add `final String? apiUrl;` (nullable TBD); constructor `AppConfig({required this.flavor, this.apiUrl})`.
- [X] T003 [US1] Edit `lib/domain/repository/app_config/app_config_repository.dart`: add `Future<String?> getUserAuthIdToken();` + `bool get isTestEnvironment;` (doc as TBD/example).
- [X] T004 [US1] Edit `lib/di/register_module.dart`: add env-keyed `@Named('isTestEnvironment')` bool — `@test` getter → `true`; a dev/prod getter → `false`.
- [X] T005 [US1] Edit `lib/data/repository/app_config/app_config_repository_impl.dart`: inject `FlutterSecureStorage` + `@Named('isTestEnvironment') bool`; `initialize` sets `AppConfig(flavor, apiUrl: null)` (TBD); `getUserAuthIdToken()` reads key `auth_id_token` (empty/absent → null); `isTestEnvironment` returns the injected bool.
- [X] T006 [US1] Run `make generate` — DI for the module bool + the impl's new deps.
- [X] T007 [P] [US1] Test `test/data/repository/app_config/app_config_repository_impl_test.dart`: after `initialize`, `config.apiUrl` is null (TBD); `getUserAuthIdToken()` → null with empty secure storage and → the written value after `FlutterSecureStorage.setMockInitialValues({'auth_id_token':'tok'})`; `isTestEnvironment` is true under `Environment.test`.

**Checkpoint**: config carries apiUrl + reads the token.

---

## Phase 3: US2 — ApiClient auth-interceptor attaches the token (Priority: P1)

- [X] T008 [US2] Add `lib/data/remote/interceptor/auth_interceptor.dart`: `AuthInterceptor extends Interceptor` — ctor takes `AppConfigRepository`; `onRequest` attaches `Authorization: Bearer <token>` when `getUserAuthIdToken()` is non-empty, else leaves headers; always `handler.next(options)`. (401 handling in US3.)
- [X] T009 [US2] Edit `lib/data/remote/api_client.dart`: add `void initBase()` — if `config.apiUrl` non-empty set `dio.options.baseUrl`; install `AuthInterceptor` **idempotently** (skip if an `AuthInterceptor` is already in `dio.interceptors`). Inject `AppConfigRepository`. Keep `ApiClient` a `@lazySingleton` (not injected into data sources — TBD).
- [X] T010 [P] [US2] Test `test/data/remote/interceptor/auth_interceptor_test.dart` (part 1): with a fake/mock `AppConfigRepository` returning a token, `onRequest` sets the `Authorization` header; returning null → no header. Assert via a `RequestOptions` + a capturing `RequestInterceptorHandler` (or `resolve`/`next` spy).

**Checkpoint**: token attaches when present.

---

## Phase 4: US3 — 401 → forced logout (Priority: P1)

- [X] T011 [US3] Extend `lib/data/remote/interceptor/auth_interceptor.dart`: `onError` — if `err.response?.statusCode == 401` resolve `AuthRepository` lazily (`authRepository` alias) and `await logout(forced: true)`; always `handler.next(err)`. Never hold an `AuthRepository` ctor ref (DI-cycle safe).
- [X] T012 [P] [US3] Test `test/data/remote/interceptor/auth_interceptor_test.dart` (part 2): a synthetic `DioException(response: Response(statusCode: 401))` → `AuthRepository.logout(forced:true)` called once (mockito, registered via getIt.allowReassignment); a 500 (and a null-response `DioException`) → logout NOT called. Error always propagated.

**Checkpoint**: 401 force-logs-out; non-401 does not.

---

## Phase 5: Polish & Cross-cutting

- [X] T013 Behavior preservation (SC-004): full existing suite passes unchanged (apiUrl null → inert; nothing injects ApiClient).
- [X] T014 [P] Drift-fix (Principle II): update `docs/mock-completion-plan.md` §5.2/§5.3 (auth/apiUrl seam now present: `AppConfig.apiUrl` + `getUserAuthIdToken` + interceptor + 401→logout wired; token in secure storage; still TBD values) + `docs/blueprints/mobile/14`/`15` note if they claim the 401 trigger is deferred. Resolve the `AuthRepository` "401 trigger deferred" doc-comment.
- [X] T015 Gate: `make gate` + `make golden-verify` green (no golden delta). Walk `quickstart.md`.

---

## Dependencies & Order

- Setup → US1 (T002–T007) → US2 (T008–T010) → US3 (T011–T012) → Polish.
- `make generate` runs once (T006); a second run only if T008/T009 add annotations (AuthInterceptor is a plain class unless `@injectable`).

## Notes

- `AuthInterceptor` may be a plain (non-DI) class instantiated by `ApiClient.initBase()` with the injected `AppConfigRepository`, or `@injectable`; prefer plain to keep it out of the graph and lazy-resolve `AuthRepository`.
- Local only; never pushed. After all: multi-agent review → fix findings → merge `019-auth-apiurl-seam` → `develop` (`--no-ff`).
