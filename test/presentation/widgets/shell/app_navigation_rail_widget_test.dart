import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/widgets/shell/app_bottom_bar_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_navigation_rail_widget.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  group('AppNavigationRailWidget', () {
    Widget host({ValueChanged<AppTab>? onSelect, VoidCallback? onCreate, VoidCallback? onAccount, String accountLabel = 'User7421'}) =>
        Scaffold(
          body: Row(
            children: [
              AppNavigationRailWidget(
                active: AppTab.chats,
                onSelect: onSelect ?? (_) {},
                onCreate: onCreate ?? () {},
                accountLabel: accountLabel,
                onAccount: onAccount ?? () {},
              ),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
        );

    testWidgets('renders both destinations and the leading create FAB', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, host());

      expect(find.byType(AppNavigationRailWidget), findsOneWidget);
      expect(find.byTooltip(l10nEn.tooltipCreateChat), findsOneWidget); // the create FAB
      expect(find.text(l10nEn.chats), findsOneWidget);
      expect(find.text(l10nEn.settings), findsOneWidget);
    });

    testWidgets('reports the tapped destination', (tester) async {
      AppTab? picked;
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, host(onSelect: (tab) => picked = tab));

      await tester.tap(find.text(l10nEn.settings));
      expect(picked, AppTab.settings);
    });

    testWidgets('the leading FAB fires onCreate', (tester) async {
      var created = false;
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, host(onCreate: () => created = true));

      await tester.tap(find.byTooltip(l10nEn.tooltipCreateChat));
      expect(created, isTrue);
    });

    testWidgets('renders the account avatar and fires onAccount on tap', (tester) async {
      var account = false;
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, host(onAccount: () => account = true));

      // The account avatar shows the label initials ('User7421' -> 'U') under an 'Account' tooltip.
      expect(find.byTooltip(l10nEn.settingsAccountTitle), findsOneWidget);
      expect(find.text('U'), findsOneWidget);

      await tester.tap(find.byTooltip(l10nEn.settingsAccountTitle));
      expect(account, isTrue);
    });
  });
}
