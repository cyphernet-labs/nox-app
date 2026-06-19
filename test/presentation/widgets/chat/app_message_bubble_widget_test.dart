import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
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

    testWidgets('renders a file-only bubble with the tighter all-around padding', (tester) async {
      const fileKey = Key('file-chip');
      await pumpApp(
        tester,
        const AppMessageBubbleWidget(
          isOwn: true,
          time: '09:00',
          file: SizedBox(key: fileKey, width: 10, height: 10),
        ),
      );

      expect(find.byKey(fileKey), findsOneWidget);

      final bubble = tester.widget<Container>(find.ancestor(of: find.byKey(fileKey), matching: find.byType(Container)).first);
      expect(bubble.padding, EdgeInsets.all(AppSpacingTokens.s8));
    });

    testWidgets('renders a single status glyph for the pending status', (tester) async {
      await pumpApp(tester, const AppMessageBubbleWidget(isOwn: true, text: 'hi', time: '09:00', status: MessageStatus.pending));

      expect(find.byType(AppIconWidget), findsOneWidget);
    });

    testWidgets('renders a single status glyph for the error status', (tester) async {
      await pumpApp(tester, const AppMessageBubbleWidget(isOwn: true, text: 'hi', time: '09:00', status: MessageStatus.error));

      expect(find.byType(AppIconWidget), findsOneWidget);
    });
  });
}
