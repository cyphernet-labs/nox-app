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

  /// The channel was refused as the wrong server while what is in the field
  /// is no usable link - nothing it says can be about a road the link took.
  /// Its own value rather than a shade of [errorNetwork]: nothing about the
  /// network is wrong, and telling the person to check their connection sends
  /// them after something that will never be the cause.
  errorServerMismatch,

  /// A link whose server did not answer, or where a different machine
  /// answered at its address. Until phase 045 every link pairs only at home,
  /// over its direct addresses (FR-019); away from home both are what a link
  /// is expected to meet, so this says where pairing works rather than blaming
  /// the network or the server.
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
