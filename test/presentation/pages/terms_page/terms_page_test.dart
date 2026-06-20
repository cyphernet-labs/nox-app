import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/pages/terms_page/terms_page.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../utils/pump_app.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'NOX',
      packageName: 'com.cyphernetlabs.noxapp',
      version: '26.1.1',
      buildNumber: '7',
      buildSignature: '',
    );
  });

  testWidgets('Terms shows the titled sections and a version footer', (tester) async {
    await pumpApp(tester, const TermsPage());

    expect(find.text(TextConstants.termsTermsHeading), findsOneWidget);
    expect(find.text(TextConstants.termsPrivacyHeading), findsOneWidget);
    expect(find.text('26.1.1'), findsOneWidget); // footer (version only, no build)
  });
}
