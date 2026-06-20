@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/pages/set_username_page/set_username_page.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest('set_username_page', () => const SetUsernamePage());
}
