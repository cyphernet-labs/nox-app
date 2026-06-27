@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/shell/app_bottom_bar_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_navigation_rail_widget.dart';

import '../../../utils/golden.dart';

void main() {
  // The rail is a vertical strip; render it beside an empty body so it lays out
  // at its intrinsic width on the design surface.
  goldenTest(
    'app_navigation_rail_widget',
    () => Scaffold(
      body: Row(
        children: [
          AppNavigationRailWidget(active: AppTab.chats, onSelect: (_) {}, onCreate: () {}, accountLabel: 'User7421', onAccount: () {}),
          const Expanded(child: SizedBox.shrink()),
        ],
      ),
    ),
  );
}
