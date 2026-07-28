@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/presentation/widgets/settings/app_settings_switch_row_widget.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest(
    'app_settings_switch_row_widget',
    () => Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // On — with a supporting line and a leading glyph.
        AppSettingsSwitchRowWidget(
          title: 'Push notifications',
          value: true,
          supportingText: 'Alerts for new messages',
          leadingIcon: NoxIcons.notifications,
          onChanged: (_) {},
        ),
        // Off.
        AppSettingsSwitchRowWidget(
          title: 'Sound',
          value: false,
          supportingText: 'Play a tone on receipt',
          leadingIcon: NoxIcons.notificationsOff,
          onChanged: (_) {},
        ),
      ],
    ),
  );
}
