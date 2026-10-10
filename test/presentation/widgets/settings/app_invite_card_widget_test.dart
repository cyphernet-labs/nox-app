import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/widgets/settings/app_invite_card_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_qr_surface_widget.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

const String _link = 'nox://pair/A6CapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTwAAECAwQFBgcICQoLDA0ODwEGwKgBFCD7';

void main() {
  group('AppInviteCardWidget', () {
    testWidgets('shows the link as a QR AND as selectable text', (tester) async {
      // Both halves, because half the platforms have no camera: Windows and
      // Linux sign a device in by pasting, so dropping the text would leave
      // those two with a code nothing on the machine can read. Its only
      // coverage used to live in the People screen's tests, which 037 deleted
      // with the screen - and the widget outlived them.
      await pumpApp(tester, AppInviteCardWidget(link: _link, message: 'This link works for 10 minutes.', onDismiss: () {}));

      expect(find.byType(AppQrSurfaceWidget), findsOneWidget);
      expect(find.widgetWithText(SelectableText, _link), findsOneWidget);
      expect(find.text('This link works for 10 minutes.'), findsOneWidget);
    });

    testWidgets('the dismiss action says Hide, and hides rather than revoking', (tester) async {
      // "Hide", never "Cancel": nothing here revokes anything, and the token
      // stays usable for its whole life whatever this button says.
      var dismissed = 0;
      await pumpApp(tester, AppInviteCardWidget(link: _link, message: 'This link works for 10 minutes.', onDismiss: () => dismissed++));

      expect(find.text(l10nEn.actionHide), findsOneWidget);
      await tester.tap(find.text(l10nEn.actionHide));
      await tester.pumpAndSettle();

      expect(dismissed, 1);
    });

    testWidgets('a link that works only at home says so, under the message (phase 045)', (tester) async {
      // The person decides on this card where to carry the link. Without the
      // note, one carried to an office fails with nothing to explain why.
      await pumpApp(tester, AppInviteCardWidget(link: _link, message: 'This link works for 10 minutes.', homeOnly: true, onDismiss: () {}));

      expect(find.text(l10nEn.devicesInviteHomeOnly), findsOneWidget);
      final message = tester.getTopLeft(find.text('This link works for 10 minutes.'));
      final note = tester.getTopLeft(find.text(l10nEn.devicesInviteHomeOnly));
      final link = tester.getTopLeft(find.widgetWithText(SelectableText, _link));
      expect(note.dy, greaterThan(message.dy), reason: 'the note reads as part of what the link is');
      expect(note.dy, lessThan(link.dy), reason: 'the note sits above the link it qualifies');
    });

    testWidgets('a link that works from anywhere carries no note', (tester) async {
      await pumpApp(tester, AppInviteCardWidget(link: _link, message: 'This link works for 10 minutes.', onDismiss: () {}));

      expect(find.text(l10nEn.devicesInviteHomeOnly), findsNothing);
    });

    testWidgets('Copy puts the whole link on the clipboard and says so', (tester) async {
      // Selectable text was the only way out of this card, and selecting a
      // hundred wrapped characters with a mouse is not a way out of anything.
      // On Windows and Linux, which have no camera for the QR, this button is
      // the only path the link has to the other machine.
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await pumpApp(tester, AppInviteCardWidget(link: _link, message: 'This link works for 10 minutes.', onDismiss: () {}));
      await tester.tap(find.text(l10nEn.actionCopy));
      await tester.pumpAndSettle();

      // The WHOLE link, not what the two wrapped lines happen to show.
      expect(copied, _link);
      expect(find.text(l10nEn.copiedToClipboard), findsOneWidget);
    });
  });
}
