part of 'login_bloc.dart';

/// Debug-selectable sign-in outcome (2.1, dev-only). `auto` derives new-vs-registered
/// from the mock dataset; the others force a specific path.
enum LoginOutcome { auto, newId, registered, errorFormat, errorNetwork, fatal }

/// Login form status. The `nav*` values are terminal: the page navigates on them.
/// The two refusals this screen still makes stay apart because the person's
/// next action differs: a link that will not parse means scan it again, a link
/// from a newer server means update the app. Everything about the server - an
/// expired or rejected token, a server out of reach - is the connection
/// screen's to say since phase 045.
enum LoginStatus {
  idle,

  /// Demo mode only: the debug stand-in outcome is on its way.
  loading,
  errorFormat,

  /// A pairing link of a version this build does not read (phase 044,
  /// FR-017). Not [errorFormat]: the link is fine, the app is old - scanning
  /// it again would meet the same answer, and only an update helps.
  errorNewerVersion,

  /// Demo mode only: the debug stand-in's network failure.
  errorNetwork,

  /// A readable link: on to the connection screen (phase 045).
  navConnect,
  navNewId,
  navRegistered,
  navFatal,
}

@freezed
abstract class LoginState with _$LoginState {
  const LoginState._();

  const factory LoginState({@Default('') String id, @Default(LoginStatus.idle) LoginStatus status, @Default(false) bool canPaste}) =
      _LoginState;

  bool get isLoading => status == LoginStatus.loading;

  /// `Sign in` is enabled for any non-empty input (no format validation, FR-011).
  ///
  /// Gated on [isLoading]: a button that stays live under a spinner invites a
  /// second tap. That second sign-in restarts the channel the first is on, and
  /// whichever attempt loses discards the session the other just stored.
  bool get canSubmit => id.trim().isNotEmpty && !isLoading;
}
