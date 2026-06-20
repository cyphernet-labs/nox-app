import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';
import 'package:nox_app/presentation/app/widgets/app_theme_toggle.dart';

import '../../../utils/pump_app.dart';

void main() {
  group('AppThemeToggle', () {
    testWidgets('on a dark canvas shows the Light label and switches to light', (tester) async {
      final bloc = AppRootBloc();
      addTearDown(bloc.close);
      await pumpApp(
        tester,
        BlocProvider<AppRootBloc>.value(value: bloc, child: const AppThemeToggle()),
        themeMode: ThemeMode.dark,
      );

      expect(find.text(TextConstants.themeLight), findsOneWidget);
      expect(find.text(TextConstants.themeDark), findsNothing);

      await tester.tap(find.text(TextConstants.themeLight));
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

      expect(find.text(TextConstants.themeDark), findsOneWidget);
      expect(find.text(TextConstants.themeLight), findsNothing);

      await tester.tap(find.text(TextConstants.themeDark));
      await tester.pump();

      expect(bloc.state.themeMode, ThemeMode.dark);
    });
  });
}
