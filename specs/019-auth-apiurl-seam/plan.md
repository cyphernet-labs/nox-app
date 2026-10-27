# Implementation Plan: Auth token + apiUrl seam (S5)

**Branch**: `019-auth-apiurl-seam` · **Spec**: [spec.md](./spec.md) · **Date**: 2026-07-26

## Summary

Form the auth/transport seam so backend integration is localized: `AppConfig` gains a nullable `apiUrl`; `AppConfigRepository` gains `getUserAuthIdToken()` (reads `auth_id_token` from secure storage — `null` in the mock phase) + `isTestEnvironment`; `ApiClient` gains `initBase()` + an `AuthInterceptor` that attaches `Authorization: Bearer <token>` and, on a 401, calls `authRepository.logout(forced:true)` (closing the deferred 401 trigger). All inert without a real `apiUrl`; zero UI change. Shapes are example/TBD until the backend is chosen.

## Technical Context

Dart/Flutter 3.44.1, package `nox_app`, Clean Architecture, injectable+get_it, Dio (`ApiClient`), `flutter_secure_storage` (already injected via `RegisterModule`, macOS legacy-keychain options). `AuthRepository.logout(forced:)` already exists (feature 009/015) with its doc noting "401 trigger deferred" — this feature wires that trigger. The forced-logout path already drives the app-state spine → `sessionExpired` → Login; S5 adds 401 as a trigger of that same path (no new navigation).

**Design decisions (from Clarifications):**
- **Token**: `AppConfigRepositoryImpl` injects `FlutterSecureStorage`, reads key `auth_id_token` (empty/absent → `null`). No writer exists yet (TBD until real sign-in).
- **DI cycle avoidance**: `AuthInterceptor` resolves `AuthRepository` LAZILY at 401 time (via the `authRepository` top-level alias / `getIt`), not constructor injection — the interceptor never holds an `AuthRepository` reference, breaking any `ApiClient → AuthRepository → repos` cycle.
- **Inert**: `apiUrl == null` → `initBase()` sets no baseUrl; no real requests are made; the interceptor is installed but only fires if a request is actually issued (none in the UI phase). `ApiClient` stays un-injected into data sources (mocks don't use it) — TBD.
- **isTestEnvironment**: an env-keyed `RegisterModule` bool (`@test → true`, dev/prod → false), injected into `AppConfigRepositoryImpl` — genuinely true under `Environment.test`, testable.

## Constitution Check

- **I — Privacy / E2EE**: Token in `flutter_secure_storage` (secure), never logged; no real network yet; no PII. The `Authorization: Bearer` scheme is an example placeholder. PASS.
- **II — Spec-as-truth**: Spec/plan/contracts drive it; blueprint 14/15/16 TBD placeholders are the model. PASS.
- **III — Architecture blueprint**: Follows blueprint 14 (networking/auth seam) + 04 (`ApiClient`/`AppConfig`). Extends the blueprint's own TBD placeholders; the real contract replaces them at backend time. PASS.
- **IV — Design-system fidelity**: No UI. PASS (N/A).
- **V — Language discipline**: Code English, spec/plan Russian. PASS.

**Result: PASS** — a data/config-layer seam; no crypto primitives, no real transport, no UI. The token is stored securely (Constitution I upheld even for the stub).

## Project Structure (files)

```
lib/domain/model/app_config/app_config.dart              # EDIT — add nullable apiUrl
lib/domain/repository/app_config/app_config_repository.dart  # EDIT — + getUserAuthIdToken() + isTestEnvironment
lib/data/repository/app_config/app_config_repository_impl.dart  # EDIT — inject secure storage + isTest bool; read token; apiUrl null (TBD)
lib/di/register_module.dart                              # EDIT — env-keyed @Named('isTestEnvironment') bool
lib/data/remote/interceptor/auth_interceptor.dart        # NEW — Dio Interceptor: attach token + 401→forced logout
lib/data/remote/api_client.dart                          # EDIT — initBase() (baseUrl from apiUrl if set; install AuthInterceptor idempotently)
```

Tests mirror under `test/` (interceptor onRequest/onError, config token read, apiUrl null).

## Phasing

- **Phase 1 — data-model.md + contracts/**: the AppConfig/repository additions + the interceptor contract (onRequest attach, onError 401→logout).
- **Phase 2 — implement** (tasks.md): AppConfig/repo/module → AuthInterceptor → ApiClient.initBase → `make generate` → tests → `make gate`.

## Risks

- **DI cycle**: mitigated by lazy `AuthRepository` resolution in the interceptor (never constructor-injected).
- **Idempotent initBase**: calling `initBase()` twice must not double-install the interceptor — guard with a flag or check `dio.interceptors`.
- **Test 401 without a server**: tested by directly invoking `AuthInterceptor.onError` with a synthetic `DioException(response: Response(statusCode: 401))` + a mock `AuthRepository` — no real request needed.
