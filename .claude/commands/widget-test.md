Generate a widget test for a `nox_app` page/widget.

> **Scope:** the single Dart package `nox_app` (layers-as-folders per `docs/blueprints/mobile/`). Run every command from the
> repo root via the **`fvm` CLI** (`fvm flutter` / `fvm dart`; SDK pinned in `.fvmrc`).

## Input

$ARGUMENTS

The first argument is the path to the widget file (e.g. `lib/presentation/pages/item_list_page/item_list_page.dart`).
Any additional text after the path describes specific test cases to cover. If none are specified, generate reasonable
defaults based on the widget's structure.

## Instructions

1. **Read the target widget and its dependencies:**
   - The widget itself. nox-app pages are plain `StatefulWidget`s that **create their own BLoC in `initState`** and provide it via
     `BlocProvider<T>.value(value: _bloc, child: BlocBuilder(...))` — e.g. `ItemListPage` does `_bloc = ItemListBloc()..add(const ItemListEvent.initialize())`
     in `initState` and `_bloc.close()` in `dispose`. `BaseStatePage<T>` (`lib/presentation/pages/base/base_state_page.dart`) is a
     `State` mixin for scaffold/appbar/drawer plumbing — it does **not** define `routeName`/`route()`; do not assume those exist.
   - Its BLoC trio if any (`bloc/*_bloc.dart` + Freezed `*_event.dart`/`*_state.dart`). Substates are **bare**:
     `Initializing` / `Initialized` / `Error` (per CLAUDE.md; page-prefixed names are only used on collision — they are NOT used here).
   - The DI the BLoC relies on. The verification Item slice is **network-only on test-env mock data**: under
     `configureDependencies(Environment.test)` it loads mock items, so its widget tests need **no** repository mock.
   - Domain models/enums referenced in the UI (`lib/domain/model/...`).
   - Strings — **all from `lib/general/text_constants.dart` (`TextConstants.xxx`, `static const`)**; there is **no i18n**.
     nox-app ships a UI kit under `lib/presentation/widgets/` (Feature-003: `App*Widget`s like `AppProgressWidget` /
     `AppErrorWidget` / `AppEmptyContentWidget` / `AppChatItemWidget` / `AppMessageBubbleWidget` / …) plus feedback helpers in
     `lib/presentation/helpers/app_feedback_helper.dart` (`showAppSnackBar` / `showAppBanner`). Prefer asserting against those +
     `TextConstants.*`; the shared pump helper is `test/utils/pump_app.dart`.

2. **Analyze the widget** to understand: states/modes (loading/error/data; create/edit; tabs), the text it renders
   (`TextConstants.*`), user interactions and which BLoC events they dispatch, and any dependency that must be controlled.

3. **Reuse or create the pump helper** in `test/utils/pump_app.dart`. The helper **must** wrap the widget in the same canvas the
   app uses, or design tokens and colors will not resolve:
   - `ScreenUtilInit(designSize: Constants.designSize, minTextAdapt: true)` — required, because `AppSpacingTokens.sN` /
     `AppTextStyleTokens` read `ScreenUtil()` and misrender/throw without it.
   - `MaterialApp(theme: AppTheme.light(), darkTheme: AppTheme.dark())` — required, because feature code reads colors via
     `context.appColors` (the `AppColors` `ThemeExtension`), which only resolves under an `AppTheme`.
   - **DI:** boot the test container once per file — `setUpAll(() async => configureDependencies(Environment.test))` +
     `tearDownAll(() async => getIt.reset())` (the nox-app pattern — there is **no** `flutter_test_config.dart`). The BLoC a page
     self-creates then service-locates its dependencies from that container.

4. **Generate the widget test file mirroring the lib/ path under `test/`** (nox-app convention — deep-mirror the source tree, NOT
   flat): `test/presentation/pages/<page>/<widget_name>_test.dart` — e.g.
   `lib/presentation/pages/item_list_page/item_list_page.dart` → `test/presentation/pages/item_list_page/item_list_page_test.dart`
   (alongside the live `test/presentation/pages/item_list_page/item_list_bloc_test.dart`).

## Test file conventions

