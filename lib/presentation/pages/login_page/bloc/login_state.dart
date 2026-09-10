part of 'login_bloc.dart';

/// Debug-selectable sign-in outcome (2.1, dev-only). `auto` derives new-vs-registered
/// from the mock dataset; the others force a specific path.
enum LoginOutcome { auto, newId, registered, errorFormat, errorNetwork, fatal }

/// Login form status. The `nav*` values are terminal: the page navigates on them.
/// The refusals stay apart because the person's next action differs: a link
/// that will not parse means scan it again, an expired token means ask for a
/// new invite, a rejected one means this link cannot be used at all. One
/// shared "it did not work" leaves them guessing which.
/// The refusals stay apart because each leads somewhere different: a link that
/// will not parse means "scan it again", an expired one means "get a new one",
/// and a rejected one means "this is not usable". Collapsing any two would make
/// the app tell somebody the wrong thing to do next.
enum LoginStatus { idle, loading, errorFormat, errorExpired, errorRejected, errorNetwork, navNewId, navRegistered, navFatal }

@freezed
abstract class LoginState with _$LoginState {
  const LoginState._();

  const factory LoginState({@Default('') String id, @Default(LoginStatus.idle) LoginStatus status, @Default(false) bool canPaste}) =
      _LoginState;

  bool get isLoading => status == LoginStatus.loading;

  /// `Sign in` is enabled for any non-empty input (no format validation, FR-011).
  ///
  /// Gated on [isLoading], not on `loading` alone: the owner wait is minutes
  /// long, and a button that stays live under a spinner invites a second tap.
  /// That second sign-in restarts the channel the first one is waiting on, and
  /// whichever attempt loses discards the session the other just stored.
  bool get canSubmit => id.trim().isNotEmpty && !isLoading;
}
