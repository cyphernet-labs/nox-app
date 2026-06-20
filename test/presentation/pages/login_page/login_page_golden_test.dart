@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/pages/login_page/login_page.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest('login_page', () => const LoginPage());
}
