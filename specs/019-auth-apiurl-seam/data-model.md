# Data Model: Auth token + apiUrl seam (S5)

No persisted domain data beyond the secure-storage token key. The "model" is the config
additions + the interceptor contract.

## AppConfig (domain model) — EDIT
| Field | Type | Note |
|-------|------|------|
| `flavor` | `AppFlavorType` | existing |
| `apiUrl` | `String?` | NEW — nullable TBD placeholder (null → no real requests) |

## AppConfigRepository (domain interface) — EDIT
| Member | Signature | Note |
|--------|-----------|------|
| `getUserAuthIdToken` | `Future<String?>` | reads `auth_id_token` from secure storage; null if empty/absent |
| `isTestEnvironment` | `bool get` | env-keyed (true under Environment.test) |

## Secure storage
| Key | Value | Note |
|-----|-------|------|
| `auth_id_token` | the bearer token | NO writer yet (TBD until real sign-in); read-only plumbing |

## AuthInterceptor (new, `lib/data/remote/interceptor/`)
| Hook | Behavior |
|------|----------|
| `onRequest` | if `getUserAuthIdToken()` returns a non-empty token → set `options.headers['Authorization'] = 'Bearer $token'`; else leave headers untouched; `handler.next(options)` |
| `onError` | if `err.response?.statusCode == 401` → resolve `AuthRepository` lazily → `logout(forced:true)` (once) → then `handler.next(err)`; else `handler.next(err)` unchanged |

## ApiClient — EDIT
- `initBase()`: if `apiUrl` is non-empty → `dio.options.baseUrl = apiUrl`; install `AuthInterceptor` **idempotently** (skip if already present). Inert when `apiUrl == null`.
