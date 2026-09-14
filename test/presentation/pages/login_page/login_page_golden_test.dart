@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/general/qr_scanner_capability.dart';
import 'package:nox_app/presentation/pages/login_page/bloc/login_bloc.dart';
import 'package:nox_app/presentation/pages/login_page/login_page.dart';

import '../../../utils/golden.dart';

/// The override is set inside the build thunk (runs at test time, not collection
/// time) so each golden is deterministic regardless of host and declaration order.
LoginPage _login({required bool scannerAvailable, LoginStatus? status}) {
  QrScannerCapability.debugOverride = scannerAvailable;
  return LoginPage(initialStatus: status);
}

void main() {
  // The screen watches the session phase since feature 036 - a server that
  // fails to prove who it is has to say so here, where the person is holding
  // the link - and that service comes from the container.
  setUpAll(() async {
    await configureDependencies(Environment.test);
  });

  tearDownAll(() async {
    QrScannerCapability.debugOverride = null;
    await getIt.reset();
  });

  // Mobile (2.1) and the desktop `_wide` branch (window titlebar + centered
  // OnboardCard). Scanner present → `Scan QR` is shown.
  goldenTest('login_page', () => _login(scannerAvailable: true));
  goldenTestDesktop('login_page', () => _login(scannerAvailable: true));

  // Windows/Linux: no camera scanner, so `Scan QR` is hidden (FR-016/FR-017).
  goldenTest('login_page_no_scan', () => _login(scannerAvailable: false));
  goldenTestDesktop('login_page_no_scan', () => _login(scannerAvailable: false));

  // A link that will not parse. Pinned because the refusals must stay
  // visibly different: this one means "scan it again", not "check your
  // connection", and a shared message would lose that.
  goldenTest('login_page_bad_link', () => _login(scannerAvailable: true, status: LoginStatus.errorFormat));
  goldenTestDesktop('login_page_bad_link', () => _login(scannerAvailable: true, status: LoginStatus.errorFormat));

  // The link parsed, and the machine at the address it carries is not the one
  // it names (036). Apart from the two above because the next action differs
  // again: not "scan it again", not "check your connection" - the server behind
  // this link is the wrong one.
  goldenTest('login_page_pin_refused', () => _login(scannerAvailable: true, status: LoginStatus.errorServerMismatch));
  goldenTestDesktop('login_page_pin_refused', () => _login(scannerAvailable: true, status: LoginStatus.errorServerMismatch));
}
