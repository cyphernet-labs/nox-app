import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/general/onboarding_mock_data.dart';
import 'package:nox_app/general/pairing/pairing_link.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';

part 'login_bloc.freezed.dart';
part 'login_event.dart';
part 'login_state.dart';

/// Login / ID-entry form state (2.1). Always-live value-state (copyWith), like
/// [AppRootState] — no init/loaded/error trio. The pairing link is READ here and
/// nothing more (phase 045): a link that will not parse, or one newer than this
/// build, is refused on this screen; a readable one goes on to the connection
/// screen, which pairs. In demo mode (gallery) the outcome is a debug stand-in.
class LoginBloc extends BaseBloc<LoginEvent, LoginState> {
  LoginBloc({this.demo = false, LoginStatus? initialStatus})
    : super(initialStatus == null ? const LoginState() : LoginState(status: initialStatus)) {
    on<IdChanged>(_onIdChanged);
    on<ClipboardChecked>(_onClipboardChecked);
    on<SignInRequested>(_onSignInRequested);
    on<NavigationHandled>(_onNavigationHandled);
  }

  /// In demo mode (gallery) the sign-in outcome is a debug stand-in and navigation
  /// is local; in the real flow a readable link goes on to the connection screen.
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
    if (demo) {
      emit(state.copyWith(status: LoginStatus.loading));
      await executeLogic(() async {
        // Debug stand-in outcome; the page navigates to a placeholder.
        await Future<void>.delayed(const Duration(milliseconds: 400));
        emit(state.copyWith(status: _resolve(event.outcome, state.id)));
      }, onError: (error, exception, stackTrace) => emit(state.copyWith(status: LoginStatus.errorNetwork)));
      return;
    }
    // Real flow: read the link, and only read it. A link that will not parse
    // means "scan it again", a newer one means "update the app" - both said
    // here, before anything dials. A readable one goes on to the connection
    // screen, where the person can see and change where it leads (phase 045).
    emit(
      state.copyWith(
        status: switch (PairingLink.refusalOf(state.id)) {
          PairingLinkError.malformed => LoginStatus.errorFormat,
          PairingLinkError.newerVersion => LoginStatus.errorNewerVersion,
          null => LoginStatus.navConnect,
        },
      ),
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
