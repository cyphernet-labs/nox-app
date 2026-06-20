@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/shell/tab_bar_shell_widget.dart';

import '../../../utils/golden.dart';

void main() {
  // Mobile layout (the golden surface is the 360-wide design size): bottom bar +
  // docked FAB + the active (Chats) tab body. The desktop rail branch is covered
  // by the widget test at a wide setSurfaceSize.
  goldenTest('tab_bar_shell', () => const TabBarShell());
}
