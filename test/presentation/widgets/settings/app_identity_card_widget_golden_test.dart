@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/settings/app_identity_card_widget.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest(
    'app_identity_card_widget',
    () => Padding(
      padding: const EdgeInsets.all(16),
      child: AppIdentityCardWidget(
        name: 'Aria',
        rawId: 'u_345c2e3c0845d19f',
        initialLoading: false,
        editing: false,
        onEditName: () {},
        onCopy: () {},
      ),
    ),
  );
}
