part of 'login_bloc.dart';

@freezed
sealed class LoginEvent with _$LoginEvent {
  /// The ID text changed (no validation — FR-011).
  const factory LoginEvent.idChanged(String id) = IdChanged;

  /// Clipboard availability checked → toggles the `Paste` action.
  const factory LoginEvent.clipboardChecked({required bool hasText}) = ClipboardChecked;

  /// `Sign in` tapped; [outcome] is the (debug) sign-in result.
  const factory LoginEvent.signInRequested({@Default(LoginOutcome.auto) LoginOutcome outcome}) = SignInRequested;

  /// The page consumed a terminal `nav*` status (navigated away) → reset to idle.
  const factory LoginEvent.navigationHandled() = NavigationHandled;
}
