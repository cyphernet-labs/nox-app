@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/pages/terms_page/terms_page.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../utils/golden.dart';

void main() {
  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'NOX',
      packageName: 'com.cyphernetlabs.noxapp',
      version: '26.1.1',
      buildNumber: '7',
      buildSignature: '',
    );
  });

  goldenTest('terms_page', () => const TermsPage());
  goldenTestDesktop('terms_page', () => const TermsPage());
}
