import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/shell/app_bottom_bar_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  group('AppBottomBarWidget', () {
    testWidgets('renders both tabs', (tester) async {
      await pumpApp(tester, AppBottomBarWidget(active: AppTab.chats, onSelect: (_) {}));

      expect(find.text(TextConstants.chats), findsOneWidget);
      expect(find.text(TextConstants.settings), findsOneWidget);
    });

    testWidgets('reports the tapped tab', (tester) async {
      AppTab? picked;
      await pumpApp(tester, AppBottomBarWidget(active: AppTab.chats, onSelect: (tab) => picked = tab));

      await tester.tap(find.text(TextConstants.settings));
      expect(picked, AppTab.settings);
    });
  });
}
