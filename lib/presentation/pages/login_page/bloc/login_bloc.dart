import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/general/onboarding_mock_data.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';

part 'login_bloc.freezed.dart';
part 'login_event.dart';
part 'login_state.dart';

/// Login / ID-entry form state (2.1). Always-live value-state (copyWith), like
/// [AppRootState] — no init/loaded/error trio. There is NO client-side format
/// validation of the ID (FR-011); the sign-in outcome is stubbed via a debug
/// selector + the mock dataset (UI-only). `// TODO(backend): real sign-in.`
class LoginBloc extends BaseBloc<LoginEvent, LoginState> {
  LoginBloc({this.demo = false}) : super(const LoginState()) {
    on<IdChanged>(_onIdChanged);
    on<ClipboardChecked>(_onClipboardChecked);
    on<SignInRequested>(_onSignInRequested);
    on<NavigationHandled>(_onNavigationHandled);
  }

  /// In demo mode (gallery) the sign-in outcome is a debug stand-in and navigation
  /// is local; in the real flow it persists the identifier via [AuthRepository] and
  /// the app-state spine drives navigation.
  final bool demo;

  void _onIdChanged(IdChanged event, Emitter<LoginState> emit) {
    // Editing clears any inline error.
    emit(state.copyWith(id: event.id, status: LoginStatus.idle));
  }

  void _onClipboardChecked(ClipboardChecked event, Emitter<LoginState> emit) {
    emit(state.copyWith(canPaste: event.hasText));
  }

  void _onNavigationHandled(NavigationHandled event, Emitter<LoginState> emit) {
    emit(state.copyWith(status: LoginStatus.idle));
  }

  Future<void> _onSignInRequested(SignInRequested event, Emitter<LoginState> emit) async {
    if (!state.canSubmit) return;
    emit(state.copyWith(status: LoginStatus.loading));
    if (demo) {
      await executeLogic(() async {
        // Debug stand-in outcome; the page navigates to a placeholder.
        await Future<void>.delayed(const Duration(milliseconds: 400));
        emit(state.copyWith(status: _resolve(event.outcome, state.id)));
      }, onError: (error, exception, stackTrace) => emit(state.copyWith(status: LoginStatus.errorNetwork)));
      return;
    }
    // Real flow: persist the identifier + re-derive app state; the spine navigates
    // (new id → Set username, registered id → Chats). No client-side validation (FR-011).
    // signIn returns a RepositoryResult (never throws), so no executeLogic wrapper.
    final result = await authRepository.signIn(identifier: state.id);
    result.match<void>(
      onData: (_) => emit(state.copyWith(status: LoginStatus.idle)),
      onError: (_) => emit(state.copyWith(status: LoginStatus.errorNetwork)),
    );
  }

  /// Maps the (debug) outcome to a terminal status. `auto` derives new-vs-registered
  /// from the mock dataset so typing a known id reproduces the registered path.
  LoginStatus _resolve(LoginOutcome outcome, String id) {
    final effective = outcome == LoginOutcome.auto
        ? (OnboardingMockData.registeredIds.contains(id.trim()) ? LoginOutcome.registered : LoginOutcome.newId)
        : outcome;
    return switch (effective) {
      LoginOutcome.newId => LoginStatus.navNewId,
      LoginOutcome.registered => LoginStatus.navRegistered,
      LoginOutcome.errorFormat => LoginStatus.errorFormat,
      LoginOutcome.errorNetwork => LoginStatus.errorNetwork,
      LoginOutcome.fatal => LoginStatus.navFatal,
      LoginOutcome.auto => LoginStatus.navNewId,
    };
  }
}
