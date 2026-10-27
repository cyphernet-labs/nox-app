@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_id_field_widget.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest(
    'app_id_field_widget',
    () => Padding(
      padding: const EdgeInsets.all(16),
      child: AppIdFieldWidget(
        controller: TextEditingController(text: 'nox1A2b3C4d5E6f7G8h9I0jKlMnOpQrStUvWx'),
        canPaste: true,
        onPaste: () {},
      ),
    ),
  );
}
