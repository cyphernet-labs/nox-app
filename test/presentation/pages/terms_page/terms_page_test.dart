import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/terms_page/terms_page.dart';
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

  testWidgets('Terms shows the doc heading, the four sections and a version footer', (tester) async {
    // Tall canvas so the whole scrollable (doc heading -> 4 sections -> footer)
    // is laid out (a short viewport would lazily skip the bottom version footer).
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApp(tester, const TermsPage());

    expect(find.text(l10nEn.termsDocHeading), findsOneWidget);
    expect(find.text(l10nEn.termsAcceptanceHeading), findsOneWidget);
    expect(find.text(l10nEn.termsIdentityHeading), findsOneWidget);
    expect(find.text(l10nEn.termsContentHeading), findsOneWidget);
    expect(find.text(l10nEn.termsPrivacyHeading), findsOneWidget);
    expect(find.text('26.1.1'), findsOneWidget); // footer (version only, no build)
  });
}
