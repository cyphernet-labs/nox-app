Generate a golden (snapshot) test for a `nox_app` page/widget.

> **Scope:** the single Dart package `nox_app` (layers-as-folders per `docs/blueprints/mobile/`). Run every command from the repo root. Flutter/Dart go through the **`fvm` CLI** (`fvm flutter` / `fvm dart`, SDK pinned in `.fvmrc` = 3.44.1) — never a hardcoded SDK path.
>
> **⚠ Golden harness — local-only, NOT in CI (read first).** This project deliberately keeps goldens **simple and local**:
> - **Plain Flutter goldens** (`matchesGoldenFile`) — **no `alchemist`, no Docker, no Linux/amd64 image, no CI golden job.** (The migrated source project used a pinned Docker image for byte-stable cross-host goldens; we explicitly do **not**.)
> - Baselines are **rendered and verified only on the developer's machine (Apple Silicon / macOS)**. They are a **local regression aid**, not a cross-platform gate. A teammate on another OS may see font/AA diffs — that is the accepted trade-off here (goldens are generated + checked solely on the owner's M1).
> - Golden tests are **excluded from CI**: they carry `@Tags(['golden'])`; `.github/workflows/ci.yml` runs `flutter test --exclude-tags golden`, and `make test` does the same. They run **only** via `make golden-update` / `make golden-verify` (which pass `--tags golden`). `dart_test.yaml` declares the `golden` tag.
> - Baseline `goldens/*.png` are **committable fixtures** (not gitignored — only `*.g.dart`/`*.freezed.dart`/`*.config.dart`/`*.mocks.dart` + `lib/design/gen/` are).
> - **Determinism:** pump under `ScreenUtilInit(designSize: Constants.designSize)` (360×779) and pin the surface to that size, so the ScreenUtil scale is a deterministic 1:1 and design tokens render at design values. `AppSpacingTokens.sN` / `AppTextStyleTokens` read `ScreenUtil()` **live** on each access (no static cache), so they resolve correctly once `ScreenUtilInit` has run and the surface is fixed.

## Input

$ARGUMENTS

The first argument is the path to the widget file (e.g. `lib/presentation/pages/item_list_page/item_list_page.dart`).
Any additional text describes specific visual scenarios to capture. If none are specified, generate reasonable defaults
based on the widget's visual states (and both `light`/`dark` themes — the app ships both via `AppTheme.light()`/`dark()`).

## Instructions

1. **Read the target widget and its dependencies** (same as `/widget-test`): the widget, its BLoC trio if any
   (`bloc/*_bloc.dart` + Freezed `*_event.dart`/`*_state.dart`, **bare** substates `Initializing`/`Initialized`/`Error`),
   the test-env DI it relies on (`configureDependencies(Environment.test)`), domain models, and the strings it renders
   (`TextConstants.*` from `lib/general/text_constants.dart` — there is no i18n).

2. **Identify visual states worth capturing:**
   - Light theme and dark theme (both ship via `AppTheme.light()`/`dark()` + `ThemeExtension<AppColors>`).
   - Default/empty, populated, and error states if they meaningfully change the UI (e.g. `ItemListPage` renders a
     `CircularProgressIndicator` while `Initializing`, a `PagedListView` of `ListTile`s when `Initialized`, and a
     `TextConstants.errorGeneralTitle` + retry button on `Error`).
   - Distinct modes (create/edit, tabs) if present.
   - If scenarios are provided in the arguments, use those.

3. **Reuse the pump helper** in `test/utils/pump_app.dart` (the same one `/widget-test` uses; create it first per `/widget-test`
   if absent). It wraps the widget in `ScreenUtilInit(designSize: Constants.designSize)` + `MaterialApp(theme: AppTheme.light()`,
   `darkTheme: AppTheme.dark())` with a `themeMode` parameter — pass `ThemeMode.dark` for the dark variant. A BLoC-backed page
   self-creates its BLoC in `initState`; the Item demo BLoC loads from the **test-env DI** (mock data) under
   `configureDependencies(Environment.test)`, so no repository mock is needed for it.

4. **Generate the golden test file mirroring the lib/ path under `test/`** (nox-app convention — tests deep-mirror the source
   tree, NOT flat): `test/presentation/pages/<page>/<widget_name>_golden_test.dart` — e.g.
   `lib/presentation/pages/item_list_page/item_list_page.dart` → `test/presentation/pages/item_list_page/item_list_page_golden_test.dart`
   (consistent with the live `test/presentation/pages/item_list_page/item_list_bloc_test.dart`).

