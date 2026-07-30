@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_primary_button_widget.dart';

import '../../../utils/golden.dart';

void main() {
  // idle (enabled label) / disabled (null onPressed) / loading (centered spinner).
  // settle:false — the loading variant hosts an animated spinner that never settles.
  // Raw paddings here (not design tokens): this scaffolding is built before
  // ScreenUtilInit, so AppSpacingTokens would fail to resolve.
  goldenTest(
    'app_primary_button_widget',
    () => const Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppPrimaryButtonWidget(label: 'Sign in', onPressed: _noop),
          SizedBox(height: 12),
          AppPrimaryButtonWidget(label: 'Sign in', onPressed: null),
          SizedBox(height: 12),
          AppPrimaryButtonWidget(label: 'Sign in', onPressed: _noop, loading: true),
        ],
      ),
    ),
    settle: false,
  );
}

void _noop() {}
