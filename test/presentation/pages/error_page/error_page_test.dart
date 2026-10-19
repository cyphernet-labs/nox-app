import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// Records what the app asks of the platform, so a test sees whether the
  /// system back sent it to the background.
  List<String> recordPlatformCalls(WidgetTester tester) {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    return calls;
  }

  testWidgets(
    'the system back on a blocking error sends the app to the background on Android',
    variant: TargetPlatformVariant.only(TargetPlatform.android),
    (tester) async {
      final calls = recordPlatformCalls(tester);
      await pumpApp(tester, AppErrorPage(params: ErrorPageParams.fatal(mode: ErrorPageMode.blocking)));

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(calls, contains('SystemNavigator.pop'));
      expect(find.text(l10nEn.errorGeneralTitle), findsOneWidget, reason: 'nothing goes past the error');
    },
  );

  testWidgets(
    'away from Android a blocking error does not close the app on back',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      // A desktop embedder answers SystemNavigator.pop by quitting; there is no
      // system back there to answer, and nothing may quit the app on its behalf.
      final calls = recordPlatformCalls(tester);
      await pumpApp(tester, AppErrorPage(params: ErrorPageParams.fatal(mode: ErrorPageMode.blocking)));

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(calls.where((m) => m == 'SystemNavigator.pop'), isEmpty);
      expect(find.text(l10nEn.errorGeneralTitle), findsOneWidget);
    },
  );

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

  testWidgets('wide embedded error shows the desktop title bar AND a back affordance (R1 parity)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApp(
      tester,
      AppErrorPage(
        params: ErrorPageParams.fatal(mode: ErrorPageMode.embedded, onRetry: _noop),
      ),
    );

    expect(find.byType(AppWindowTitlebarWidget), findsOneWidget);
    // R1: desktop embedded now offers a back affordance (parity with mobile embedded).
    expect(find.byTooltip(l10nEn.tooltipBack), findsOneWidget);
  });

  testWidgets('wide BLOCKING error suppresses system back via PopScope — parity with mobile (R1)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApp(tester, AppErrorPage(params: ErrorPageParams.fatal(mode: ErrorPageMode.blocking)));

    // On mobile a blocking error is wrapped in PopScope(canPop:false); desktop MUST match
    // so a fatal error is not escapable by the system back gesture.
    expect(find.byWidgetPredicate((w) => w is PopScope && w.canPop == false), findsOneWidget);
    expect(find.byTooltip(l10nEn.tooltipBack), findsNothing); // blocking has no back on either platform
  });
}
