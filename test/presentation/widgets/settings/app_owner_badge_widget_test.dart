import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/widgets/settings/app_owner_badge_widget.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  group('AppOwnerBadgeWidget', () {
    testWidgets('states ownership in the app language', (tester) async {
      await pumpApp(tester, const AppOwnerBadgeWidget());

      expect(find.text(l10nEn.settingsOwnerBadge), findsOneWidget);
    });

    testWidgets('survives doubled text scale without overflowing', (tester) async {
      // The accessibility floor the project tests to, and the size at which a
      // fixed-width chip would burst.
      await tester.binding.setSurfaceSize(const Size(320, 200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpApp(tester, const AppOwnerBadgeWidget(), textScale: 2);

      expect(tester.takeException(), isNull);
    });
  });
}
