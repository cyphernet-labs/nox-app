import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/design/app_text_style_tokens.dart';
import 'package:nox_app/design/theme/app_theme.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';
import 'package:nox_app/presentation/pages/about_page/about_page.dart';
import 'package:nox_app/presentation/pages/appearance_page/appearance_page.dart';
import 'package:nox_app/presentation/pages/chat_card_page/chat_card_page.dart';
import 'package:nox_app/presentation/pages/chat_thread_page/chat_thread_page.dart';
import 'package:nox_app/presentation/pages/chats_list_page/chats_list_page.dart';
import 'package:nox_app/presentation/pages/create_chat_page/create_chat_page.dart';
import 'package:nox_app/presentation/pages/error_page/error_page.dart';
import 'package:nox_app/presentation/pages/file_view_page/file_view_page.dart';
import 'package:nox_app/presentation/pages/language_page/language_page.dart';
import 'package:nox_app/presentation/pages/login_page/login_page.dart';
import 'package:nox_app/presentation/pages/notifications_page/notifications_page.dart';
import 'package:nox_app/presentation/pages/qr_scan_page/qr_scan_page.dart';
import 'package:nox_app/presentation/pages/screens_gallery_page/screens_gallery_page.dart';
import 'package:nox_app/presentation/pages/set_username_page/set_username_page.dart';
import 'package:nox_app/presentation/pages/splash_page/splash_page.dart';
import 'package:nox_app/presentation/pages/settings_root_page/settings_root_page.dart';
import 'package:nox_app/presentation/pages/terms_page/terms_page.dart';
import 'package:nox_app/presentation/widgets/shell/tab_bar_shell_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  // The shell (4.1) + Chats list (5.1) reached from the gallery resolve ChatRepository from DI.
  setUpAll(() async {
    await configureDependencies(Environment.test);
  });

  tearDownAll(() async {
    await getIt.reset();
  });

  // The page's AppBar hosts AppThemeToggle, which reads AppRootBloc only on tap.
  Widget underTest() => BlocProvider<AppRootBloc>(create: (_) => AppRootBloc(), child: const ScreensGalleryPage());

  testWidgets('lists the screen-map sections and screens', (tester) async {
    await pumpApp(tester, underTest());

    expect(find.text(TextConstants.screensGalleryTitle), findsOneWidget);
    // Top-of-list section headers + a screen row (title + id badge).
    expect(find.text('Launch'), findsOneWidget);
    expect(find.text('Onboarding'), findsOneWidget);
    expect(find.text('Splash'), findsOneWidget);
    expect(find.text('1.1'), findsOneWidget);
    // Scroll to confirm a later section/screen is listed too (ListView builds lazily).
    await tester.scrollUntilVisible(find.text('About'), 200);
    expect(find.text('About'), findsOneWidget);
  });

  testWidgets('every screen row is wired — no "coming soon" stubs remain (phase 1 complete)', (tester) async {
    await pumpApp(tester, underTest());

    // M4 wires the last screens (5.2 / 5.3 / 5.4); the gallery has no stub left.
    expect(find.text(TextConstants.comingSoon), findsNothing);
  });

  testWidgets('activated Chat thread row (5.2) opens ChatThreadPage', (tester) async {
    await pumpApp(tester, underTest());

    final row = find.widgetWithText(ListTile, 'Chat thread');
    await tester.scrollUntilVisible(row, 200);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.byType(ChatThreadPage), findsOneWidget);
  });

  testWidgets('activated File view row (5.3) opens FileViewPage', (tester) async {
    await pumpApp(tester, underTest());

    final row = find.widgetWithText(ListTile, 'File view');
    await tester.scrollUntilVisible(row, 200);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle(); // lets the fake download timer finish (no pending timer)

    expect(find.byType(FileViewPage), findsOneWidget);
  });

  testWidgets('activated Chat card row (5.4) opens ChatCardPage', (tester) async {
    await pumpApp(tester, underTest());

    final row = find.widgetWithText(ListTile, 'Chat card');
    await tester.scrollUntilVisible(row, 200);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.byType(ChatCardPage), findsOneWidget);
  });

  testWidgets('theme toggle dispatches to AppRootBloc without throwing', (tester) async {
    await pumpApp(tester, underTest());

    await tester.tap(find.byTooltip(TextConstants.tooltipToggleTheme));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('activated Splash row (1.1) opens SplashPage', (tester) async {
    await pumpApp(tester, underTest());

    await tester.tap(find.text('Splash'));
    await tester.pumpAndSettle();

    expect(find.byType(SplashPage), findsOneWidget);
  });

  testWidgets('activated Login row (2.1) opens LoginPage', (tester) async {
    await pumpApp(tester, underTest());

    await tester.scrollUntilVisible(find.text('2.1'), 200);
    await tester.tap(find.widgetWithText(ListTile, 'Login'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('activated QR scan row (2.2) opens QrScanPage', (tester) async {
    await pumpApp(tester, underTest(), settle: false);

    await tester.scrollUntilVisible(find.text('2.2'), 200);
    await tester.tap(find.widgetWithText(ListTile, 'QR scan'));
    await tester.pumpAndSettle();

    expect(find.byType(QrScanPage), findsOneWidget);
  });

  testWidgets('activated Set username row (2.3) opens SetUsernamePage', (tester) async {
    await pumpApp(tester, underTest());

    await tester.scrollUntilVisible(find.text('2.3'), 200);
    await tester.tap(find.widgetWithText(ListTile, 'Set username'));
    await tester.pumpAndSettle();

    expect(find.byType(SetUsernamePage), findsOneWidget);
  });

  testWidgets('activated Error row (3.1) opens AppErrorPage', (tester) async {
    await pumpApp(tester, underTest());

    await tester.scrollUntilVisible(find.text('3.1'), 200);
    await tester.tap(find.widgetWithText(ListTile, 'Error')); // the row, not the section header
    await tester.pumpAndSettle();

    expect(find.byType(AppErrorPage), findsOneWidget);
  });

  testWidgets('activated Language row (7.4) opens LanguagePage', (tester) async {
    await pumpApp(tester, underTest());

    final row = find.widgetWithText(ListTile, 'Language');
    await tester.scrollUntilVisible(row, 200);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.byType(LanguagePage), findsOneWidget);
  });

  testWidgets('activated Notifications row (7.2) opens NotificationsPage', (tester) async {
    await pumpApp(tester, underTest());

    final row = find.widgetWithText(ListTile, 'Notifications');
    await tester.scrollUntilVisible(row, 200);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.byType(NotificationsPage), findsOneWidget);
  });

  testWidgets('activated Terms (7.6) and About (7.7) rows open their pages', (tester) async {
    await pumpApp(tester, underTest());

    final termsRow = find.widgetWithText(ListTile, 'Terms');
    await tester.scrollUntilVisible(termsRow, 200);
    await tester.ensureVisible(termsRow);
    await tester.pumpAndSettle();
    await tester.tap(termsRow);
    await tester.pumpAndSettle();
    expect(find.byType(TermsPage), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    final aboutRow = find.widgetWithText(ListTile, 'About');
    await tester.scrollUntilVisible(aboutRow, 200);
    await tester.ensureVisible(aboutRow);
    await tester.pumpAndSettle();
    await tester.tap(aboutRow);
    await tester.pumpAndSettle();
    expect(find.byType(AboutPage), findsOneWidget);
  });

  testWidgets('activated Create chat row (6.1) opens CreateChatPage', (tester) async {
    await pumpApp(tester, underTest(), settle: false);

    final row = find.widgetWithText(ListTile, 'Create chat');
    await tester.scrollUntilVisible(row, 200);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.byType(CreateChatPage), findsOneWidget);
  });

  testWidgets('activated Tab bar shell row (4.1) opens TabBarShell', (tester) async {
    await pumpApp(tester, underTest());

    final row = find.widgetWithText(ListTile, 'Tab bar shell');
    await tester.scrollUntilVisible(row, 200);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.byType(TabBarShell), findsOneWidget);
  });

  testWidgets('activated Chats list row (5.1) opens ChatsListPage', (tester) async {
    await pumpApp(tester, underTest());

    final row = find.widgetWithText(ListTile, 'Chats list');
    await tester.scrollUntilVisible(row, 200);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.byType(ChatsListPage), findsOneWidget);
  });

  testWidgets('activated Settings row (7.1) opens SettingsRootPage', (tester) async {
    await pumpApp(tester, underTest());

    final row = find.widgetWithText(ListTile, 'Settings');
    await tester.scrollUntilVisible(row, 200);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.byType(SettingsRootPage), findsOneWidget);
  });

  testWidgets('activated Appearance row (7.3) opens AppearancePage', (tester) async {
    // AppearancePage reads AppRootBloc in build, so the bloc must sit ABOVE the
    // navigator (as AppRoot does). pumpApp can't do that, so wrap manually.
    await tester.pumpWidget(
      BlocProvider<AppRootBloc>(
        create: (_) => AppRootBloc(),
        child: ScreenUtilInit(
          designSize: Constants.designSize,
          fontSizeResolver: AppTextStyleTokens.fontSizeResolver,
          builder: (context, _) => MaterialApp(theme: AppTheme.light(), home: const ScreensGalleryPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.widgetWithText(ListTile, 'Appearance');
    await tester.scrollUntilVisible(row, 200);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.byType(AppearancePage), findsOneWidget);
  });
}
