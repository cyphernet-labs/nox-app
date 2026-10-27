@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/state/app_error_widget.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest('app_error_widget', () => AppErrorWidget(message: 'Could not load chats', onTryAgain: () {}));
}
