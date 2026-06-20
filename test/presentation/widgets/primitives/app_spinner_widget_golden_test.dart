@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/primitives/app_spinner_widget.dart';

import '../../../utils/golden.dart';

void main() {
  // settle: false — captures the first frame of the (otherwise endless) animation.
  goldenTest('app_spinner_widget', () => const Center(child: AppSpinnerWidget(size: 32)), settle: false);
}
