@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/pages/qr_scan_page/qr_scan_page.dart';

import '../../../utils/golden.dart';

void main() {
  // The reticle + mask are brand-fixed (#FAFAFA / #000 @ 55%): identical in both
  // themes; only the AppBar / placeholder surfaces differ by theme.
  goldenTest('qr_scan_page', () => const QrScanPage());
}
