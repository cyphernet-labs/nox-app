@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/shell/app_panel_header_widget.dart';

import '../../../utils/golden.dart';

void main() {
  // Desktop side-sheet/panel header: title + close affordance.
  goldenTest(
    'app_panel_header_widget',
    () => Align(
      alignment: Alignment.topCenter,
      child: AppPanelHeaderWidget(title: 'Chat info', onClose: () {}),
    ),
  );
}