```dart
// test/utils/pump_app.dart  (create once, reuse across widget + golden tests)
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/theme/app_theme.dart';
import 'package:nox_app/general/constants.dart';

/// Pumps [child] inside the app's ScreenUtil + theme canvas so AppSpacingTokens /
/// AppTextStyleTokens and `context.appColors` resolve as in production.
Future<void> pumpApp(WidgetTester tester, Widget child, {ThemeMode themeMode = ThemeMode.light}) async {
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: Constants.designSize,
      minTextAdapt: true,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        home: child,
        // Clamp OS font scaling so text metrics match production (mirror AppRoot).
        builder: (context, widget) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
          child: widget ?? const SizedBox.shrink(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
```

```dart
// test/presentation/pages/item_list_page/item_list_page_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/pages/item_list_page/item_list_page.dart';

import '../../../utils/pump_app.dart'; // adjust relative depth to the test's location

void main() {
  setUpAll(() async => configureDependencies(Environment.test));
  tearDownAll(() async => getIt.reset());

  group('ItemListPage', () {
    testWidgets('renders the mock items once the test-env load settles', (tester) async {
      await pumpApp(tester, const ItemListPage());

      // Initialize()->load runs against the test-env DI (mock data); pumpApp already pumpAndSettle'd.
      expect(find.byType(ListTile), findsWidgets);
    });
  });
}
```

For a page whose BLoC resolves a repository you must **control** (not the Item demo), mockito is available
(`@GenerateMocks([XxxRepository])`, generated by `make generate`). Reset and re-register before pumping:

```dart
// getIt.allowReassignment = true lets a test override a registered binding after configureDependencies.
setUp(() async {
  await configureDependencies(Environment.test);
  getIt.allowReassignment = true;
  getIt.registerSingleton<XxxRepository>(mockXxxRepository);
});
tearDown(() async => getIt.reset());
```

## Rules

- **Pump helper lives in `test/utils/pump_app.dart`** and MUST wrap in `ScreenUtilInit(designSize: Constants.designSize)` +
  `MaterialApp(theme: AppTheme.light()/dark())`. Skipping either breaks token/color resolution. Relative imports of test helpers
  are allowed (test files are not in `lib/`); production code uses full `package:nox_app/...` imports only.
- **DI via `configureDependencies(Environment.test)` + `getIt.reset()`** (in `setUpAll`/`tearDownAll`, or `setUp`/`tearDown` when a
  per-test mock override is needed). There is no `flutter_test_config.dart` and no auto-bootstrap — wire DI explicitly.
- **Mock only when necessary** with **mockito** (`@GenerateMocks([XxxRepository])` → `import '<test>.mocks.dart'`, generated by
  `make generate`, gitignored). To override a binding after `configureDependencies`, set `getIt.allowReassignment = true` then
  `getIt.registerSingleton<XxxRepository>(mock)`. No mocktail / `registerFallbackValue`. The Item slice needs no mock (test-env data).
- **Strings via `TextConstants`** — assert `find.text(TextConstants.xxx)` (e.g. `errorGeneralTitle`, `actionTryAgain`, `noData`).
  No `L10n` / i18n infra exists. Use `find.byIcon(...)` for icons, `find.byType(...)` for widgets.
- **Naming — descriptive sentences** (match the repo style, e.g. `test/presentation/pages/item_list_page/item_list_bloc_test.dart`).
  Do **NOT** use a `test_should{X}_when{Y}` prefix.
- **`@Tags(['golden'])` is for golden tests only** — do not tag widget tests (they run in `make test` / CI; golden tests are excluded).
- **`await tester.pumpAndSettle()`** to resolve animations; for a debounced field use `pumpAndSettle(const Duration(milliseconds: 400))`.
- **Test observable UI, not BLoC internals** (BLoC logic belongs in `/bloc-test`).
- **Style:** line length **140**, single quotes, `const` wherever possible.

5. **Run the test:**
   ```bash
   make generate                                  # only if the test needs *.mocks.dart / codegen
   fvm flutter test <test_file_path>              # or: make test FILE=<test_file_path>
   ```

6. **Format the files you created/changed, with explicit paths** (line length 140):
   ```bash
   fvm dart format -l 140 <test_file_path> test/utils/pump_app.dart
   ```
   Never whole-repo format as a completion step.
