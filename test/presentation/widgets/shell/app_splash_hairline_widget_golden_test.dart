@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/shell/app_splash_hairline_widget.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest('app_splash_hairline_widget', () => const Align(alignment: Alignment.topCenter, child: AppSplashHairlineWidget()));
}
