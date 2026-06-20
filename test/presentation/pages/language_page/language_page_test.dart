import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/app_language.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/pages/language_page/language_page.dart';

import '../../../utils/pump_app.dart';

void main() {
  testWidgets('lists the three languages with System selected by default', (tester) async {
    await pumpApp(tester, const LanguagePage());

    expect(find.text(TextConstants.languageSystem), findsOneWidget);
    expect(find.text(TextConstants.languageEnglish), findsOneWidget);
    expect(find.text(TextConstants.languageUkrainian), findsOneWidget);

    final group = tester.widget<RadioGroup<AppLanguage>>(find.byType(RadioGroup<AppLanguage>));
    expect(group.groupValue, AppLanguage.system);
  });

  testWidgets('selecting a language moves the selection', (tester) async {
    await pumpApp(tester, const LanguagePage());

    await tester.tap(find.text(TextConstants.languageEnglish));
    await tester.pump();

    final group = tester.widget<RadioGroup<AppLanguage>>(find.byType(RadioGroup<AppLanguage>));
    expect(group.groupValue, AppLanguage.english);
  });
}
