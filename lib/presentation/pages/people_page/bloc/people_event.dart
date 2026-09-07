part of 'people_bloc.dart';

@freezed
sealed class PeopleEvent with _$PeopleEvent {
  const factory PeopleEvent.initialize() = PeopleInitialize;

  const factory PeopleEvent.inviteRequested() = PeopleInviteRequested;

  const factory PeopleEvent.inviteDismissed() = PeopleInviteDismissed;
}
