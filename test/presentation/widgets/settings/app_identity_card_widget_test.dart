import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/widgets/primitives/app_ringed_avatar_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_identity_card_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_qr_surface_widget.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

const String _id = 'u_345c2e3c0845d19f';

void main() {
  AppIdentityCardWidget card({
    bool initialLoading = false,
    bool editing = false,
    String name = 'Aria',
    String rawId = _id,
    VoidCallback? onEditName,
    VoidCallback? onCopy,
  }) => AppIdentityCardWidget(
    name: name,
    rawId: rawId,
    initialLoading: initialLoading,
    editing: editing,
    onEditName: onEditName ?? () {},
    onCopy: onCopy ?? () {},
    nameEditField: editing ? const TextField(key: Key('edit')) : null,
  );

  group('AppIdentityCardWidget', () {
    testWidgets('reads as an account header: avatar, name, the whole id, two named actions', (tester) async {
      await pumpApp(tester, card());

      expect(find.byType(AppRingedAvatarWidget), findsOneWidget);
      expect(find.text('Aria'), findsOneWidget);
      // The WHOLE id. It stopped being a secret in 032, so there is no mask and
      // nothing to reveal - showing part of it would only look like there were.
      expect(find.text(_id), findsOneWidget);
      expect(find.widgetWithText(FilledButton, l10nEn.settingsEditNameAction), findsOneWidget);
      expect(find.widgetWithText(FilledButton, l10nEn.settingsCopyIdAction), findsOneWidget);
    });

    testWidgets('the id line is named for a screen reader, though nothing names it on screen', (tester) async {
      // No `Your ID` caption is drawn - the string sits under the person's own
      // name with `Copy ID` beneath it, and a caption adds nothing to the eye.
      // A screen reader without one gets forty opaque characters and no noun.
      // The semantics tree is not built unless something asks for it. Disposed
      // inside the body, not in a tearDown: the handle check runs BEFORE tearDowns.
      final semantics = tester.ensureSemantics();
      await pumpApp(tester, card());

      // Nothing on screen says `Your ID`...
      expect(find.text(l10nEn.settingsYourIdLabel), findsNothing);
      // ...but the card's semantics node does. The card merges into one node, so
      // a reader hears `A, Aria, Your ID: u_345…`; without the wrapper the third
      // part is the bare key.
      expect(tester.getSemantics(find.text(_id)).label, contains('${l10nEn.settingsYourIdLabel}: $_id'));

      semantics.dispose();
    });

    testWidgets('with no id yet: an em dash, and Copy withdrawn', (tester) async {
      // `authorId` is null until a greeting brings one - always on the mock
      // flavours, and between pairing and the first greeting on a live one.
      // Rendered bare, that is a gap that reads as a rendering fault; and an
      // enabled Copy would confirm an empty clipboard to somebody who then
      // pastes nothing.
      await pumpApp(tester, card(rawId: ''));

      expect(find.text('—'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, l10nEn.settingsCopyIdAction)).onPressed, isNull);
      // Edit name is untouched: a person has a name before they have an id.
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, l10nEn.settingsEditNameAction)).onPressed, isNotNull);
    });

    testWidgets('the actions are named, not glyphs to be guessed at', (tester) async {
      // The card carried two bare IconButtons, one per row, pinned to the far
      // right - no container to read as a button, and on the desktop pane most
      // of a pane's width from the value each acted on.
      await pumpApp(tester, card());

      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('each action calls its own callback', (tester) async {
      var edits = 0;
      var copies = 0;
      await pumpApp(tester, card(onEditName: () => edits++, onCopy: () => copies++));

      await tester.tap(find.text(l10nEn.settingsEditNameAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10nEn.settingsCopyIdAction));
      await tester.pumpAndSettle();

      expect((edits, copies), (1, 1));
    });

    testWidgets('Initial-loading swaps the ID for a spinner', (tester) async {
      // settle: false — the indeterminate spinner never settles.
      await pumpApp(tester, card(initialLoading: true), settle: false);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(_id), findsNothing);
    });

    testWidgets('editing shows the supplied name field, and withdraws Edit name', (tester) async {
      // The state that button offers to enter is the one the card is already in.
      await pumpApp(tester, card(editing: true));

      expect(find.byKey(const Key('edit')), findsOneWidget);
      expect(find.text('Aria'), findsNothing);
      expect(find.widgetWithText(FilledButton, l10nEn.settingsEditNameAction), findsNothing);
      expect(find.widgetWithText(FilledButton, l10nEn.settingsCopyIdAction), findsOneWidget);
    });

    testWidgets('a long name is not clipped - it wraps under itself, with nothing beside it', (tester) async {
      // The old regression: the name shared a Row with the edit button and was
      // laid out at a fraction of it. Nothing shares its line any more, so the
      // guard is that the name renders whole at phone width.
      const long = 'Alexandra_Smirnova_QQ';
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpApp(tester, card(name: long));

      expect(find.text(long), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no QR inside the card - pairing a device is its own screen', (tester) async {
      await pumpApp(tester, card());

      expect(find.byType(AppQrSurfaceWidget), findsNothing);
    });
  });
}
