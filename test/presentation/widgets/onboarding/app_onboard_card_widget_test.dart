import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_onboard_card_widget.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  testWidgets('renders the brand head (logo + wordmark) above the child', (tester) async {
    await pumpApp(tester, const AppOnboardCardWidget(child: Text('field-slot')));

    expect(find.text(l10nEn.appName), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('field-slot'), findsOneWidget);
  });
}
