import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/person/person_model.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/people_page/bloc/people_bloc.dart';
import 'package:nox_app/presentation/pages/people_page/people_body.dart';
import 'package:nox_app/presentation/widgets/settings/app_invite_card_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_owner_badge_widget.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

const _circle = PeopleState(
  loading: false,
  people: [
    PersonModel(id: 'u_owner', label: 'Anna', isOwner: true, isSelf: true),
    PersonModel(id: 'u_guest', label: 'Boris', isOwner: false, isSelf: false),
  ],
);

void main() {
  testWidgets('the circle names everybody and marks exactly one owner', (tester) async {
    await pumpApp(tester, const Scaffold(body: PeopleBody(initialState: _circle)));

    expect(find.text('Anna'), findsOneWidget);
    expect(find.text('Boris'), findsOneWidget);
    // One badge, on the owner's row. Two would mean the flag is being inferred
    // somewhere rather than read from the server.
    expect(find.byType(AppOwnerBadgeWidget), findsOneWidget);
    expect(find.text(l10nEn.peopleYou), findsOneWidget);
  });

  testWidgets('a circle of one says so rather than showing a blank pane', (tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: PeopleBody(initialState: _circle.copyWith(people: [_circle.people.first])),
      ),
    );

    expect(find.text(l10nEn.peopleEmpty), findsOneWidget);
    expect(find.text(l10nEn.peopleInvite), findsOneWidget);
  });

  testWidgets('the invite is shown as a QR and as text, because half the platforms have no camera', (tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: PeopleBody(initialState: _circle.copyWith(inviteLink: 'https://nox.app/p/#AQEK')),
      ),
    );

    expect(find.byType(AppInviteCardWidget), findsOneWidget);
    expect(find.text('https://nox.app/p/#AQEK'), findsOneWidget);
    // And it says how long the link lives: a day, not the device invite's ten
    // minutes.
    expect(find.text(l10nEn.peopleInviteMessage), findsOneWidget);
  });

  testWidgets('a failed invite is visible with rows already on screen, not only on an empty list', (tester) async {
    // Rendered only when the list is empty, a failure reads as a dead button on
    // every other attempt.
    await pumpApp(tester, Scaffold(body: PeopleBody(initialState: _circle.copyWith(inviteFailed: true))));

    expect(find.text(l10nEn.peopleInviteError), findsOneWidget);
    expect(find.text('Anna'), findsOneWidget);
  });
}
