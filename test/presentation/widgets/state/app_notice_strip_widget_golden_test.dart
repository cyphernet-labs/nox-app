@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/presentation/widgets/state/app_notice_strip_widget.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest(
    'app_notice_strip_widget',
    () => Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Plain notice (offline banner) — default `error` glyph, no action.
        const AppNoticeStripWidget(message: 'You are offline. Messages will send when you reconnect.'),
        const SizedBox(height: 16),
        // Notice with a trailing action (retry) and an explicit glyph.
        AppNoticeStripWidget(message: 'Could not load messages.', icon: NoxIcons.wifiOff, actionLabel: 'Retry', onAction: () {}),
      ],
    ),
  );
}
