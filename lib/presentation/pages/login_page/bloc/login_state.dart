part of 'login_bloc.dart';

/// Debug-selectable sign-in outcome (2.1, dev-only). `auto` derives new-vs-registered
/// from the mock dataset; the others force a specific path.
enum LoginOutcome { auto, newId, registered, errorFormat, errorNetwork, errorServerMismatch, fatal }

/// Login form status. The `nav*` values are terminal: the page navigates on them.
/// The refusals stay apart because the person's next action differs: a link
/// that will not parse means scan it again, an expired token means ask for a
/// new invite, a rejected one means this link cannot be used at all. One
/// shared "it did not work" leaves them guessing which.
enum LoginStatus {
  idle,
  loading,
  errorFormat,
  errorExpired,
  errorRejected,
  errorNetwork,

  /// The machine the link led to presented a key the link did not name, where
  /// that cannot be an accident: behind the onion address of a version-2 link,
  /// which nobody can hold without the server's keys (FR-030). Its own value
  /// rather than a shade of [errorNetwork]: nothing about the network is wrong,
  /// and telling the person to check their connection sends them after
  /// something that will never be the cause.
  errorServerMismatch,

  /// A version-1 link - a claim, or an invite the server could not put its
  /// onion address in - and its server did not answer, or a different machine
  /// answered at its address. Away from home both are what such a link is
  /// expected to meet, so this says where pairing works rather than blaming the
  /// network or the server (FR-005, FR-022).
  errorHomeNetworkOnly,
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
