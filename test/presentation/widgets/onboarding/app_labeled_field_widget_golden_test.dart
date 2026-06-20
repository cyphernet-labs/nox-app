@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_labeled_field_widget.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest(
    'app_labeled_field_widget',
    () => Padding(
      padding: const EdgeInsets.all(16),
      child: AppLabeledFieldWidget(
        controller: TextEditingController(text: 'Random thoughts'),
        label: TextConstants.createChatNameLabel,
        maxLength: 64,
        helperText: TextConstants.usernameHelper,
        errorText: TextConstants.nameTakenError,
      ),
    ),
  );
}
