@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/pages/about_page/about_page.dart';
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

  goldenTest('about_page', () => const AboutPage());
  goldenTestDesktop('about_page', () => const AboutPage());
}
