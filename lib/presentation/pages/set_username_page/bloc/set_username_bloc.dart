import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/username_rules.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';

part 'set_username_bloc.freezed.dart';
part 'set_username_event.dart';
part 'set_username_state.dart';

/// Set-username form (2.3). Client charset validation is immediate; the uniqueness
/// check is debounced (~300ms) and CASE-SENSITIVE against the mock dataset. The
/// field is pre-filled with the server-assigned `User<random>` (a stub here).
/// `// TODO(backend): real uniqueness + save.`
class SetUsernameBloc extends BaseBloc<SetUsernameEvent, SetUsernameState> {
  SetUsernameBloc({String initialName = defaultName, this.demo = false})
    : super(SetUsernameState(name: initialName, status: UsernameStatus.prefilled)) {
    on<NameChanged>(_onNameChanged);
    on<DoneRequested>(_onDoneRequested);
    on<SkipRequested>(_onSkipRequested);
    on<NavigationHandled>(_onNavigationHandled);
  }

  /// In demo mode (gallery) the save outcome is a debug stand-in and navigation is
  /// local; in the real flow it marks onboarding complete via [AuthRepository] and
  /// the app-state spine drives navigation to the shell.
  final bool demo;

  void _onNavigationHandled(NavigationHandled event, Emitter<SetUsernameState> emit) {
    emit(state.copyWith(status: UsernameStatus.valid));
  }

  /// Stand-in for the server-assigned default name. Single source:
  /// [Constants.defaultUserLabel] (shared with the shell + Settings).
  static const String defaultName = Constants.defaultUserLabel;

  void _onNameChanged(NameChanged event, Emitter<SetUsernameState> emit) {
    final name = event.name;
    if (name.isEmpty) {
      emit(state.copyWith(name: name, status: UsernameStatus.empty));
      return;
    }
    if (!UsernameRules.hasValidCharset(name)) {
      emit(state.copyWith(name: name, status: UsernameStatus.invalidCharset));
      return;
    }
    // Decided here and now. There is nobody to ask: person labels are not
    // unique (owner, 2026-09-02), the server neither enforces nor reports it,
    // and charset and length are local rules that have just been applied. What
    // used to follow was a debounced 200ms wait and a lookup in four hardcoded
    // strings - a spinner animating a check nothing performed.
    emit(state.copyWith(name: name, status: UsernameStatus.valid));
  }

  Future<void> _onDoneRequested(DoneRequested event, Emitter<SetUsernameState> emit) async {
    if (!state.canSubmit) return;
    emit(state.copyWith(status: UsernameStatus.submitting));
    if (demo) {
      await executeLogic(() async {
        // Debug stand-in outcome; the page navigates to a placeholder.
        await Future<void>.delayed(const Duration(milliseconds: 400));
        emit(state.copyWith(status: _statusFor(event.outcome)));
      }, onError: (error, exception, stackTrace) => emit(state.copyWith(status: UsernameStatus.navFatal)));
      return;
    }
    // Real flow: mark onboarding complete (caching the chosen label); the spine
    // navigates to the shell (authorized). completeOnboarding returns a
    // RepositoryResult (never throws), so no executeLogic wrapper.
    final result = await authRepository.completeOnboarding(label: state.name);
    result.match<void>(
      onData: (_) => emit(state.copyWith(status: UsernameStatus.valid)),
      onError: (_) => emit(state.copyWith(status: UsernameStatus.navFatal)),
    );
  }

  /// `Skip` keeps the server-assigned name (no `canSubmit` gate) but shares the
  /// `submitting` state with `Done`, so the re-entry / concurrent-with-Done guard is
  /// the same single `isSubmitting` flag (no widget-local bool).
  Future<void> _onSkipRequested(SkipRequested event, Emitter<SetUsernameState> emit) async {
    if (state.isSubmitting) return;
    emit(state.copyWith(status: UsernameStatus.submitting));
    if (demo) {
      await executeLogic(() async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        emit(state.copyWith(status: UsernameStatus.navSuccess));
      }, onError: (error, exception, stackTrace) => emit(state.copyWith(status: UsernameStatus.navFatal)));
      return;
    }
    // Real flow: mark onboarding complete (keep the current name); the spine navigates.
    final result = await authRepository.completeOnboarding();
    result.match<void>(
      onData: (_) => emit(state.copyWith(status: UsernameStatus.valid)),
      onError: (_) => emit(state.copyWith(status: UsernameStatus.navFatal)),
    );
  }

  UsernameStatus _statusFor(UsernameOutcome outcome) => switch (outcome) {
    UsernameOutcome.success => UsernameStatus.navSuccess,
    UsernameOutcome.raceTaken => UsernameStatus.raceTaken,
    UsernameOutcome.fatal => UsernameStatus.navFatal,
  };
}
