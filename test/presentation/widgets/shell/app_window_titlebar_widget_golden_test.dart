@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/shell/app_window_titlebar_widget.dart';

import '../../../utils/golden.dart';

void main() {
  // Desktop window titlebar (wordmark only, and with a screen subtitle).
  goldenTest(
    'app_window_titlebar_widget',
    () => const Align(
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppWindowTitlebarWidget(),
          SizedBox(height: 8),
          AppWindowTitlebarWidget(subtitle: 'Sign in'),
        ],
      ),
    ),
  );
}
