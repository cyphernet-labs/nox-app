@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/presentation/widgets/settings/app_settings_nav_row_widget.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest(
    'app_settings_nav_row_widget',
    () => Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Phone: a standalone tile, chip on the left, chevron on the right.
        AppSettingsNavRowWidget(title: 'Devices', icon: NoxIcons.devices, onTap: () {}),
        AppSettingsNavRowWidget(title: 'Appearance', icon: NoxIcons.palette, onTap: () {}),
        // Destructive: error throughout, the glyph filled, and no chevron - it
        // opens a dialog rather than going anywhere.
        AppSettingsNavRowWidget(title: 'Log out', icon: NoxIcons.logoutFill, danger: true, onTap: () {}),
        SizedBox(height: 24),
        // Desktop pane: transparent until selected, and the selected one swaps
        // its glyph for the filled variant.
        AppSettingsNavRowWidget(title: 'Account', icon: NoxIcons.person, selectedIcon: NoxIcons.personFill, menuPane: true, onTap: () {}),
        AppSettingsNavRowWidget(
          title: 'Language',
          icon: NoxIcons.language,
          selectedIcon: NoxIcons.languageFill,
          selected: true,
          menuPane: true,
          onTap: () {},
        ),
      ],
    ),
  );
}
