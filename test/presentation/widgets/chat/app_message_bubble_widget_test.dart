import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_message_bubble_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  group('AppMessageBubbleWidget', () {
    testWidgets('shows the text', (tester) async {
      await pumpApp(tester, const AppMessageBubbleWidget(isOwn: true, text: 'hello', time: '09:00'));

      expect(find.text('hello'), findsOneWidget);
    });

    testWidgets('own + status renders a status glyph', (tester) async {
      await pumpApp(tester, const AppMessageBubbleWidget(isOwn: true, text: 'hi', time: '09:00', status: MessageStatus.sent));

      expect(find.byType(AppIconWidget), findsOneWidget);
    });

    testWidgets('other message has no status glyph', (tester) async {
      await pumpApp(tester, const AppMessageBubbleWidget(isOwn: false, text: 'hi', time: '09:00'));

      expect(find.byType(AppIconWidget), findsNothing);
    });
  });
}
