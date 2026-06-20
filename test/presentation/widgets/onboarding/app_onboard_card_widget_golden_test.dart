@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_onboard_card_widget.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest(
    'app_onboard_card_widget',
    () => const AppOnboardCardWidget(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(),
          SizedBox(height: 16),
          FilledButton(onPressed: null, child: Text(TextConstants.loginSignIn)),
        ],
      ),
    ),
  );
}
