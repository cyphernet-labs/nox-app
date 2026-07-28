@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/settings/app_settings_nav_row_widget.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest(
    'app_settings_nav_row_widget',
    () => Builder(
      builder: (context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Resting row.
          AppSettingsNavRowWidget(title: 'Account', onTap: () {}),
          // Selected (desktop settings master pane).
          AppSettingsNavRowWidget(title: 'Appearance', selected: true, onTap: () {}),
          // Destructive (error color override).
          AppSettingsNavRowWidget(title: 'Log out', color: Theme.of(context).colorScheme.error, onTap: () {}),
        ],
      ),
    ),
  );
}
