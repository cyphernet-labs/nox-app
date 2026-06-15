import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';
import 'package:nox_app/presentation/pages/home_page/home_page.dart';
import 'package:nox_app/presentation/pages/ui_kit_page/ui_kit_page.dart';

import '../../../utils/pump_app.dart';

void main() {
  testWidgets('HomePage shows the launcher and opens the UI kit', (tester) async {
    await pumpApp(tester, BlocProvider<AppRootBloc>(create: (_) => AppRootBloc(), child: const HomePage()));

    expect(find.text(TextConstants.actionOpenUiKit), findsOneWidget);

    await tester.tap(find.text(TextConstants.actionOpenUiKit));
    await tester.pump(); // start the route transition
    await tester.pump(const Duration(milliseconds: 400)); // finish it (gallery has spinners → no pumpAndSettle)

    expect(find.byType(UiKitPage), findsOneWidget);
  });

  testWidgets('theme toggle dispatches to AppRootBloc', (tester) async {
    final bloc = AppRootBloc();
    addTearDown(bloc.close);
    await pumpApp(tester, BlocProvider<AppRootBloc>.value(value: bloc, child: const HomePage()));

    await tester.tap(find.byTooltip(TextConstants.tooltipToggleTheme));
    await tester.pump();

    // Light canvas + system default → toggling resolves to an explicit mode (no crash, bloc wired).
    expect(bloc.state.themeMode, isNot(ThemeMode.system));
  });
}
