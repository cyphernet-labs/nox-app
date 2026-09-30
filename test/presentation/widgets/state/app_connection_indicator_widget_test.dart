import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/design/app_text_style_tokens.dart';
import 'package:nox_app/design/theme/app_theme.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/connection/connection_status.dart';
import 'package:nox_app/domain/service/connection_status_service.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/l10n/app_localizations.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/l10n/app_localizations_uk.dart';
import 'package:nox_app/presentation/widgets/state/app_connection_indicator_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/fixed_connection_status.dart';
import '../../../utils/pump_app.dart';

/// The connection corner (phase 040, FR-027 - FR-029, SC-006).
final l10nEn = AppLocalizationsEn();
final l10nUk = AppLocalizationsUk();

Future<void> _pumpIndicator(WidgetTester tester, ConnectionStatus status, {bool wide = false}) => pumpApp(
  tester,
  Center(
    child: AppConnectionIndicatorWidget(wide: wide, status: status),
  ),
);

void main() {
  group('what the corner shows', () {
    testWidgets('direct and current: nothing at all', (tester) async {
      await _pumpIndicator(tester, FixedConnectionStatusService.direct);

      expect(find.text(l10nEn.connectionTorBadge), findsNothing);
      expect(find.text(l10nEn.connectionConnecting), findsNothing);
      expect(find.byType(InkWell), findsNothing, reason: 'nothing to tap');
    });

    testWidgets('through Tor: the badge, and its name for a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpIndicator(tester, FixedConnectionStatusService.tor);

      expect(find.text(l10nEn.connectionTorBadge), findsOneWidget);
      expect(find.text(l10nEn.connectionConnecting), findsNothing);
      expect(find.bySemanticsLabel(l10nEn.connectionSemanticsTor), findsOneWidget);
      handle.dispose();
    });

    testWidgets('coming up directly: Connecting…, no badge', (tester) async {
      await _pumpIndicator(tester, FixedConnectionStatusService.connecting);

      expect(find.text(l10nEn.connectionConnecting), findsOneWidget);
      expect(find.text(l10nEn.connectionTorBadge), findsNothing);
    });

    testWidgets('coming up through Tor: Connecting… and the badge', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpIndicator(tester, FixedConnectionStatusService.connectingTor);

      expect(find.text(l10nEn.connectionConnecting), findsOneWidget);
      expect(find.text(l10nEn.connectionTorBadge), findsOneWidget);
      expect(find.bySemanticsLabel(l10nEn.connectionSemanticsConnectingTor), findsOneWidget);
      handle.dispose();
    });

    testWidgets('offline: nothing - the banner speaks, and the badge never shows offline (FR-028)', (tester) async {
      await _pumpIndicator(tester, const ConnectionStatus(state: LinkState.offline));

      expect(find.text(l10nEn.connectionTorBadge), findsNothing);
      expect(find.text(l10nEn.connectionConnecting), findsNothing);
    });

    testWidgets('a refused server: nothing - its own banner speaks', (tester) async {
      await _pumpIndicator(tester, const ConnectionStatus(state: LinkState.serverMismatch));

      expect(find.byType(InkWell), findsNothing);
    });
  });

  testWidgets('the tap target is at least 48x48 where a finger is the pointer (FR-029)', (tester) async {
    await _pumpIndicator(tester, FixedConnectionStatusService.tor);

    final size = tester.getSize(find.byType(InkWell));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  group('the explanation', () {
    testWidgets('narrow: a bottom sheet that says the connection goes through Tor', (tester) async {
      await _pumpIndicator(tester, FixedConnectionStatusService.tor);

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text(l10nEn.connectionInfoTitle), findsOneWidget);
      expect(find.text(l10nEn.connectionInfoTor), findsOneWidget);
    });

    testWidgets('wide: a dialog, and a direct path coming up says so', (tester) async {
      await _pumpIndicator(tester, FixedConnectionStatusService.connecting, wide: true);

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text(l10nEn.connectionInfoConnecting), findsOneWidget);
    });

    testWidgets('the local-network hint shows only where the platform asks for that access', (tester) async {
      await pumpApp(tester, const AppConnectionInfoContent(status: FixedConnectionStatusService.tor, localNetworkHint: true));
      expect(find.text(l10nEn.connectionInfoLocalNetwork), findsOneWidget);

      await pumpApp(tester, const AppConnectionInfoContent(status: FixedConnectionStatusService.tor, localNetworkHint: false));
      expect(find.text(l10nEn.connectionInfoLocalNetwork), findsNothing);
    });
  });

  testWidgets('in Ukrainian the corner speaks Ukrainian (SC-006)', (tester) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: Constants.designSize,
        fontSizeResolver: AppTextStyleTokens.fontSizeResolver,
        builder: (context, _) => MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('uk'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: Center(child: AppConnectionIndicatorWidget(wide: false, status: FixedConnectionStatusService.connectingTor)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10nUk.connectionConnecting), findsOneWidget);
    expect(find.text(l10nUk.connectionTorBadge), findsOneWidget);
  });

  testWidgets('without a fixed status it follows the live service', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    addTearDown(getIt.reset);
    final service = FixedConnectionStatusService(FixedConnectionStatusService.direct);
    getIt.allowReassignment = true;
    getIt.registerSingleton<ConnectionStatusService>(service);

    await pumpApp(tester, const Center(child: AppConnectionIndicatorWidget(wide: false)));
    expect(find.text(l10nEn.connectionTorBadge), findsNothing);

    service.emit(FixedConnectionStatusService.tor);
    await tester.pumpAndSettle();
    expect(find.text(l10nEn.connectionTorBadge), findsOneWidget);
  });
}
