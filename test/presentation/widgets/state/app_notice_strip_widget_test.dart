import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_notice_strip_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  testWidgets('renders the action button and fires onAction when tapped', (tester) async {
    var taps = 0;
    await pumpApp(
      tester,
      AppNoticeStripWidget(message: 'You are offline.', icon: NoxIcons.wifiOff, actionLabel: 'Retry', onAction: () => taps++),
    );

    expect(find.byType(TextButton), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.byType(TextButton));
    expect(taps, 1);
  });

  testWidgets('renders no action button when actionLabel is null', (tester) async {
    await pumpApp(tester, const AppNoticeStripWidget(message: 'You are offline.'));

    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('falls back to the error glyph when icon is null', (tester) async {
    await pumpApp(tester, const AppNoticeStripWidget(message: 'Failed to load.'));

    final icon = tester.widget<AppIconWidget>(find.byType(AppIconWidget));
    expect(icon.icon, NoxIcons.error);
  });

  testWidgets('always renders the message text', (tester) async {
    await pumpApp(tester, const AppNoticeStripWidget(message: 'Failed to load.'));

    expect(find.text('Failed to load.'), findsOneWidget);
  });
}
