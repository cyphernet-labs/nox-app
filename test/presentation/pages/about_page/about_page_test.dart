import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/about_page/about_page.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

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

  testWidgets('About shows the version and build number', (tester) async {
    await pumpApp(tester, const AboutPage());

    expect(find.text(l10nEn.versionLabel), findsOneWidget);
    expect(find.text('26.1.1 (build 7)'), findsOneWidget);
  });
}
