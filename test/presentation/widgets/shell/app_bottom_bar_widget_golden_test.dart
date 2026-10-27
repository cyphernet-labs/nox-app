@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/shell/app_bottom_bar_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_create_fab_widget.dart';

import '../../../utils/golden.dart';

void main() {
  // Combined shell: bottom bar + docked FAB cradled in the notch (the real composition).
  goldenTest(
    'app_bottom_bar_widget',
    () => Scaffold(
      bottomNavigationBar: AppBottomBarWidget(active: AppTab.chats, onSelect: (_) {}),
      floatingActionButton: const AppCreateFabWidget(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      body: const SizedBox.shrink(),
    ),
  );
}
