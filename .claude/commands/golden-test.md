Generate a golden (snapshot) test for a `nox_app` page/widget.

> **Scope:** the single Dart package `nox_app` (layers-as-folders per `docs/blueprints/mobile/`). Run every command from the repo root. Flutter/Dart go through the **`fvm` CLI** (`fvm flutter` / `fvm dart`, SDK pinned in `.fvmrc` = 3.44.1) — never a hardcoded SDK path.
>
> **⚠ Golden harness — local-only, NOT in CI (read first).** This project deliberately keeps goldens **simple and local**:
> - **Plain Flutter goldens** (`matchesGoldenFile`) — **no `alchemist`, no Docker, no Linux/amd64 image, no CI golden job.** (The migrated source project used a pinned Docker image for byte-stable cross-host goldens; we explicitly do **not**.)
> - Baselines are **rendered and verified only on the developer's machine (Apple Silicon / macOS)**. They are a **local regression aid**, not a cross-platform gate. A teammate on another OS may see font/AA diffs — that is the accepted trade-off here (goldens are generated + checked solely on the owner's M1).
> - Golden tests are **excluded from CI**: they carry `@Tags(['golden'])`; `.github/workflows/ci.yml` runs `flutter test --exclude-tags golden`, and `make test` does the same. They run **only** via `make golden-update` / `make golden-verify` (which pass `--tags golden`). `dart_test.yaml` declares the `golden` tag.
> - Baseline `goldens/*.png` are **committable fixtures** — not gitignored. The ignored generated set is `*.g.dart`/`*.freezed.dart`/`*.config.dart`/`*.mocks.dart` + `lib/design/gen/` + the gen-l10n output `lib/l10n/app_localizations*.dart`, plus the golden-diff `**/failures/` dirs.
> - **Determinism:** pump under `ScreenUtilInit(designSize: Constants.designSize)` (360×779) and pin the surface to that size, so the ScreenUtil scale is a deterministic 1:1 and design tokens render at design values. `AppSpacingTokens.sN` / `AppTextStyleTokens` read `ScreenUtil()` **live** on each access (no static cache), so they resolve correctly once `ScreenUtilInit` has run and the surface is fixed.
>
> **Three golden categories (project rule).** Goldens split into THREE kinds — the existing approach stays, the third is added:
> 1. **Widget** goldens — per `App*Widget` (a small piece OR a whole-page chunk of functionality), via `goldenTest`. Kept as-is.
> 2. **Page — mobile** — every `*Page` on the 360 design surface, via `goldenTest`. Kept as-is.
> 3. **Page — desktop** — every **product** `*Page` on a wide window (`kDesktopGoldenSize`, 1280×800), via `goldenTestDesktop`. **New, and required for every product page**: it locks the desktop `_wide` / master-detail / window-titlebar branch, which the mobile surface cannot exercise (this is how a desktop layout that renders crooked on a real computer gets caught). Exempt from the desktop variant: dev-only pages (the UI-kit / screens-gallery / launcher), and the brand-fixed **splash** (identical on mobile and desktop by design). So a product page owns a **pair**: `goldens/<page>_<mode>.png` (mobile) **and** `goldens/<page>_desktop_<mode>.png` (desktop).

## Input

$ARGUMENTS

The first argument is the path to the widget file (e.g. `lib/presentation/pages/chats_list_page/chats_list_page.dart`).
Any additional text describes specific visual scenarios to capture. If none are specified, generate reasonable defaults
based on the widget's visual states (and both `light`/`dark` themes — the app ships both via `AppTheme.light()`/`dark()`).

## Instructions

1. **Read the target widget and its dependencies** (same as `/widget-test`): the widget, its BLoC trio if any
   (`bloc/*_bloc.dart` + Freezed `*_event.dart`/`*_state.dart`, **bare** substates `Initializing`/`Initialized`/`Error`),
   the test-env DI it relies on (`configureDependencies(Environment.test)`), domain models, and the strings it renders
   (`context.l10n.*`, generated from `lib/l10n/app_en.arb` / `app_uk.arb`; `pumpApp` pins `Locale('en')`, so goldens always capture
   the English bundle).

