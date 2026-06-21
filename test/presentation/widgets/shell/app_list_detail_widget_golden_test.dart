@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/shell/app_list_detail_widget.dart';

import '../../../utils/golden.dart';

void main() {
  // The two-pane layout is inherently wide (verified by the widget test at a wide
  // surface); the golden surface is mobile-360, so we snapshot the no-selection
  // detail placeholder, which is what fills the detail pane until a row is chosen.
  goldenTest(
    'app_detail_empty_widget',
    () => const AppDetailEmptyWidget(title: 'Select a chat', message: 'Choose a conversation on the left, or press + to start a new one.'),
  );
}
