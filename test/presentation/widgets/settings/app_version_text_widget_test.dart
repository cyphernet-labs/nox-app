import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:nox_app/presentation/widgets/settings/app_version_text_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  setUp(() {
    // PackageInfo.fromPlatform() hits a platform channel — seed mock values so the
    // FutureBuilder resolves instead of throwing MissingPluginException.
    PackageInfo.setMockInitialValues(
      appName: 'NOX',
      packageName: 'com.cyphernetlabs.noxapp',
      version: '1.2.3',
      buildNumber: '42',
      buildSignature: '',
    );
  });

  testWidgets('renders empty while the package info future is unresolved', (tester) async {
    // First frame only: the FutureBuilder has not resolved yet, so the text is empty.
    await pumpApp(tester, const AppVersionTextWidget(), settle: false);

    expect(tester.widget<Text>(find.byType(Text)).data, isEmpty);
  });

  testWidgets('renders version with build number when showBuild is true (default)', (tester) async {
    await pumpApp(tester, const AppVersionTextWidget());

    expect(find.text('1.2.3 (build 42)'), findsOneWidget);
  });

  testWidgets('renders the bare version when showBuild is false', (tester) async {
    await pumpApp(tester, const AppVersionTextWidget(showBuild: false));

    expect(find.text('1.2.3'), findsOneWidget);
    expect(find.text('1.2.3 (build 42)'), findsNothing);
  });

  testWidgets('forwards the provided text style to the rendered Text', (tester) async {
    const style = TextStyle(fontSize: 11, fontWeight: FontWeight.w600);
    await pumpApp(tester, const AppVersionTextWidget(style: style));

    expect(tester.widget<Text>(find.text('1.2.3 (build 42)')).style, style);
  });
}
