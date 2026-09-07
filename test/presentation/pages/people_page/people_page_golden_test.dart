@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/person/person_model.dart';
import 'package:nox_app/presentation/pages/people_page/bloc/people_bloc.dart';
import 'package:nox_app/presentation/pages/people_page/people_page.dart';

import '../../../utils/golden.dart';

/// The circle comes from a server, and there is none under test, so the state
/// is seeded through the page's test seam — the same way the devices list pins
/// states the mock world cannot reach.
PeopleState _state() => const PeopleState(
  loading: false,
  people: [
    PersonModel(id: 'u_owner', label: 'Anna', isOwner: true, isSelf: true),
    PersonModel(id: 'u_guest', label: 'Boris', isOwner: false, isSelf: false),
  ],
);

void main() {
  goldenTest('people_page', () => PeoplePage(initialState: _state()));
  goldenTestDesktop('people_page', () => PeoplePage(initialState: _state()));

  // A circle of one. The sentence has to say so rather than showing a blank
  // pane — and this is the state every server sits in before the first invite.
  goldenTest('people_page_alone', () => PeoplePage(initialState: _state().copyWith(people: [_state().people.first])));
  goldenTestDesktop('people_page_alone', () => PeoplePage(initialState: _state().copyWith(people: [_state().people.first])));

  // The link on screen: the one state where the invite itself is visible.
  goldenTest('people_page_invite', () => PeoplePage(initialState: _state().copyWith(inviteLink: 'https://nox.app/p/#AQEK')));
  goldenTestDesktop('people_page_invite', () => PeoplePage(initialState: _state().copyWith(inviteLink: 'https://nox.app/p/#AQEK')));
}
