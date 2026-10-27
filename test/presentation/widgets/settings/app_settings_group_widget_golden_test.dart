@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/settings/app_settings_group_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_settings_switch_row_widget.dart';

import '../../../utils/golden.dart';

void main() {
  // Locks the grouped-card container (surface, rounding, row dividers). Its rows
  // are switch rows now: the settings destinations left this container for one
  // tile each, and the 7.2 / 7.8 lists are what still lives in it.
  goldenTest(
    'app_settings_group_widget',
    () => Padding(
      padding: const EdgeInsets.all(16),
      child: AppSettingsGroupWidget(
        children: [
          AppSettingsSwitchRowWidget(title: 'Enable notifications', value: true, onChanged: (_) {}),
          AppSettingsSwitchRowWidget(title: 'Sound', value: false, supportingText: 'Play a tone on receipt', onChanged: (_) {}),
        ],
      ),
    ),
  );
}
