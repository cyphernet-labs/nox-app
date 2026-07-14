import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';
import 'package:nox_app/presentation/pages/appearance_page/appearance_page.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  testWidgets('lists the three theme options and switches theme live', (tester) async {
    final bloc = AppRootBloc();
    addTearDown(bloc.close);
    await pumpApp(tester, BlocProvider<AppRootBloc>.value(value: bloc, child: const AppearancePage()));

    expect(find.text(l10nEn.themeSystem), findsOneWidget);
    expect(find.text(l10nEn.themeLight), findsOneWidget);
    expect(find.text(l10nEn.themeDark), findsOneWidget);

    await tester.tap(find.text(l10nEn.themeDark));
    await tester.pump();

    expect(bloc.state.themeMode, ThemeMode.dark);
  });
}