2. **Identify visual states worth capturing:**
   - Light theme and dark theme (both ship via `AppTheme.light()`/`dark()` + `ThemeExtension<AppColors>`).
   - Default/empty, populated, and error states if they meaningfully change the UI. Product pages expose a `@visibleForTesting`
     scenario seam for exactly this — e.g. `ChatsListPage(initialScenario: ChatsListScenario.empty | .offline | .inlineError |
     .fatal)` seeds the state on init, so each variant gets its own `goldenTest('<page>_<scenario>', …)` without driving the UI.
   - Distinct modes (create/edit, tabs) if present.
   - If scenarios are provided in the arguments, use those.

3. **Use the `goldenTest()` helper** in `test/utils/golden.dart` — `goldenTest(name, build, {settle})`. It does everything:
   loads real fonts (`loadNoxFonts`, so glyphs aren't the `flutter_test` placeholder box-font), freezes `AppClock` at
   `kGoldenClock` (so relative-time copy like `Yesterday` is stable day-to-day) with a matching reset, pins the surface to
   `Constants.designSize` by sizing `tester.view` directly at dpr 3 (`setSurfaceSize` would NOT reach the MediaQuery ScreenUtil
   reads), precaches the brand logo on settled screens, and renders **both** light and dark (`goldens/<name>_light.png` +
   `_dark.png`) via `pumpApp` — which additionally wraps the build thunk in a `Scaffold(body: …)` and pins `Locale('en')`. You
   supply only `name` and a `build` thunk. Pass `settle: false` for animated content (spinners/progress, or any page that renders
   one) — otherwise the internal `pumpAndSettle` hangs on the endless animation. Pure widgets need no DI; a page that needs a BLoC
   usually wraps it inline (`BlocProvider<AppRootBloc>(create: (_) => AppRootBloc(), child: ...)`) — only a page whose BLoC
   self-creates from `getIt` needs the test-env DI (see Rules).

   For a **product page**, ALSO call **`goldenTestDesktop(name, build, {settle, size})`** (same file) with the *same* `name` and
   `build` thunk. It is the identical harness pinned to `kDesktopGoldenSize` (1280×800, dpr 2) instead of the mobile surface, so the
   page selects its `_wide` branch; it writes `goldens/<name>_desktop_light.png` + `_dark.png`. ScreenUtil resolves spacing/fonts
   through the production clamps at that surface (spacing → 1.2 ceiling, fonts → 1.0 ceiling — see `AppTextStyleTokens.fontSizeResolver`),
   so the baseline is the true desktop rendering, not an up-scaled phone. One wide-surface size is platform-agnostic (the five desktop
   targets share one Flutter wide layout).

4. **Generate the golden test file mirroring the lib/ path under `test/`** (nox-app convention — tests deep-mirror the source
   tree, NOT flat): `test/presentation/pages/<page>/<widget_name>_golden_test.dart` — e.g.
   `lib/presentation/pages/chats_list_page/chats_list_page.dart` → `test/presentation/pages/chats_list_page/chats_list_page_golden_test.dart`
   (consistent with the live `test/presentation/pages/settings_root_page/settings_root_page_golden_test.dart`).

## Test file conventions

**Plain widget** — one `goldenTest()` call covers light + dark:

```dart
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/chat/app_chat_item_widget.dart';

import '../../../utils/golden.dart'; // adjust relative depth to the test's location

void main() {
  goldenTest(
    'app_chat_item_widget',
    () => const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AppChatItemWidget(name: 'Cyphernet Labs', preview: 'Latest build is green', time: '09:24'),
        AppChatItemWidget(name: 'Ann Lee', preview: 'See you tomorrow', time: '08:10', unread: 5),
      ],
    ),
  );
}
```

**Animated content** — `settle: false` captures the first frame (otherwise `pumpAndSettle` hangs):

```dart
goldenTest('app_spinner_widget', () => const Center(child: AppSpinnerWidget(size: 32)), settle: false);
```

**Page needing a BLoC** — provide it inline (no `getIt` for `AppRootBloc`):

```dart
goldenTest('ui_kit_page', () => BlocProvider<AppRootBloc>(create: (_) => AppRootBloc(), child: const UiKitPage()), settle: false);
```

**Product page = a mobile + desktop pair** — same `name` and `build`, two surfaces (`goldenTestDesktop` adds the `_wide` baseline):

```dart
void main() {
  goldenTest('login_page', () => const LoginPage());
  goldenTestDesktop('login_page', () => const LoginPage());
}
```

## Rules

- **Tag** `@Tags(['golden'])` at the very top (before imports, with `library;`) — this is what keeps goldens out of CI / `make test`.
- **Always go through `goldenTest()`** (`test/utils/golden.dart`) — do **not** hand-roll `setSurfaceSize`/`matchesGoldenFile`/a
  light-dark loop. The helper encapsulates the deterministic canvas (`ScreenUtilInit(Constants.designSize)` 360×779 + `AppTheme`
  via `pumpApp`), the real-font load (`loadNoxFonts`), the light+dark pair, and
  `expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/<name>_<mode>.png'))`. ScreenUtil at a fixed 1:1 surface is why
  `AppSpacingTokens`/`AppTextStyleTokens` (which read `ScreenUtil()` live, no static cache) render at design values.
- **`name`** → `goldens/<name>_light.png` + `<name>_dark.png` (relative to the test file; `goldens/` is created on first generation,
  a single macOS-rendered set, **no `linux/` subdir**). Convention: `name` = the widget/page snake_case (`app_chat_item_widget`).
  The per-test titles (`'matches the light theme'`) are produced by the helper — never write `test_shouldMatchGolden_when{X}`.
- **`settle: false`** for any animated content (spinner/progress) or a page that renders one — otherwise the internal
  `pumpAndSettle` never returns. Add a one-line comment saying why.
- **Reactive pages need a bespoke harness.** A page whose repository keeps a `watch*` subscription and mock seed delays in flight
  works with neither `settle: true` (pumpAndSettle waits forever) nor `settle: false` (snapshots the spinner). Mirror
  `test/presentation/pages/chat_thread_page/chat_thread_page_golden_test.dart`: same frozen clock / real fonts / pinned surface as
  `golden.dart`, but settle with a bounded `for (…) await tester.pump(const Duration(milliseconds: 150))` loop.
- **DI:** pure widgets need none; a page wraps its own BLoC inline (`BlocProvider<…>(create: …, child: …)`). A page whose BLoC
  self-creates from `getIt` needs `setUpAll(() async => configureDependencies(Environment.test))` +
  `tearDownAll(() async => getIt.reset())` at `main()` level. `test/flutter_test_config.dart` is auto-loaded but only seeds the
  `SharedPreferences` / `FlutterSecureStorage` mock backends — it does not build the container. A DB-backed page additionally needs
  `await getIt<AppDatabase>().clearEntireDatabase()`; a page that reads the session spine (identity card / Show QR / account
  avatar) needs `registerFakeSession()` from `test/utils/fake_session_repository.dart`. Relative imports of test helpers are
  allowed (test files are not in `lib/`).
- **Style:** line length **140**, single quotes, `const` wherever possible. Golden `.png` files are **committable fixtures** (not gitignored).

5. **Generate baselines (locally, on your M1 — never in CI):**
   ```bash
   make golden-update                                                  # all golden tests
   make golden-update FILE=test/presentation/pages/chats_list_page/chats_list_page_golden_test.dart   # one file
   ```
   This runs `fvm flutter test --tags golden --update-goldens` and writes the `goldens/*.png`. Run `make generate` first if the
   test needs `*.mocks.dart`/codegen.

6. **Verify the goldens pass (locally):**
   ```bash
   make golden-verify                                                  # or: make golden-verify FILE=...
   ```
   On failure the runner writes `*_testImage.png` / `*_masterImage.png` diffs under a gitignored `failures/` dir next to the
   golden. A diff almost always means the widget changed — review, then regenerate with `make golden-update` if intended.
   > Note: a non-zero exit from `make golden-verify` is a REAL failure — the repo has a full golden set, so the old "no tests ran"
   > (`flutter test` exit 79) escape hatch no longer applies. The only exception is a `FILE=` narrowing that matches no golden test.

7. **Format the files you created/changed, with explicit paths** (never format the `goldens/*.png`, and never a file you did not touch):
   ```bash
   fvm dart format -l 140 <test_file_path>   # add test/utils/golden.dart only if you changed the harness
   ```

8. **Remind the user** that `goldens/*.png` are fixtures (not codegen) and must be committed alongside the test (work lands on
   `develop`; pushing to a remote stays an explicit owner decision). Goldens are **not** checked by CI, so **run
   `make golden-verify` locally before committing** — that is the only place a golden regression is caught. If the look changed on
   purpose, regenerate (`make golden-update`) and commit the new PNGs.
