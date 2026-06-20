part of 'login_bloc.dart';

/// Debug-selectable sign-in outcome (2.1, dev-only). `auto` derives new-vs-registered
/// from the mock dataset; the others force a specific path.
enum LoginOutcome { auto, newId, registered, errorFormat, errorNetwork, fatal }

/// Login form status. The `nav*` values are terminal: the page navigates on them.
enum LoginStatus { idle, loading, errorFormat, errorNetwork, navNewId, navRegistered, navFatal }

@freezed
abstract class LoginState with _$LoginState {
  const LoginState._();

  const factory LoginState({@Default('') String id, @Default(LoginStatus.idle) LoginStatus status, @Default(false) bool canPaste}) =
      _LoginState;

  bool get isLoading => status == LoginStatus.loading;

  /// `Sign in` is enabled for any non-empty input (no format validation, FR-011).
  bool get canSubmit => id.trim().isNotEmpty && status != LoginStatus.loading;

  String? get errorText => switch (status) {
    LoginStatus.errorFormat => TextConstants.loginInvalidId,
    LoginStatus.errorNetwork => TextConstants.loginNetworkError,
    _ => null,
  };
}
