import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/chat/app_chat_item_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  group('AppChatItemWidget', () {
    testWidgets('hides the badge when there are no unread messages', (tester) async {
      await pumpApp(tester, const AppChatItemWidget(name: 'Ann', preview: 'hi', time: '09:00'));

      expect(find.text('0'), findsNothing);
    });

    testWidgets('caps the unread badge at 99+', (tester) async {
      await pumpApp(tester, const AppChatItemWidget(name: 'Ann', preview: 'hi', time: '09:00', unread: 120));

      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('shows the raw unread count under 100', (tester) async {
      await pumpApp(tester, const AppChatItemWidget(name: 'Ann', preview: 'hi', time: '09:00', unread: 5));

      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('shows the exact count at the 99 boundary', (tester) async {
      await pumpApp(tester, const AppChatItemWidget(name: 'Ann', preview: 'hi', time: '09:00', unread: 99));

      expect(find.text('99'), findsOneWidget);
      expect(find.text('99+'), findsNothing);
    });

    testWidgets('caps to 99+ once the count exceeds 99', (tester) async {
      await pumpApp(tester, const AppChatItemWidget(name: 'Ann', preview: 'hi', time: '09:00', unread: 100));

      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('fires onTap', (tester) async {
      var taps = 0;
      await pumpApp(tester, AppChatItemWidget(name: 'Ann', preview: 'hi', time: '09:00', onTap: () => taps++));

      await tester.tap(find.byType(AppChatItemWidget));
      expect(taps, 1);
    });
  });
}
