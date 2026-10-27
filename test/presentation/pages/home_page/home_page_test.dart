import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';
import 'package:nox_app/presentation/pages/home_page/home_page.dart';
import 'package:nox_app/presentation/pages/screens_gallery_page/screens_gallery_page.dart';
import 'package:nox_app/presentation/pages/ui_kit_page/ui_kit_page.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('HomePage shows the launcher and opens the UI kit', (tester) async {
    await pumpApp(tester, BlocProvider<AppRootBloc>(create: (_) => AppRootBloc(), child: const HomePage()));

    expect(find.text(l10nEn.actionOpenUiKit), findsOneWidget);

    await tester.tap(find.text(l10nEn.actionOpenUiKit));
    await tester.pump(); // start the route transition
    await tester.pump(const Duration(milliseconds: 400)); // finish it (gallery has spinners → no pumpAndSettle)

    expect(find.byType(UiKitPage), findsOneWidget);
  });

  testWidgets('HomePage opens the screens gallery', (tester) async {
    await pumpApp(tester, BlocProvider<AppRootBloc>(create: (_) => AppRootBloc(), child: const HomePage()));

    expect(find.text(l10nEn.actionOpenScreens), findsOneWidget);

    await tester.tap(find.text(l10nEn.actionOpenScreens));
    await tester.pumpAndSettle(); // the gallery is a static list (no spinners)

    expect(find.byType(ScreensGalleryPage), findsOneWidget);
  });

  testWidgets('theme toggle dispatches to AppRootBloc', (tester) async {
    final bloc = AppRootBloc();
    addTearDown(bloc.close);
    await pumpApp(tester, BlocProvider<AppRootBloc>.value(value: bloc, child: const HomePage()));

    await tester.tap(find.byTooltip(l10nEn.tooltipToggleTheme));
    await tester.pump();

    // Light canvas + system default → toggling resolves to an explicit mode (no crash, bloc wired).
    expect(bloc.state.themeMode, isNot(ThemeMode.system));
  });
}
