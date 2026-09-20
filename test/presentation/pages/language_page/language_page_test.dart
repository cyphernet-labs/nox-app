import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/app_language.dart';
import 'package:nox_app/general/locale_controller.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/language_page/language_page.dart';
import 'package:nox_app/presentation/widgets/settings/app_select_option_widget.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

/// Which option card reports itself selected. The card is the only thing that
/// knows, and asking it beats asking a `RadioGroup` that no longer exists: the
/// screen moved onto the same option cards Appearance 7.3 uses.
String? _selectedLabel(WidgetTester tester) {
  for (final card in tester.widgetList<AppSelectOptionWidget>(find.byType(AppSelectOptionWidget))) {
    if (card.selected) return card.label;
  }
  return null;
}

void main() {
  tearDown(() => LocaleController.instance.set(AppLanguage.system));

  testWidgets('lists the three languages with System selected by default', (tester) async {
    await pumpApp(tester, const LanguagePage());

    expect(find.text(l10nEn.languageSystem), findsOneWidget);
    expect(find.text(l10nEn.languageEnglish), findsOneWidget);
    expect(find.text(l10nEn.languageUkrainian), findsOneWidget);

    expect(find.byType(AppSelectOptionWidget), findsNWidgets(3));
    expect(_selectedLabel(tester), l10nEn.languageSystem);
  });

  testWidgets('selecting a language moves the selection, and moves the app with it', (tester) async {
    await pumpApp(tester, const LanguagePage());

    await tester.tap(find.text(l10nEn.languageEnglish));
    await tester.pump();

    expect(_selectedLabel(tester), l10nEn.languageEnglish);
    // The card is not the state: the controller is, and it is what re-renders
    // every other string in the app. A card that lit up without telling it would
    // look right and do nothing.
    expect(LocaleController.instance.language.value, AppLanguage.english);
  });

  testWidgets('the options carry no flags - a flag is not what a language is', (tester) async {
    // 40dp national flags sat here, clipped by the rows they were in, and in full
    // colour against an icon set that is monochrome everywhere else.
    await pumpApp(tester, const LanguagePage());

    for (final card in tester.widgetList<AppSelectOptionWidget>(find.byType(AppSelectOptionWidget))) {
      expect(card.preview, isNull, reason: '${card.label} still has a leading thumbnail');
    }
  });
}
