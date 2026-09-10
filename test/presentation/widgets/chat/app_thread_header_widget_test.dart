import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/widgets/chat/app_thread_header_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_avatar_widget.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  final chat = ChatModel(
    id: 'c1',
    name: 'General Discussion',
    lastMessagePreview: 'Hello there',
    lastMessageAt: DateTime(2026, 1, 1, 12, 0),
  );

  group('AppThreadHeaderWidget', () {
    testWidgets('renders the avatar, the chat name and the info action tooltip from l10n', (tester) async {
      await pumpApp(tester, AppThreadHeaderWidget(chat: chat, onInfo: () {}));

      expect(find.byType(AppAvatarWidget), findsOneWidget);
      expect(find.text('General Discussion'), findsOneWidget);
      expect(find.byTooltip(l10nEn.tooltipChatInfo), findsOneWidget);
    });

    testWidgets('the chat name is single-line and ellipsized', (tester) async {
      await pumpApp(tester, AppThreadHeaderWidget(chat: chat, onInfo: () {}));

      final nameText = tester.widget<Text>(find.text('General Discussion'));
      expect(nameText.maxLines, 1);
      expect(nameText.overflow, TextOverflow.ellipsis);
    });

    testWidgets('tapping the name/avatar row invokes onInfo', (tester) async {
      var infoTaps = 0;
      await pumpApp(tester, AppThreadHeaderWidget(chat: chat, onInfo: () => infoTaps++));

      await tester.tap(find.text('General Discussion'));
      await tester.pumpAndSettle();

      expect(infoTaps, 1);
    });

    testWidgets('tapping the trailing folder action invokes onInfo', (tester) async {
      var infoTaps = 0;
      await pumpApp(tester, AppThreadHeaderWidget(chat: chat, onInfo: () => infoTaps++));

      await tester.tap(find.byTooltip(l10nEn.tooltipChatInfo));
      await tester.pumpAndSettle();

      expect(infoTaps, 1);
    });

    testWidgets('both interactive targets each increment onInfo independently', (tester) async {
      var infoTaps = 0;
      await pumpApp(tester, AppThreadHeaderWidget(chat: chat, onInfo: () => infoTaps++));

      await tester.tap(find.text('General Discussion'));
      await tester.pumpAndSettle();
      expect(infoTaps, 1);

      await tester.tap(find.byTooltip(l10nEn.tooltipChatInfo));
      await tester.pumpAndSettle();
      expect(infoTaps, 2);
    });
  });
}
