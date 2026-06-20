import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/shell/app_bottom_bar_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_create_fab_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_navigation_rail_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  group('AppNavigationRailWidget', () {
    Widget host({ValueChanged<AppTab>? onSelect, VoidCallback? onCreate}) => Scaffold(
      body: Row(
        children: [
          AppNavigationRailWidget(active: AppTab.chats, onSelect: onSelect ?? (_) {}, onCreate: onCreate ?? () {}),
          const Expanded(child: SizedBox.shrink()),
        ],
      ),
    );

    testWidgets('renders both destinations and the leading create FAB', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, host());

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(AppCreateFabWidget), findsOneWidget);
      expect(find.text(TextConstants.chats), findsOneWidget);
      expect(find.text(TextConstants.settings), findsOneWidget);
    });

    testWidgets('reports the tapped destination', (tester) async {
      AppTab? picked;
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, host(onSelect: (tab) => picked = tab));

      await tester.tap(find.text(TextConstants.settings));
      expect(picked, AppTab.settings);
    });

    testWidgets('the leading FAB fires onCreate', (tester) async {
      var created = false;
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, host(onCreate: () => created = true));

      await tester.tap(find.byType(AppCreateFabWidget));
      expect(created, isTrue);
    });
  });
}
