import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/settings/app_identity_card_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_qr_surface_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  AppIdentityCardWidget card({
    bool revealable = true,
    bool showInlineQr = false,
    bool initialLoading = false,
    bool editing = false,
    bool idRevealed = false,
  }) => AppIdentityCardWidget(
    name: 'Aria',
    maskedId: TextConstants.idMask,
    rawId: 'RAWID-0123456789',
    revealable: revealable,
    showInlineQr: showInlineQr,
    initialLoading: initialLoading,
    editing: editing,
    idRevealed: idRevealed,
    onToggleReveal: () {},
    onEditName: () {},
    onCopy: () {},
    onShowQr: () {},
    nameEditField: editing ? const TextField(key: Key('edit')) : null,
  );

  group('AppIdentityCardWidget', () {
    testWidgets('mobile: shows the name, the masked ID and Show/Copy/Show-QR + edit actions', (tester) async {
      await pumpApp(tester, card());

      expect(find.text('Aria'), findsOneWidget);
      expect(find.text(TextConstants.idMask), findsOneWidget);
      expect(find.byTooltip(TextConstants.settingsNameEditTooltip), findsOneWidget);
      expect(find.byTooltip(TextConstants.idShowTooltip), findsOneWidget);
      expect(find.byTooltip(TextConstants.idCopyTooltip), findsOneWidget);
      expect(find.byTooltip(TextConstants.idShowQrTooltip), findsOneWidget);
    });

    testWidgets('Initial-loading swaps the ID for a spinner', (tester) async {
      // settle: false — the indeterminate spinner never settles.
      await pumpApp(tester, card(initialLoading: true), settle: false);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(TextConstants.idMask), findsNothing);
    });

    testWidgets('revealed state shows the raw identifier', (tester) async {
      await pumpApp(tester, card(idRevealed: true));

      expect(find.text('RAWID-0123456789'), findsOneWidget);
    });

    testWidgets('editing shows the supplied name field', (tester) async {
      await pumpApp(tester, card(editing: true));

      expect(find.byKey(const Key('edit')), findsOneWidget);
    });

    testWidgets('desktop: no reveal toggle, inline account QR instead', (tester) async {
      await pumpApp(tester, card(revealable: false, showInlineQr: true));

      expect(find.byTooltip(TextConstants.idShowTooltip), findsNothing);
      expect(find.byTooltip(TextConstants.idHideTooltip), findsNothing);
      expect(find.byType(AppQrSurfaceWidget), findsOneWidget);
    });
  });
}
