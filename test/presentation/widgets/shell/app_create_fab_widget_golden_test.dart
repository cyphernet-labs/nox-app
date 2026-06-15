@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/shell/app_create_fab_widget.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest('app_create_fab_widget', () => const Center(child: AppCreateFabWidget()));
}
