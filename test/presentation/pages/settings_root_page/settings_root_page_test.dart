import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';
import 'package:nox_app/presentation/pages/notifications_page/notifications_body.dart';
import 'package:nox_app/presentation/pages/notifications_page/notifications_page.dart';
import 'package:nox_app/presentation/pages/settings_root_page/settings_root_page.dart';
import 'package:nox_app/presentation/pages/splash_page/splash_page.dart';
import 'package:nox_app/presentation/widgets/settings/app_identity_card_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_qr_surface_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_list_detail_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  // demo: true keeps the standalone preview behaviour (Log out → Splash; dev controls).
  // Real-flow logout (→ Login via the spine) is covered in app_root_logout_flow_test.dart.
  Widget underTest({bool inShell = false}) => BlocProvider<AppRootBloc>(
    create: (_) => AppRootBloc(),
    child: SettingsRootPage(inShell: inShell, demo: true),
  );

  group('SettingsRootPage (mobile)', () {
    Future<void> pumpMobile(WidgetTester tester, {bool settle = true}) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, underTest(), settle: settle);
    }

    testWidgets('shows the identity card, the settings rows and Log out', (tester) async {
      await pumpMobile(tester);

      expect(find.byType(AppIdentityCardWidget), findsOneWidget);
      expect(find.text(TextConstants.settingsNotificationsTitle), findsOneWidget);
      expect(find.text(TextConstants.settingsAppearanceTitle), findsOneWidget);
      expect(find.text(TextConstants.settingsAboutTitle), findsOneWidget);
      expect(find.text(TextConstants.logoutRow), findsOneWidget);
    });

    testWidgets('Initial-loading shows a spinner in the ID position', (tester) async {
      await pumpMobile(tester, settle: false);
      await tester.pump(); // first frame, Initialize not yet resolved (300ms)

      expect(find.descendant(of: find.byType(AppIdentityCardWidget), matching: find.byType(CircularProgressIndicator)), findsOneWidget);

      await tester.pumpAndSettle(); // let Initialize resolve so no timers leak
    });

    testWidgets('tapping a settings row opens the real subscreen (7.2)', (tester) async {
      await pumpMobile(tester);

      await tester.tap(find.widgetWithText(ListTile, TextConstants.settingsNotificationsTitle));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsPage), findsOneWidget);
    });

    testWidgets('Copy puts the ID on the clipboard and shows a snackbar', (tester) async {
      await pumpMobile(tester);

      await tester.tap(find.byTooltip(TextConstants.idCopyTooltip));
      await tester.pump(); // snackbar in
      await tester.pump();

      expect(find.text(TextConstants.copiedToClipboard), findsOneWidget);
    });

    testWidgets('Show QR opens the brand-fixed light QR sheet', (tester) async {
      await pumpMobile(tester);

      await tester.tap(find.byTooltip(TextConstants.idShowQrTooltip));
      await tester.pumpAndSettle();

      expect(find.byType(AppQrSurfaceWidget), findsOneWidget);
      expect(find.text(TextConstants.qrSheetTitle), findsOneWidget);
    });

    testWidgets('Show/Hide reveal is available on mobile', (tester) async {
      await pumpMobile(tester);
      expect(find.byTooltip(TextConstants.idShowTooltip), findsOneWidget);
    });

    testWidgets('Log out opens a confirm dialog that Cancel dismisses', (tester) async {
      await pumpMobile(tester);

      await tester.tap(find.widgetWithText(ListTile, TextConstants.logoutRow));
      await tester.pumpAndSettle();
      expect(find.text(TextConstants.logoutDialogTitle), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, TextConstants.actionCancel));
      await tester.pumpAndSettle();
      expect(find.text(TextConstants.logoutDialogTitle), findsNothing);
    });

    testWidgets('confirming Log out navigates to Splash (1.1)', (tester) async {
      await pumpMobile(tester);

      await tester.tap(find.widgetWithText(ListTile, TextConstants.logoutRow));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, TextConstants.logoutRow));
      await tester.pumpAndSettle();

      expect(find.byType(SplashPage), findsOneWidget);
    });

    testWidgets('blur reverts an invalid inline name-edit (not a one-way trap)', (tester) async {
      await pumpMobile(tester);

      await tester.tap(find.byTooltip(TextConstants.settingsNameEditTooltip));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'bad name!'); // invalid charset
      await tester.pump();

      FocusManager.instance.primaryFocus?.unfocus(); // blur
      await tester.pumpAndSettle();

      // Edit mode exited and the committed name is unchanged (the draft was reverted).
      expect(find.byType(TextField), findsNothing);
      expect(find.byTooltip(TextConstants.settingsNameEditTooltip), findsOneWidget);
      expect(find.text('User7421'), findsOneWidget);
    });

    testWidgets('blur commits a valid inline name-edit', (tester) async {
      await pumpMobile(tester);

      await tester.tap(find.byTooltip(TextConstants.settingsNameEditTooltip));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Freename'); // valid + free
      await tester.pumpAndSettle(); // debounce + availability check

      FocusManager.instance.primaryFocus?.unfocus(); // blur
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.text('Freename'), findsOneWidget);
    });
  });

  group('SettingsRootPage (desktop)', () {
    Future<void> pumpDesktop(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, underTest());
    }

    testWidgets('renders the list-detail with the identity card as the default (account) pane', (tester) async {
      await pumpDesktop(tester);

      expect(find.byType(AppListDetailWidget), findsOneWidget);
      expect(find.byType(AppIdentityCardWidget), findsOneWidget);
    });

    testWidgets('selecting a menu item swaps the detail pane without a push', (tester) async {
      await pumpDesktop(tester);

      await tester.tap(find.widgetWithText(ListTile, TextConstants.settingsNotificationsTitle));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsBody), findsOneWidget);
      // No navigation push happened — still the same settings page.
      expect(find.byType(SettingsRootPage), findsOneWidget);
      expect(find.byType(NotificationsPage), findsNothing);
    });

    testWidgets('the raw ID is never revealable on desktop (no Show/Hide)', (tester) async {
      await pumpDesktop(tester);

      expect(find.byTooltip(TextConstants.idShowTooltip), findsNothing);
      // Inline account QR is shown instead.
      expect(find.byType(AppQrSurfaceWidget), findsOneWidget);
    });
  });
}
