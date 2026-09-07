import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/widgets/settings/app_identity_card_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_qr_surface_widget.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  AppIdentityCardWidget card({
    bool revealable = true,
    bool initialLoading = false,
    bool editing = false,
    bool idRevealed = false,
    bool? isOwner,
    String name = 'Aria',
  }) => AppIdentityCardWidget(
    isOwner: isOwner,
    name: name,
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

    testWidgets('the owner badge appears only when the server said this person owns it', (tester) async {
      await pumpApp(tester, card(isOwner: true));
      expect(find.text(l10nEn.settingsOwnerBadge), findsOneWidget);
    });

    testWidgets('somebody who does not own the server gets no badge', (tester) async {
      await pumpApp(tester, card(isOwner: false));
      expect(find.text(l10nEn.settingsOwnerBadge), findsNothing);
    });

    testWidgets('an unstated answer draws nothing, exactly like a no', (tester) async {
      // Same pixels, different meaning. Drawing "not the owner" before the
      // server has answered would be a claim the app cannot make, followed by
      // a flicker when the greeting corrects it - so both draw nothing, and
      // the distinction lives in the data.
      await pumpApp(tester, card());
      expect(find.text(l10nEn.settingsOwnerBadge), findsNothing);
    });

    testWidgets('a long name keeps its width, with and without the badge', (tester) async {
      // The regression this pins: a Row of two flexible children splits the
      // free space by flex, so the name was laid out at HALF the row and
      // ellipsized with blank space beside it - for everyone, badge or not.
      const long = 'Alexandra_Smirnova_QQ';
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpApp(tester, card(name: long));
      final plain = tester.getSize(find.text(long)).width;

      await pumpApp(tester, card(name: long, isOwner: true));
      final withBadge = tester.getSize(find.text(long)).width;

      // The name renders at its natural width, not at a fraction of the row.
      expect(plain, greaterThan(150));
      expect(withBadge, plain, reason: 'the badge must not steal width from the name');
    });

    testWidgets('the badge moves to its own line instead of crushing the name', (tester) async {
      // Doubled text scale on a narrow phone is the accessibility floor the
      // project already tests to, and it leaves no room for the name and the
      // badge on one row. `pumpApp` pins the English locale, so this is the
      // SHORTER of the two strings - the Ukrainian one only makes it tighter.
      const long = 'Alexandra_Smirnova_QQ';
      await tester.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpApp(tester, card(name: long, isOwner: true), textScale: 2);
      expect(tester.takeException(), isNull);

      // Asserted by POSITION, not by presence: both widgets are on screen in
      // the broken layout too - a Row of two flexible children keeps them side
      // by side and silently squeezes the name to an ellipsis. Only the y
      // offset tells the two apart.
      final nameTop = tester.getTopLeft(find.text(long)).dy;
      final badgeTop = tester.getTopLeft(find.text(l10nEn.settingsOwnerBadge)).dy;
      expect(badgeTop, greaterThan(nameTop), reason: 'the badge should have wrapped below the name');
    });

    testWidgets('the badge survives an inline rename', (tester) async {
      // Ownership has nothing to do with editing a name. While the editing
      // branch returned the field alone, the badge blinked out on every rename.
      await pumpApp(tester, card(isOwner: true, editing: true));

      expect(find.byKey(const Key('edit')), findsOneWidget);
      expect(find.text(l10nEn.settingsOwnerBadge), findsOneWidget);
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
