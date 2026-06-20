@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/presentation/widgets/shell/tab_bar_shell_widget.dart';

import '../../../utils/golden.dart';

void main() {
  // The shell hosts the real Chats list, whose bloc resolves ChatRepository from DI.
  setUpAll(() async {
    await configureDependencies(Environment.test);
  });

  tearDownAll(() async {
    await getIt.reset();
  });

  // Mobile layout (the golden surface is the 360-wide design size): bottom bar +
  // docked FAB + the active (Chats) tab body. The desktop rail branch is covered
  // by the widget test at a wide setSurfaceSize.
  goldenTest('tab_bar_shell', () => const TabBarShell());
}
