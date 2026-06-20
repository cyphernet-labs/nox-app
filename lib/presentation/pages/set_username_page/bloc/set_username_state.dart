part of 'set_username_bloc.dart';

/// Debug-selectable save outcome (2.3, dev-only).
enum UsernameOutcome { success, raceTaken, fatal }

/// Set-username form status. `nav*` values are terminal (the page navigates).
enum UsernameStatus { prefilled, empty, invalidCharset, checking, valid, taken, submitting, raceTaken, navSuccess, navFatal }

@freezed
abstract class SetUsernameState with _$SetUsernameState {
  const SetUsernameState._();

  const factory SetUsernameState({
    @Default('') String name,
    @Default(UsernameStatus.prefilled) UsernameStatus status,
  }) = _SetUsernameState;

  bool get isChecking => status == UsernameStatus.checking;

  bool get isSubmitting => status == UsernameStatus.submitting;

  /// `Done` enabled only for a valid (or the pristine prefilled) name.
  bool get canSubmit => status == UsernameStatus.valid || status == UsernameStatus.prefilled;

  String? get errorText => switch (status) {
    UsernameStatus.invalidCharset => TextConstants.usernameCharsetError,
    UsernameStatus.taken || UsernameStatus.raceTaken => TextConstants.nameTakenError,
    _ => null,
  };
}
