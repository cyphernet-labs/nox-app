import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';
import 'package:nox_app/presentation/pages/screens_gallery_page/screens_gallery_page.dart';

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
}
