# Contract: Навигационный spine (state → экран)

**Feature**: `009-app-state-flow` | **Phase**: 1

UI-контракт фичи: как app-state управляет верхнеуровневой навигацией и как существующие экраны реконсилируются под spine. Реализуется в `lib/presentation/app/` (`AppRoot` + `AppRootBloc`) — блюпринт `05 §6.1`.

---

## 1. Маппинг state → top-level экран

| `appliedAppState.state` | Route | Экран |
|---|---|---|
| `init` | `home: SplashPage()` | 1.1 Splash |
| `unauthorized` | `LoginPage.route()` (`/onboarding/login`) | 2.1 Login |
| `registrationPending` | `SetUsernamePage.route()` (`/onboarding/set-username`) | 2.3 Set username |
| `authorized` | `TabBarShell.route()` (`/shell`) | 4.1 Tab bar shell (Chats + Settings) |

## 2. Route-swap (в `AppRoot`, `MaterialApp(navigatorKey: _navigatorKey, home: SplashPage())`)

`BlocListener<AppRootBloc, AppRootState>` №1 — роутинг:
```text
listenWhen: previous.appliedAppState.state != current.appliedAppState.state
listener:
  route := routeForState(current.appliedAppState.state)
  if (previous.appliedAppState.state == AppStateType.init):   // первый переход со splash
      _navigatorKey.currentState!.pushReplacement(route)
  else:                                                       // любой последующий
      _navigatorKey.currentState!.pushAndRemoveUntil(route, (_) => false)
```
- Различение первого перехода по `previous == init` устраняет нужду в `NavigatorObserver` (в NOX его нет).
- `pushAndRemoveUntil(..., (_) => false)` обнуляет стек через авторизационную границу (FR-007): «назад» не возвращает на предыдущую границу.

`BlocListener` №2 — `sessionExpired` (one-shot):
```text
listenWhen: current.appliedAppState.state == AppStateType.unauthorized
            && current.appliedAppState.sessionExpired
            && previous.appliedAppState.state != AppStateType.unauthorized
listener:
  addPostFrameCallback:
    ctx := _navigatorKey.currentContext          // ниже MaterialApp → ScaffoldMessenger в scope
    showAppSnackBar(ctx, text: TextConstants.sessionExpiredMessage, error: true)
```
- Post-frame → snackbar ложится ПОСЛЕ routing-пуша на том же переходе. Срабатывает один раз (ключ — переход *в* `unauthorized` c `sessionExpired`).

## 3. Двухфазное применение (splash-gate)

```text
COLD START
  AppRoot.initState → AppRootBloc()..add(initialize())
    → subscribe watchAppState() → subject пуст → fetchAppState() (cache-only)
      → resolve (напр. unauthorized) → subject.add
    → updateAppState(hasData): isReady был false → set lastAppState, isReady=true, БЕЗ apply
  SplashPage: reveal-анимация завершилась → если isReady → add(applyAppState())
    → appliedAppState = lastAppState
  Listener №1: previous.appliedAppState == init → pushReplacement(LoginPage)

LATER (login / setUsername / logout)
  AuthRepository.<mutation> → session-write → fetchAppState() → subject.add
  updateAppState: isReady уже true → add(applyAppState()) немедленно
  Listener №1: previous != init → pushAndRemoveUntil(targetPage, (_) => false)
```

## 4. Реконсиляция существующих экранов (demo-vs-real split)

В **demo-режиме** (галерея) экраны сохраняют текущее preview-поведение и **не пишут в хранилище**. В **реальном режиме** — ведут spine.

| Экран | Real-режим (новый путь) | Demo-режим (без изменений) |
|---|---|---|
| `SplashPage` (+ `demo`/`routeDemo()`) | анимация done → `applyAppState()` (ждёт `isReady`); dev-бар скрыт | dev-outcome бар + локальный placeholder-роутинг |
| `LoginPage`/`LoginBloc` | `signInRequested` success → `authRepository.signIn(id)` → spine навигирует; placeholder-пуши (`navNewId`/`navRegistered`) убраны | debug-outcome обвязка + `RoutePlaceholderPage` |
| `SetUsernamePage`/`SetUsernameBloc` | `navSuccess`/skip → `authRepository.completeOnboarding(label)` → `authorized` | placeholder |
| `SettingsRootPage._logout` | подтверждение → `authRepository.logout(forced:false)` → spine → Login (вместо `Navigator.push(SplashPage.route())`) | текущее (Splash push) |

Сигнал-источники для замены: login `LoginStatus.navNewId/navRegistered`, set-username `UsernameStatus.navSuccess`/skip, settings `_logout`. В реальном режиме они **не пушат** маршруты — мутируют сессию и зовут `fetchAppState()`; навигацию ведёт spine.

## 5. Точка входа и галерея

- `AppRoot`: `home: const HomePage()` → `home: const SplashPage()`.
- `HomePage`/`ScreensGalleryPage`/`UiKitPage` остаются как **dev-вход** (`kDebugMode`-only affordance — напр. dev-row в Settings, открывающий `ScreensGalleryPage.route()`). Галерея self-contained (свои `route()`/`routeDemo()`), spine её не ведёт.

## 6. Новые/изменённые строки

- `TextConstants.sessionExpiredMessage = 'Your session expired'` (новая; UI-микрокопирайт EN).
- Прочие строки (`Sign in`, `Log out`, `Your ID`, …) — без изменений.

## 7. Acceptance-привязка

| Сценарий спеки | Контракт |
|---|---|
| US1 (cold-start → правильный экран, за splash) | §1–3 |
| US2 (login/setUsername/logout → немедленный переход, обнулённый стек) | §2 (pushAndRemoveUntil), §4 |
| US3 (sessionExpired one-shot) | §2 Listener №2 |
| SC-008 (preview-обвязка цела) | §4 demo-колонка, §5 |
