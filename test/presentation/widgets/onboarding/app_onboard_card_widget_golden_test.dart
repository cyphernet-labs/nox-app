@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_onboard_card_widget.dart';

import '../../../utils/golden.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  goldenTest(
    'app_onboard_card_widget',
    () => AppOnboardCardWidget(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const TextField(),
          const SizedBox(height: 16),
          FilledButton(onPressed: null, child: Text(l10nEn.loginSignIn)),
        ],
      ),
    ),
  );
}
