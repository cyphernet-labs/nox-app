import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/widgets/chat/app_chat_people_section_widget.dart';

import '../../../utils/fake_session_repository.dart';
import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  group('AppChatPeopleSectionWidget', () {
    setUp(registerFakeSession);
    tearDown(getIt.reset);

    testWidgets('names the person this machine belongs to', (tester) async {
      await pumpApp(tester, const AppChatPeopleSectionWidget());
      await tester.pumpAndSettle();

      expect(find.text(l10nEn.chatPeopleTitle), findsOneWidget);
      expect(find.text(Constants.defaultUserLabel), findsOneWidget);
    });

    testWidgets('the invite control is disabled and says so', (tester) async {
      // Disabled rather than absent. A missing control answers "how do I add
      // somebody?" with silence; this one answers "later", which is the truth
      // until a relay exists.
      await pumpApp(tester, const AppChatPeopleSectionWidget());
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, l10nEn.chatInvitePerson));
      expect(button.onPressed, isNull, reason: 'a control that looks live and does nothing is worse than one that says it is not ready');
      expect(button.enabled, isFalse);
      expect(find.text(l10nEn.chatInviteLater), findsOneWidget);
    });

    testWidgets('tapping it produces nothing at all - no route, no message', (tester) async {
      // An error would read as a fault rather than as unfinished work, so the
      // assertion is that the tap is inert rather than that it explains itself.
      await pumpApp(tester, const AppChatPeopleSectionWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, l10nEn.chatInvitePerson), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text(l10nEn.chatInvitePerson), findsOneWidget, reason: 'still the same screen');
    });

    testWidgets('lists exactly one person, because that is all this machine holds', (tester) async {
      // Not a roster: nothing is stored and no membership is implied. The day
      // a relay lands, this is where a real one goes.
      await pumpApp(tester, const AppChatPeopleSectionWidget());
      await tester.pumpAndSettle();

      expect(find.text(Constants.defaultUserLabel), findsOneWidget);
    });
  });
}
