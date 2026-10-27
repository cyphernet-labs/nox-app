@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/presentation/pages/set_username_page/set_username_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/golden.dart';

void main() {
  // The screen reads the server-assigned name out of the session on open, so it needs
  // a container. With no session there is no label, and the field opens empty - which
  // is the state these baselines pin.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
  });

  tearDown(() async => getIt.reset());

  // Mobile (2.3) and the desktop `_wide` branch (centered OnboardCard).
  goldenTest('set_username_page', () => const SetUsernamePage());
  goldenTestDesktop('set_username_page', () => const SetUsernamePage());
}
