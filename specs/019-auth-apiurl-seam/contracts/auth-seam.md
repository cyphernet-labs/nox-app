# Contract: auth/apiUrl seam (S5)

## AppConfigRepository (additions)
```dart
abstract class AppConfigRepository {
  Future<void> initialize({required AppFlavorType flavorType});
  AppConfig get config;                    // config.apiUrl : String? (TBD null)
  Future<String?> getUserAuthIdToken();    // secure 'auth_id_token'; null in mock phase
  bool get isTestEnvironment;              // true under Environment.test
}
```

## AuthInterceptor (Dio Interceptor)
```dart
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._config);           // AppConfigRepository (for the token)
  // AuthRepository resolved LAZILY at 401 (authRepository alias / getIt) — no ctor ref.

  onRequest: token = await _config.getUserAuthIdToken();
             if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
             handler.next(options);
  onError:   if (err.response?.statusCode == 401) { await authRepository.logout(forced: true); }
             handler.next(err);            // always propagate
}
```

## Invariants
- `apiUrl == null` → `initBase()` sets no baseUrl; 0 real requests; interceptor installed but idle.
- 401 reuses the EXISTING forced-logout path (spine → sessionExpired → Login); no new UI/nav.
- Non-401 errors never touch logout. Token never logged.
- Flip-to-backend: set a real apiUrl + write the token on sign-in (+ inject ApiClient into data sources); repos/DAOs/UI untouched.
