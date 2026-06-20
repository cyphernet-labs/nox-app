import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/theme/app_theme.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';
import 'package:nox_app/presentation/pages/about_page/about_page.dart';
import 'package:nox_app/presentation/pages/appearance_page/appearance_page.dart';
import 'package:nox_app/presentation/pages/error_page/error_page.dart';
import 'package:nox_app/presentation/pages/language_page/language_page.dart';
import 'package:nox_app/presentation/pages/notifications_page/notifications_page.dart';
import 'package:nox_app/presentation/pages/screens_gallery_page/screens_gallery_page.dart';
import 'package:nox_app/presentation/pages/splash_page/splash_page.dart';
import 'package:nox_app/presentation/pages/terms_page/terms_page.dart';

import '../../../utils/pump_app.dart';

void main() {
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

  testWidgets('un-wired screens render as disabled "coming soon" stubs', (tester) async {
    await pumpApp(tester, underTest());

    // No screen is wired yet, so the stub affordance is present across the list.
    expect(find.text(TextConstants.comingSoon), findsWidgets);

    // A late-milestone screen (5.2) stays a disabled stub through M1–M3.
    final chatThread = find.text('Chat thread');
    await tester.scrollUntilVisible(chatThread, 200);
    final tile = tester.widget<ListTile>(find.ancestor(of: chatThread, matching: find.byType(ListTile)));
    expect(tile.enabled, isFalse);
    expect(tile.onTap, isNull);
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

  testWidgets('activated Error row (3.1) opens AppErrorPage', (tester) async {
    await pumpApp(tester, underTest());

    await tester.scrollUntilVisible(find.text('3.1'), 200);
    await tester.tap(find.widgetWithText(ListTile, 'Error')); // the row, not the section header
    await tester.pumpAndSettle();

    expect(find.byType(AppErrorPage), findsOneWidget);
  });

  testWidgets('activated Language row (7.4) opens LanguagePage', (tester) async {
    await pumpApp(tester, underTest());

    await tester.scrollUntilVisible(find.text('7.4'), 200);
    await tester.tap(find.widgetWithText(ListTile, 'Language'));
    await tester.pumpAndSettle();

    expect(find.byType(LanguagePage), findsOneWidget);
  });

  testWidgets('activated Notifications row (7.2) opens NotificationsPage', (tester) async {
    await pumpApp(tester, underTest());

    await tester.scrollUntilVisible(find.text('7.2'), 200);
    await tester.tap(find.widgetWithText(ListTile, 'Notifications'));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationsPage), findsOneWidget);
  });

  testWidgets('activated Terms (7.6) and About (7.7) rows open their pages', (tester) async {
    await pumpApp(tester, underTest());

    await tester.scrollUntilVisible(find.text('7.6'), 200);
    await tester.tap(find.widgetWithText(ListTile, 'Terms'));
    await tester.pumpAndSettle();
    expect(find.byType(TermsPage), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('7.7'), 200);
    await tester.tap(find.widgetWithText(ListTile, 'About'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutPage), findsOneWidget);
  });

  testWidgets('activated Appearance row (7.3) opens AppearancePage', (tester) async {
    // AppearancePage reads AppRootBloc in build, so the bloc must sit ABOVE the
    // navigator (as AppRoot does). pumpApp can't do that, so wrap manually.
    await tester.pumpWidget(
      BlocProvider<AppRootBloc>(
        create: (_) => AppRootBloc(),
        child: ScreenUtilInit(
          designSize: Constants.designSize,
          minTextAdapt: true,
          builder: (context, _) => MaterialApp(theme: AppTheme.light(), home: const ScreensGalleryPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('7.3'), 200);
    await tester.tap(find.widgetWithText(ListTile, 'Appearance'));
    await tester.pumpAndSettle();

    expect(find.byType(AppearancePage), findsOneWidget);
  });
}
