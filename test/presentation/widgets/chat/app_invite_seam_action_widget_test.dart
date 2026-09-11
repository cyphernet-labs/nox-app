import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/widgets/chat/app_invite_seam_action_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_thread_header_widget.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  group('AppInviteSeamActionWidget', () {
    testWidgets('is named for a screen reader and disabled', (tester) async {
      // Icon-only, so it must carry a text name (FR-017). The name is the
      // action alone: a disabled control is already announced as unavailable,
      // and the caption that says it comes later has its home in the chat card.
      await pumpApp(tester, const AppInviteSeamActionWidget());

      expect(find.byTooltip(l10nEn.chatInvitePerson), findsOneWidget);
      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.onPressed, isNull, reason: 'the relay does not exist yet, so neither does the action');
    });

    testWidgets('the info action stays live beside it, and comes first', (tester) async {
      // The corpus describes info first, then the seam. And the seam being
      // dimmed matters: AppIconWidget paints its own colour filter, so a null
      // onPressed alone leaves it looking exactly like the live action.
      final chat = ChatModel(id: 'c1', name: 'Kitchen', lastMessagePreview: '', lastMessageAt: DateTime(2026));
      await pumpApp(tester, AppThreadHeaderWidget(chat: chat, onInfo: () {}));

      final info = tester.getTopLeft(find.byTooltip(l10nEn.tooltipChatInfo)).dx;
      final invite = tester.getTopLeft(find.byTooltip(l10nEn.chatInvitePerson)).dx;
      expect(info, lessThan(invite), reason: 'info first, then the seam');
    });
  });
}
