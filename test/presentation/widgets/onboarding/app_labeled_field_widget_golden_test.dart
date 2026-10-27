@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_labeled_field_widget.dart';

import '../../../utils/golden.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  goldenTest(
    'app_labeled_field_widget',
    () => Padding(
      padding: const EdgeInsets.all(16),
      child: AppLabeledFieldWidget(
        controller: TextEditingController(text: 'Random thoughts'),
        label: l10nEn.createChatNameLabel,
        maxLength: 64,
        helperText: l10nEn.usernameHelper,
        errorText: l10nEn.nameTakenError,
      ),
    ),
  );
}
