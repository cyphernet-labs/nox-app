import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/shell/app_wordmark_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  testWidgets('AppWordmarkWidget renders the NOX wordmark', (tester) async {
    await pumpApp(tester, const AppWordmarkWidget());

    expect(find.text(TextConstants.appName), findsOneWidget);
  });
}