## Test file conventions

```dart
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/presentation/pages/item_list_page/item_list_page.dart';

import '../../../utils/pump_app.dart'; // adjust relative depth to the test's location

// 1:1 with the ScreenUtil design canvas → deterministic token scale (see Rules).
const Size _surfaceSize = Constants.designSize;

void main() {
  setUpAll(() async => configureDependencies(Environment.test));
  tearDownAll(() async => getIt.reset());

  group('ItemListPage golden', () {
    testWidgets('matches the light theme', (tester) async {
      await tester.binding.setSurfaceSize(_surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpApp(tester, const ItemListPage());

      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/item_list_page_light.png'));
    });

    testWidgets('matches the dark theme', (tester) async {
      await tester.binding.setSurfaceSize(_surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpApp(tester, const ItemListPage(), themeMode: ThemeMode.dark);

      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/item_list_page_dark.png'));
    });
  });
}
```

## Rules

- **Tag** `@Tags(['golden'])` at the very top (before imports, with `library;`) — this is what keeps goldens out of CI / `make test`.
- **Naming — descriptive sentences** (`'matches the light theme'`). Do **NOT** use a `test_shouldMatchGolden_when{X}` prefix.
- **DI:** for a BLoC-backed page, boot the test container once — `setUpAll(() async => configureDependencies(Environment.test))`
  + `tearDownAll(() async => getIt.reset())` (the nox-app pattern; there is no `flutter_test_config.dart`). Pure-widget goldens
  (no BLoC / no `getIt`) can skip DI.
- **Reuse `pumpApp`** from `test/utils/pump_app.dart` — it provides the mandatory `ScreenUtilInit` + `AppTheme` canvas; capture
  both `light` and `dark` where the design differs. Relative imports of test helpers are allowed (test files are not in `lib/`).
- **Fixed surface size:** `tester.binding.setSurfaceSize(Constants.designSize)` (360×779) and restore with `addTearDown` — a 1:1
  ScreenUtil scale so tokens render at design values. `AppSpacingTokens`/`AppTextStyleTokens` read `ScreenUtil()` live (no static
  cache), so a consistent surface across the run is enough.
- **Golden file path:** `goldens/<widget_name>_<scenario>.png`, relative to the test file (`goldens/` is created on first generation).
  There is **no `linux/` subdir** — a single macOS-rendered set.
- **Subject:** `find.byType(MaterialApp)` for `matchesGoldenFile`. The pump helper already `pumpAndSettle()`s before you capture.
- **Style:** line length **140**, single quotes, `const` wherever possible.
- Golden `.png` files are **committable fixtures** (not gitignored).

5. **Generate baselines (locally, on your M1 — never in CI):**
   ```bash
   make golden-update                                                  # all golden tests
   make golden-update FILE=test/presentation/pages/item_list_page/item_list_page_golden_test.dart   # one file
   ```
   This runs `fvm flutter test --tags golden --update-goldens` and writes the `goldens/*.png`. Run `make generate` first if the
   test needs `*.mocks.dart`/codegen.

6. **Verify the goldens pass (locally):**
   ```bash
   make golden-verify                                                  # or: make golden-verify FILE=...
   ```
   On failure the runner writes `*_testImage.png` / `*_masterImage.png` diffs under a gitignored `failures/` dir next to the
   golden. A diff almost always means the widget changed — review, then regenerate with `make golden-update` if intended.
   > Note: until **at least one** `@Tags(['golden'])` test exists, `make golden-verify` / `make golden-update` exit non-zero with
   > "no tests ran" (`flutter test` exit 79) — that's expected on an empty golden set, not a failure.

7. **Format the files you created/changed, with explicit paths** (never format the `goldens/*.png`):
   ```bash
   fvm dart format -l 140 <test_file_path> test/utils/pump_app.dart
   ```

8. **Remind the user** that `goldens/*.png` are fixtures (not codegen) and must be committed — stage them and let the owner commit
   (repo no-auto-commit rule; on this branch commits go to `develop`). Goldens are **not** checked by CI, so **run
   `make golden-verify` locally before committing** — that is the only place a golden regression is caught. If the look changed on
   purpose, regenerate (`make golden-update`) and commit the new PNGs.
