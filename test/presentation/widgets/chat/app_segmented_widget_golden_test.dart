@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/chat/app_segmented_widget.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest(
    'app_segmented_widget',
    () => Center(
      child: AppSegmentedWidget<int>(options: const {0: 'System', 1: 'Light', 2: 'Dark'}, selected: 0, onChanged: (_) {}),
    ),
  );
}
