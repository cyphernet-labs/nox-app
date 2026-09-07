part of 'people_bloc.dart';

@freezed
abstract class PeopleState with _$PeopleState {
  const PeopleState._();

  const factory PeopleState({
    @Default(true) bool loading,
    @Default(<PersonModel>[]) List<PersonModel> people,
    @Default(false) bool failed,

    /// The invite link currently on screen, or null. Held in state rather than
    /// re-fetched, because every fetch mints a new token on the server.
    String? inviteLink,
    @Default(false) bool inviteFailed,

    /// An invite is being minted. The button is disabled while it is: every
    /// press creates a 24-hour token that admits a person and cannot be taken
    /// back.
    @Default(false) bool inviting,

    /// The server said only the owner may invite. Distinct from a failure,
    /// because it means the app should not have offered this — not that it
    /// should be tried again.
    @Default(false) bool notOwner,
  }) = _PeopleState;

  /// Everyone but the person holding this device, who is shown apart: the row
  /// about oneself is the one place the owner badge is already known from
  /// Settings.
  List<PersonModel> get others => people.where((p) => !p.isSelf).toList();

  PersonModel? get self => people.where((p) => p.isSelf).firstOrNull;
}
