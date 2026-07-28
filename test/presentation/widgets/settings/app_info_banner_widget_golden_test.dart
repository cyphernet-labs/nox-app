@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/presentation/widgets/settings/app_info_banner_widget.dart';

import '../../../utils/golden.dart';

void main() {
  // The banner's inner text Column is mainAxisSize.max; IntrinsicHeight bounds it to its
  // content so the golden shows the natural banner height (not a full-surface stretch).
  goldenTest(
    'app_info_banner_widget',
    () => Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: IntrinsicHeight(
          child: AppInfoBannerWidget(
            icon: NoxIcons.notificationsOff,
            title: 'Notifications are off',
            message: 'Enable notifications in system settings to get alerts for new messages.',
            actionLabel: 'Open settings',
            onAction: () {},
          ),
        ),
      ),
    ),
  );
}
