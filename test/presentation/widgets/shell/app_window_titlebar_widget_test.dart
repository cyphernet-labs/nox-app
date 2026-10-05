import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/shell/app_window_titlebar_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  testWidgets('AppWindowTitlebarWidget renders the NOX wordmark and the subtitle', (tester) async {
    await pumpApp(tester, const AppWindowTitlebarWidget(subtitle: 'Sign in'));

    expect(find.text('NOX'), findsOneWidget); // styled wordmark
    expect(find.textContaining('Sign in'), findsOneWidget); // subtitle
  });

  testWidgets('a trailing widget sits at the right edge of the strip (phase 040)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApp(tester, const AppWindowTitlebarWidget(subtitle: 'Chats', trailing: Text('corner')));

    final strip = tester.getRect(find.byType(AppWindowTitlebarWidget));
    final corner = tester.getRect(find.text('corner'));
    expect(corner.right, greaterThan(strip.right - 40), reason: 'pushed to the right edge, not after the subtitle');
  });
}
