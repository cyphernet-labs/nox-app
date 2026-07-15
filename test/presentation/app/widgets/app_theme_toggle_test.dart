import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';
import 'package:nox_app/presentation/app/widgets/app_theme_toggle.dart';

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

  group('AppThemeToggle', () {
    testWidgets('on a dark canvas shows the Light label and switches to light', (tester) async {
      final bloc = AppRootBloc();
      addTearDown(bloc.close);
      await pumpApp(
        tester,
        BlocProvider<AppRootBloc>.value(value: bloc, child: const AppThemeToggle()),
        themeMode: ThemeMode.dark,
      );

      expect(find.text(l10nEn.themeLight), findsOneWidget);
      expect(find.text(l10nEn.themeDark), findsNothing);

      await tester.tap(find.text(l10nEn.themeLight));
      await tester.pump();

      expect(bloc.state.themeMode, ThemeMode.light);
    });

    testWidgets('on a light canvas shows the Dark label and switches to dark', (tester) async {
      final bloc = AppRootBloc();
      addTearDown(bloc.close);
      await pumpApp(
        tester,
        BlocProvider<AppRootBloc>.value(value: bloc, child: const AppThemeToggle()),
        themeMode: ThemeMode.light,
      );

      expect(find.text(l10nEn.themeDark), findsOneWidget);
      expect(find.text(l10nEn.themeLight), findsNothing);

      await tester.tap(find.text(l10nEn.themeDark));
      await tester.pump();

      expect(bloc.state.themeMode, ThemeMode.dark);
    });
  });
}
