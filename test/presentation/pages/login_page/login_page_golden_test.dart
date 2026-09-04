@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
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
  tearDownAll(() => QrScannerCapability.debugOverride = null);

  // Mobile (2.1) and the desktop `_wide` branch (window titlebar + centered
  // OnboardCard). Scanner present → `Scan QR` is shown.
  goldenTest('login_page', () => _login(scannerAvailable: true));
  goldenTestDesktop('login_page', () => _login(scannerAvailable: true));

  // Windows/Linux: no camera scanner, so `Scan QR` is hidden (FR-016/FR-017).
  goldenTest('login_page_no_scan', () => _login(scannerAvailable: false));
  goldenTestDesktop('login_page_no_scan', () => _login(scannerAvailable: false));

  // A link that will not parse. Pinned because the three refusals must stay
  // visibly different: this one means "scan it again", not "check your
  // connection", and a shared message would lose that.
  goldenTest('login_page_bad_link', () => _login(scannerAvailable: true, status: LoginStatus.errorFormat));
  goldenTestDesktop('login_page_bad_link', () => _login(scannerAvailable: true, status: LoginStatus.errorFormat));
}
