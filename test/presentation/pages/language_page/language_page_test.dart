import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/app_language.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/language_page/language_page.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  testWidgets('lists the three languages with System selected by default', (tester) async {
    await pumpApp(tester, const LanguagePage());

    expect(find.text(l10nEn.languageSystem), findsOneWidget);
    expect(find.text(l10nEn.languageEnglish), findsOneWidget);
    expect(find.text(l10nEn.languageUkrainian), findsOneWidget);

    final group = tester.widget<RadioGroup<AppLanguage>>(find.byType(RadioGroup<AppLanguage>));
    expect(group.groupValue, AppLanguage.system);
  });

  testWidgets('selecting a language moves the selection', (tester) async {
    await pumpApp(tester, const LanguagePage());

    await tester.tap(find.text(l10nEn.languageEnglish));
    await tester.pump();

    final group = tester.widget<RadioGroup<AppLanguage>>(find.byType(RadioGroup<AppLanguage>));
    expect(group.groupValue, AppLanguage.english);
  });
}
