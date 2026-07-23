# Quickstart & Validation: auth/apiUrl seam (S5)

## Automated (the gate)
```bash
make generate        # injectable for the new AuthInterceptor + module bool
make gate            # generate -> format -> analyze -> test (goldens excluded)
make golden-verify   # unchanged (no UI change)
```
Targeted:
```bash
make test FILE=test/data/repository/app_config/app_config_repository_impl_test.dart  # apiUrl null + token read
make test FILE=test/data/remote/interceptor/auth_interceptor_test.dart               # attach token + 401->logout
```

## Manual (optional)
- `apiUrl == null` → the app runs exactly as before on the local Sembast DB (no requests).
- (backend phase) set a real apiUrl + write `auth_id_token` on sign-in → requests carry the bearer;
  a real 401 force-logs-out to Login.

## Success-criteria mapping
| Criterion | Validated by |
|-----------|--------------|
| SC-001 (token null / present) | app_config repo test (empty vs written secure storage) |
| SC-002 (attach vs not) | interceptor onRequest test (token vs null) |
| SC-003 (401 once, non-401 zero) | interceptor onError test (synthetic DioException 401 / 500) |
| SC-004 (inert without apiUrl) | full existing suite unchanged |
| SC-005 (no UI change) | make gate + make golden-verify green, no golden delta |
| SC-006 (localized flip) | contracts/auth-seam.md |

## Rollback
Reverting the branch restores the bare ApiClient. No persisted change, no user-facing effect.
