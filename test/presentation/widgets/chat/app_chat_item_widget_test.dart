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

    testWidgets('a chat with no messages is ONE line, sitting on the row centre', (tester) async {
      // The preview line used to render whether or not there was a preview, so a
      // chat with nothing in it was a two-line column with a blank second line -
      // and the Row centres that column, which left the name above the row's
      // middle with dead space under it.
      await pumpApp(tester, const AppChatItemWidget(name: 'Ann', preview: '', time: 'now'));

      final row = tester.getRect(find.byType(AppChatItemWidget));
      final name = tester.getRect(find.text('Ann'));
      final time = tester.getRect(find.text('now'));

      expect(name.center.dy, moreOrLessEquals(row.center.dy, epsilon: 1.5), reason: 'the name is off the row centre line');
      expect(time.center.dy, moreOrLessEquals(row.center.dy, epsilon: 1.5), reason: 'the timestamp is off the row centre line');
    });

    testWidgets('with a preview it is two lines again', (tester) async {
      await pumpApp(tester, const AppChatItemWidget(name: 'Ann', preview: 'hi', time: 'now'));

      // Two lines: the preview sits below the name, and the pair straddles the
      // row centre rather than either of them sitting on it.
      expect(find.text('hi'), findsOneWidget);
      expect(tester.getRect(find.text('hi')).top, greaterThan(tester.getRect(find.text('Ann')).bottom - 1));
    });
  });
}
