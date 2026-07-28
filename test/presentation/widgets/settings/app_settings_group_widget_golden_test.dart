@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/settings/app_settings_group_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_settings_nav_row_widget.dart';

import '../../../utils/golden.dart';

void main() {
  // Locks the grouped-card container (surface, rounding, row dividers).
  goldenTest(
    'app_settings_group_widget',
    () => Padding(
      padding: const EdgeInsets.all(16),
      child: AppSettingsGroupWidget(
        children: [
          AppSettingsNavRowWidget(title: 'Account', onTap: () {}),
          AppSettingsNavRowWidget(title: 'Appearance', onTap: () {}),
          AppSettingsNavRowWidget(title: 'Notifications', onTap: () {}),
        ],
      ),
    ),
  );
}
