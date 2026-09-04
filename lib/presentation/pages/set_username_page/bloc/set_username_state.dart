part of 'set_username_bloc.dart';

/// Debug-selectable save outcome (2.3, dev-only).
enum UsernameOutcome { success, raceTaken, fatal }

/// Set-username form status. `nav*` values are terminal (the page navigates).
/// `raceTaken` survives on the demo path only (the screens gallery drives it
/// through [UsernameOutcome]). There is no `taken`: person labels are not
/// unique (owner, 2026-09-02), so nothing can report a person's name as
/// belonging to someone else.
enum UsernameStatus { prefilled, empty, invalidCharset, checking, valid, submitting, raceTaken, navSuccess, navFatal }

@freezed
abstract class SetUsernameState with _$SetUsernameState {
  const SetUsernameState._();

  const factory SetUsernameState({@Default('') String name, @Default(UsernameStatus.prefilled) UsernameStatus status}) = _SetUsernameState;

  bool get isChecking => status == UsernameStatus.checking;

  bool get isSubmitting => status == UsernameStatus.submitting;

  /// `Done` enabled only for a valid (or the pristine prefilled) name.
  bool get canSubmit => status == UsernameStatus.valid || status == UsernameStatus.prefilled;
}
