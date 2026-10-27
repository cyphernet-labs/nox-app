import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/widgets/shell/app_wordmark_widget.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  testWidgets('AppWordmarkWidget renders the NOX wordmark', (tester) async {
    await pumpApp(tester, const AppWordmarkWidget());

    expect(find.text(l10nEn.appName), findsOneWidget);
  });
}
