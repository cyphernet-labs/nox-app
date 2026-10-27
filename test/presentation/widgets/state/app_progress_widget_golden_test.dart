@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/state/app_progress_widget.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest('app_progress_widget', () => const AppProgressWidget(), settle: false);
}
