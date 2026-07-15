import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';
import 'package:nox_app/presentation/pages/notifications_page/notifications_body.dart';
import 'package:nox_app/presentation/pages/notifications_page/notifications_page.dart';
import 'package:nox_app/presentation/pages/settings_root_page/settings_root_page.dart';
import 'package:nox_app/presentation/pages/splash_page/splash_page.dart';
import 'package:nox_app/presentation/widgets/settings/app_identity_card_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_qr_surface_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_list_detail_widget.dart';

import '../../../utils/fake_session_repository.dart';
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

  // The identity card loads the user's id from the session spine on init.
  setUp(registerFakeSession);
  tearDown(getIt.reset);

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
      expect(find.text(l10nEn.settingsNotificationsTitle), findsOneWidget);
      expect(find.text(l10nEn.settingsAppearanceTitle), findsOneWidget);
      expect(find.text(l10nEn.settingsAboutTitle), findsOneWidget);
      expect(find.text(l10nEn.logoutRow), findsOneWidget);
    });

    testWidgets('Initial-loading shows a spinner in the ID position', (tester) async {
      // First frame: the bloc is at its initial state (initialLoading: true); the
      // dispatched Initialize hasn't resolved the session yet.
      await pumpMobile(tester, settle: false);

      expect(find.descendant(of: find.byType(AppIdentityCardWidget), matching: find.byType(CircularProgressIndicator)), findsOneWidget);

      await tester.pumpAndSettle(); // let Initialize resolve so nothing leaks
    });

    testWidgets('tapping a settings row opens the real subscreen (7.2)', (tester) async {
      await pumpMobile(tester);

      await tester.tap(find.widgetWithText(ListTile, l10nEn.settingsNotificationsTitle));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsPage), findsOneWidget);
    });

    testWidgets('Copy puts the ID on the clipboard and shows a snackbar', (tester) async {
      await pumpMobile(tester);

      await tester.tap(find.byTooltip(l10nEn.idCopyTooltip));
      await tester.pump(); // snackbar in
      await tester.pump();

      expect(find.text(l10nEn.copiedToClipboard), findsOneWidget);
    });

    testWidgets('Show QR opens the brand-fixed light QR sheet', (tester) async {
      await pumpMobile(tester);

      await tester.tap(find.byTooltip(l10nEn.idShowQrTooltip));
      await tester.pumpAndSettle();

      expect(find.byType(AppQrSurfaceWidget), findsOneWidget);
      expect(find.text(l10nEn.qrSheetTitle), findsOneWidget);
    });

    testWidgets('Show/Hide reveal is available on mobile', (tester) async {
      await pumpMobile(tester);
      expect(find.byTooltip(l10nEn.idShowTooltip), findsOneWidget);
    });

    testWidgets('Log out opens a confirm dialog that Cancel dismisses', (tester) async {
      await pumpMobile(tester);

      await tester.tap(find.widgetWithText(ListTile, l10nEn.logoutRow));
      await tester.pumpAndSettle();
      expect(find.text(l10nEn.logoutDialogTitle), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, l10nEn.actionCancel));
      await tester.pumpAndSettle();
      expect(find.text(l10nEn.logoutDialogTitle), findsNothing);
    });

    testWidgets('confirming Log out navigates to Splash (1.1)', (tester) async {
      await pumpMobile(tester);

      await tester.tap(find.widgetWithText(ListTile, l10nEn.logoutRow));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, l10nEn.logoutRow));
      await tester.pumpAndSettle();

      expect(find.byType(SplashPage), findsOneWidget);
    });

    testWidgets('blur reverts an invalid inline name-edit (not a one-way trap)', (tester) async {
      await pumpMobile(tester);

      await tester.tap(find.byTooltip(l10nEn.settingsNameEditTooltip));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'bad name!'); // invalid charset
      await tester.pump();

      FocusManager.instance.primaryFocus?.unfocus(); // blur
      await tester.pumpAndSettle();

      // Edit mode exited and the committed name is unchanged (the draft was reverted).
      expect(find.byType(TextField), findsNothing);
      expect(find.byTooltip(l10nEn.settingsNameEditTooltip), findsOneWidget);
      expect(find.text('User7421'), findsOneWidget);
    });

    testWidgets('blur commits a valid inline name-edit', (tester) async {
      await pumpMobile(tester);

      await tester.tap(find.byTooltip(l10nEn.settingsNameEditTooltip));
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

      await tester.tap(find.widgetWithText(ListTile, l10nEn.settingsNotificationsTitle));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsBody), findsOneWidget);
      // No navigation push happened — still the same settings page.
      expect(find.byType(SettingsRootPage), findsOneWidget);
      expect(find.byType(NotificationsPage), findsNothing);
    });

    testWidgets('the raw ID is never revealable on desktop (no Show/Hide)', (tester) async {
      await pumpDesktop(tester);

      expect(find.byTooltip(l10nEn.idShowTooltip), findsNothing);
      // Inline account QR is shown instead.
      expect(find.byType(AppQrSurfaceWidget), findsOneWidget);
    });
  });
}
