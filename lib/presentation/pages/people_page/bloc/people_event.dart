part of 'people_bloc.dart';

@freezed
sealed class PeopleEvent with _$PeopleEvent {
  const factory PeopleEvent.initialize() = PeopleInitialize;

  const factory PeopleEvent.inviteRequested() = PeopleInviteRequested;

  const factory PeopleEvent.inviteDismissed() = PeopleInviteDismissed;

  /// A question was answered somewhere: the circle may have grown, and the
  /// invite on screen is spent either way.
  const factory PeopleEvent.questionSettled() = PeopleQuestionSettled;
}
