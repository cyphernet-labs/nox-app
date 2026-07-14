import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/app_theme.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_bottom_bar_widget.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  group('AppBottomBarWidget', () {
    AppIconWidget iconAbove(WidgetTester tester, String label) {
      return tester.widget<AppIconWidget>(find.descendant(of: find.widgetWithText(Column, label), matching: find.byType(AppIconWidget)));
    }

    testWidgets('renders both tabs', (tester) async {
      await pumpApp(tester, AppBottomBarWidget(active: AppTab.chats, onSelect: (_) {}));

      expect(find.text(l10nEn.chats), findsOneWidget);
      expect(find.text(l10nEn.settings), findsOneWidget);
    });

    testWidgets('reports the tapped tab', (tester) async {
      AppTab? picked;
      await pumpApp(tester, AppBottomBarWidget(active: AppTab.chats, onSelect: (tab) => picked = tab));

      await tester.tap(find.text(l10nEn.settings));
      expect(picked, AppTab.settings);
    });

    testWidgets('renders the active tab filled in primary and the inactive tab outlined', (tester) async {
      await pumpApp(tester, AppBottomBarWidget(active: AppTab.chats, onSelect: (_) {}));

      final colorScheme = AppTheme.light().colorScheme;

      final activeIcon = iconAbove(tester, l10nEn.chats);
      expect(activeIcon.icon.path, NoxIcons.forumFill.path);
      expect(activeIcon.color, colorScheme.primary);

      final inactiveIcon = iconAbove(tester, l10nEn.settings);
      expect(inactiveIcon.icon.path, NoxIcons.settings.path);
      expect(inactiveIcon.color, colorScheme.onSurfaceVariant);
    });

    testWidgets('still reports a tap on the already-active tab', (tester) async {
      AppTab? picked;
      await pumpApp(tester, AppBottomBarWidget(active: AppTab.chats, onSelect: (tab) => picked = tab));

      await tester.tap(find.text(l10nEn.chats));
      expect(picked, AppTab.chats);
    });
  });
}
