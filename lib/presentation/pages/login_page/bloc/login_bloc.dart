import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';
import 'package:nox_app/general/onboarding_mock_data.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';

part 'login_bloc.freezed.dart';
part 'login_event.dart';
part 'login_state.dart';

/// Login / ID-entry form state (2.1). Always-live value-state (copyWith), like
/// [AppRootState] — no init/loaded/error trio. There is NO client-side format
/// validation of the ID (FR-011); the sign-in outcome is stubbed via a debug
/// selector + the mock dataset (UI-only). `// TODO(backend): real sign-in.`
class LoginBloc extends BaseBloc<LoginEvent, LoginState> {
  LoginBloc({this.demo = false, LoginStatus? initialStatus})
    : super(initialStatus == null ? const LoginState() : LoginState(status: initialStatus)) {
    on<IdChanged>(_onIdChanged);
    on<ClipboardChecked>(_onClipboardChecked);
    on<SignInRequested>(_onSignInRequested);
    on<NavigationHandled>(_onNavigationHandled);
    on<ServerRefused>(_onServerRefused);
    // Watched from here rather than read from the sign-in result: the pin is
    // checked during the TLS handshake, which happens before `pair` goes out -
    // so the repository can only report that there was no channel, and the
    // person would be told to check a connection that is working perfectly.
    _phaseSub = _phaseService.watchPhase().listen((phase) {
      if (phase.isServerMismatch) add(const LoginEvent.serverRefused());
    });
  }

  final SessionPhaseService _phaseService = getIt<SessionPhaseService>();

  StreamSubscription<SessionPhase>? _phaseSub;

  @override
  Future<void> close() {
    _phaseSub?.cancel();
    return super.close();
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

  /// Shown even when nothing is in flight: a refusal that arrives while the
  /// person is still typing is about the link they just pasted, and hiding it
  /// until they press the button again would let them press it into the same
  /// wall twice.
  void _onServerRefused(ServerRefused event, Emitter<LoginState> emit) {
    emit(state.copyWith(status: LoginStatus.errorServerMismatch));
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
      onError: (e) => emit(state.copyWith(status: _statusFor(e, refused: _refusedServer()))),
    );
  }

  /// Whether the channel refused the machine the link named.
  ///
  /// Asked at the moment the sign-in result is mapped, and asked two ways,
  /// because the refusal and the failure are two different events and either
  /// can land first: the phase may already say so, or the event carrying it may
  /// already have moved this screen.
  bool _refusedServer() => _phaseService.phase.isServerMismatch || state.status == LoginStatus.errorServerMismatch;

  /// Each refusal keeps its own message: the repository already told them
  /// apart, and collapsing them here would undo that.
  ///
  /// [refused] outranks everything. A pin refusal happens inside the TLS
  /// handshake, BEFORE `pair` goes out, so the only thing sign-in can report is
  /// that there was no channel — `connection`. Mapping that to "check your
  /// connection" sends the person after a network that is working perfectly,
  /// which is the precise confusion this feature exists to remove, and it made
  /// the honest message unreachable outside the debug gallery.
  static LoginStatus _statusFor(Object? exception, {required bool refused}) {
    if (refused) return LoginStatus.errorServerMismatch;
    return switch (exception) {
      RepositoryException.invalidRequest => LoginStatus.errorFormat,
      RepositoryException.notFound => LoginStatus.errorExpired,
      RepositoryException.authentication => LoginStatus.errorRejected,
      RepositoryException.internal => LoginStatus.errorNetwork,
      _ => LoginStatus.errorNetwork,
    };
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
      LoginOutcome.errorServerMismatch => LoginStatus.errorServerMismatch,
      LoginOutcome.fatal => LoginStatus.navFatal,
      LoginOutcome.auto => LoginStatus.navNewId,
    };
  }
}
