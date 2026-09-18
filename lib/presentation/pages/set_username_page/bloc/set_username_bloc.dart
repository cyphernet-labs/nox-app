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

/// Set-username form (2.3). Client charset validation is immediate; a name is never
/// refused as taken (labels are not unique). The field opens on the name the SERVER
/// assigned, read from the session - see [_onPrefillRequested].
class SetUsernameBloc extends BaseBloc<SetUsernameEvent, SetUsernameState> {
  SetUsernameBloc({String? initialName, bool demo = false})
    : demo = demo,
      super(
        SetUsernameState(
          name: initialName ?? (demo ? defaultName : ''),
          status: (initialName ?? (demo ? defaultName : '')).isEmpty ? UsernameStatus.empty : UsernameStatus.prefilled,
        ),
      ) {
    on<NameChanged>(_onNameChanged);
    on<PrefillRequested>(_onPrefillRequested);
    on<DoneRequested>(_onDoneRequested);
    on<SkipRequested>(_onSkipRequested);
    on<NavigationHandled>(_onNavigationHandled);
    // The real screen asks the session who the server says this person is. Until
    // now it opened on a constant compiled into the client, which named anyone who
    // pressed Done without editing the field.
    if (!demo && initialName == null) add(const SetUsernameEvent.prefillRequested());
  }

  /// In demo mode (gallery) the save outcome is a debug stand-in and navigation is
  /// local; in the real flow it marks onboarding complete via [AuthRepository] and
  /// the app-state spine drives navigation to the shell.
  final bool demo;

  void _onNavigationHandled(NavigationHandled event, Emitter<SetUsernameState> emit) {
    emit(state.copyWith(status: UsernameStatus.valid));
  }

  /// The gallery preview's placeholder name, and the fallback label the shell and
  /// Settings fall back to. NOT a prefill for the real screen: [_onPrefillRequested]
  /// reads that from the session, where the server put it.
  static const String defaultName = Constants.defaultUserLabel;

  /// Fills the field with the name the server assigned at the first greeting, which
  /// `adoptServerIdentity` cached in the session. Nothing is invented: with no cached
  /// label the field simply opens empty, and `Skip` still keeps whatever the server
  /// holds. A person who starts typing before the read returns keeps what they typed.
  Future<void> _onPrefillRequested(PrefillRequested event, Emitter<SetUsernameState> emit) async {
    if (state.name.isNotEmpty) return;
    final result = await sessionRepository.readSession();
    final label = result.match<String?>(onData: (session) => session?.label, onError: (_) => null);
    if (label == null || label.isEmpty || state.name.isNotEmpty) return;
    emit(state.copyWith(name: label, status: UsernameStatus.prefilled));
  }

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
