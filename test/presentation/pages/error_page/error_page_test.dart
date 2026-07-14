import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/error_page/error_page.dart';
import 'package:nox_app/presentation/pages/error_page/error_page_params.dart';
import 'package:nox_app/presentation/widgets/shell/app_window_titlebar_widget.dart';

import '../../../utils/pump_app.dart';

Future<void> _noop() async {}

final l10nEn = AppLocalizationsEn();

void main() {
  testWidgets('embedded error shows back, title, message and Try again', (tester) async {
    await pumpApp(
      tester,
      AppErrorPage(
        params: ErrorPageParams.network(mode: ErrorPageMode.embedded, onRetry: _noop),
      ),
    );

    expect(find.byTooltip(l10nEn.tooltipBack), findsOneWidget);
    expect(find.text(l10nEn.noConnection), findsOneWidget); // network preset title
    expect(find.text(l10nEn.errorNetworkMessage), findsOneWidget);
    expect(find.text(l10nEn.actionTryAgain), findsOneWidget);
  });

  testWidgets('blocking error has no back affordance', (tester) async {
    await pumpApp(tester, AppErrorPage(params: ErrorPageParams.fatal(mode: ErrorPageMode.blocking)));

    expect(find.byTooltip(l10nEn.tooltipBack), findsNothing);
    expect(find.text(l10nEn.errorGeneralTitle), findsOneWidget);
  });

  testWidgets('Try again shows a spinner while onRetry runs', (tester) async {
    final completer = Completer<void>();
    await pumpApp(
      tester,
      AppErrorPage(
        params: ErrorPageParams.fatal(mode: ErrorPageMode.embedded, onRetry: () => completer.future),
      ),
      settle: false,
    );

    await tester.tap(find.text(l10nEn.actionTryAgain));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();
    expect(find.text(l10nEn.actionTryAgain), findsOneWidget);
  });

  testWidgets('wide window uses the desktop title bar instead of an app-bar back', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApp(
      tester,
      AppErrorPage(
        params: ErrorPageParams.fatal(mode: ErrorPageMode.embedded, onRetry: _noop),
      ),
    );

    expect(find.byType(AppWindowTitlebarWidget), findsOneWidget);
    expect(find.byTooltip(l10nEn.tooltipBack), findsNothing);
  });
}
