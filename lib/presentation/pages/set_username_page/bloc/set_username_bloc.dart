import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/general/onboarding_mock_data.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';
import 'package:nox_app/presentation/base/bloc_transformers.dart';

part 'set_username_bloc.freezed.dart';
part 'set_username_event.dart';
part 'set_username_state.dart';

/// Set-username form (2.3). Client charset validation is immediate; the uniqueness
/// check is debounced (~300ms) and CASE-SENSITIVE against the mock dataset. The
/// field is pre-filled with the server-assigned `User<random>` (a stub here).
/// `// TODO(backend): real uniqueness + save.`
class SetUsernameBloc extends BaseBloc<SetUsernameEvent, SetUsernameState> {
  SetUsernameBloc({String initialName = defaultName})
    : super(SetUsernameState(name: initialName, status: UsernameStatus.prefilled)) {
    on<NameChanged>(_onNameChanged);
    on<AvailabilityRequested>(_onAvailabilityRequested, transformer: debounceRestartable());
    on<DoneRequested>(_onDoneRequested);
  }

  /// Stub for the server-assigned default name (must NOT collide with the mock
  /// taken set, since the user's current name is always free to keep).
  static const String defaultName = 'User7421';

  static final RegExp _charset = RegExp(r'^[A-Za-z0-9._-]+$');

  void _onNameChanged(NameChanged event, Emitter<SetUsernameState> emit) {
    final name = event.name;
    if (name.isEmpty) {
      emit(state.copyWith(name: name, status: UsernameStatus.empty));
      return;
    }
    if (!_charset.hasMatch(name)) {
      emit(state.copyWith(name: name, status: UsernameStatus.invalidCharset));
      return;
    }
    emit(state.copyWith(name: name, status: UsernameStatus.checking));
    add(SetUsernameEvent.availabilityRequested(name));
  }

  Future<void> _onAvailabilityRequested(AvailabilityRequested event, Emitter<SetUsernameState> emit) async {
    // Drop stale checks (the user kept typing); switchMap already cancels the prior run.
    if (state.name != event.name || state.status != UsernameStatus.checking) return;
    await executeLogic(
      () async {
        // TODO(backend): real server uniqueness check.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (state.name != event.name) return;
        final taken = OnboardingMockData.takenUsernames.contains(event.name); // case-sensitive (FR-032)
        emit(state.copyWith(status: taken ? UsernameStatus.taken : UsernameStatus.valid));
      },
      onError: (error, exception, stackTrace) => emit(state.copyWith(status: UsernameStatus.valid)),
    );
  }

  Future<void> _onDoneRequested(DoneRequested event, Emitter<SetUsernameState> emit) async {
    if (!state.canSubmit) return;
    emit(state.copyWith(status: UsernameStatus.submitting));
    await executeLogic(
      () async {
        // TODO(backend): real save; the outcome is a debug stand-in.
        await Future<void>.delayed(const Duration(milliseconds: 400));
        emit(state.copyWith(status: _statusFor(event.outcome)));
      },
      onError: (error, exception, stackTrace) => emit(state.copyWith(status: UsernameStatus.navFatal)),
    );
  }

  UsernameStatus _statusFor(UsernameOutcome outcome) => switch (outcome) {
    UsernameOutcome.success => UsernameStatus.navSuccess,
    UsernameOutcome.raceTaken => UsernameStatus.raceTaken,
    UsernameOutcome.fatal => UsernameStatus.navFatal,
  };
}
