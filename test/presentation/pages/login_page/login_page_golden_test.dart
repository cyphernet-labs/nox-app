@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/pages/login_page/login_page.dart';

import '../../../utils/golden.dart';

void main() {
  // Mobile (2.1) and the desktop `_wide` branch (window titlebar + centered
  // OnboardCard) — the latter is the first desktop golden baseline.
  goldenTest('login_page', () => const LoginPage());
  goldenTestDesktop('login_page', () => const LoginPage());
}
