import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/widgets/settings/app_identity_card_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_qr_surface_widget.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  AppIdentityCardWidget card({bool revealable = true, bool initialLoading = false, bool editing = false, bool idRevealed = false}) =>
      AppIdentityCardWidget(
        name: 'Aria',
        maskedId: l10nEn.idMask,
        rawId: 'RAWID-0123456789',
        revealable: revealable,
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
      expect(find.text(l10nEn.idMask), findsOneWidget);
      expect(find.byTooltip(l10nEn.settingsNameEditTooltip), findsOneWidget);
      expect(find.byTooltip(l10nEn.idShowTooltip), findsOneWidget);
      expect(find.byTooltip(l10nEn.idCopyTooltip), findsOneWidget);
      expect(find.byTooltip(l10nEn.idShowQrTooltip), findsOneWidget);
    });

    testWidgets('Initial-loading swaps the ID for a spinner', (tester) async {
      // settle: false — the indeterminate spinner never settles.
      await pumpApp(tester, card(initialLoading: true), settle: false);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(l10nEn.idMask), findsNothing);
    });

    testWidgets('revealed state shows the raw identifier', (tester) async {
      await pumpApp(tester, card(idRevealed: true));

      expect(find.text('RAWID-0123456789'), findsOneWidget);
    });

    testWidgets('editing shows the supplied name field', (tester) async {
      await pumpApp(tester, card(editing: true));

      expect(find.byKey(const Key('edit')), findsOneWidget);
    });

    testWidgets('desktop (non-revealable): no reveal toggle, and no QR inside the card', (tester) async {
      await pumpApp(tester, card(revealable: false));

      expect(find.byTooltip(l10nEn.idShowTooltip), findsNothing);
      expect(find.byTooltip(l10nEn.idHideTooltip), findsNothing);
      // The account QR now renders as a separate block below the card (settings_root_page), not inside it.
      expect(find.byType(AppQrSurfaceWidget), findsNothing);
    });
  });
}
