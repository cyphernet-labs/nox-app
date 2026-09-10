import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/widgets/settings/app_invite_card_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_qr_surface_widget.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

const String _link = 'https://nox.app/p/#k=abc123&t=def456';

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
  });
}
