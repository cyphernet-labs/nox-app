import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';
import 'package:nox_app/presentation/pages/appearance_page/appearance_page.dart';

import '../../../utils/pump_app.dart';

void main() {
  testWidgets('lists the three theme options and switches theme live', (tester) async {
    final bloc = AppRootBloc();
    addTearDown(bloc.close);
    await pumpApp(tester, BlocProvider<AppRootBloc>.value(value: bloc, child: const AppearancePage()));

    expect(find.text(TextConstants.themeSystem), findsOneWidget);
    expect(find.text(TextConstants.themeLight), findsOneWidget);
    expect(find.text(TextConstants.themeDark), findsOneWidget);

    await tester.tap(find.text(TextConstants.themeDark));
    await tester.pump();

    expect(bloc.state.themeMode, ThemeMode.dark);
  });
}
