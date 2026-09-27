@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/settings/app_settings_switch_row_widget.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest(
    'app_settings_switch_row_widget',
    () => Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // On, with a supporting line. No leading glyph: settings rows are
        // icon-less, and this one was the single exception in the app.
        AppSettingsSwitchRowWidget(title: 'Push notifications', value: true, supportingText: 'Alerts for new messages', onChanged: (_) {}),
        // Off.
        AppSettingsSwitchRowWidget(title: 'Sound', value: false, supportingText: 'Play a tone on receipt', onChanged: (_) {}),
        // Disabled - the OS refused the permission, so the switch cannot act.
        const AppSettingsSwitchRowWidget(
          title: 'Push notifications',
          value: false,
          supportingText: 'Blocked in system settings',
          onChanged: null,
        ),
      ],
    ),
  );
}
