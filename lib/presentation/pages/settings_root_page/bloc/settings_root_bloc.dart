import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/identity/identity_resolver.dart';
import 'package:nox_app/general/username_rules.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';
import 'package:nox_app/presentation/base/bloc_transformers.dart';

part 'settings_root_bloc.freezed.dart';
part 'settings_root_event.dart';
part 'settings_root_state.dart';

/// Settings-root form state (7.1): the identity card's inline name-edit reuses the
/// exact 2.3 rules — immediate client charset validation + a debounced (~300ms),
/// CASE-SENSITIVE uniqueness check against the mock dataset — plus the masked/raw
/// identifier reveal. The display label is loaded from and persisted to the local
/// session (feature 015); the uniqueness check is still mock-dataset-backed. Logout
/// is handled by a self-contained dialog in the page (not here). `// TODO(backend):`
/// real server uniqueness check.
class SettingsRootBloc extends BaseBloc<SettingsRootEvent, SettingsRootState> {
  SettingsRootBloc() : super(const SettingsRootState()) {
    on<SettingsInitialize>(_onInitialize);
    on<NameEditStarted>(_onNameEditStarted);
    on<SettingsNameChanged>(_onNameChanged);
    on<SettingsAvailabilityRequested>(_onAvailabilityRequested, transformer: debounceRestartable());
    on<NameSubmitted>(_onNameSubmitted);
    on<NameEditCancelled>(_onNameEditCancelled);
    on<IdRevealToggled>(_onIdRevealToggled);
  }

  Future<void> _onInitialize(SettingsInitialize event, Emitter<SettingsRootState> emit) async {
    // Load the user's own identifier for Show QR (FR-014) from the 009 session spine.
    // Empty/error never fabricates a fake id (that would flow into a real scannable
    // QR) — it degrades to an empty rawId. Settings is authorized-only, so the id is
    // normally present. TODO(backend): also load the real name when the identity
    // endpoint lands.
    final result = await sessionRepository.readSession();
    result.match<void>(
      // Load the real display label from the session (feature 015); a missing/empty
      // label degrades to the default via resolveIdentity, matching the state default.
      onData: (session) =>
          emit(state.copyWith(initialLoading: false, rawId: session?.identifier ?? '', name: resolveIdentity(session).label)),
      onError: (_) => emit(state.copyWith(initialLoading: false, rawId: '')),
    );
  }

  void _onNameEditStarted(NameEditStarted event, Emitter<SettingsRootState> emit) {
    emit(state.copyWith(editing: true, draftName: state.name, status: SettingsNameStatus.valid));
  }

  void _onNameChanged(SettingsNameChanged event, Emitter<SettingsRootState> emit) {
    final name = event.name;
    if (name == state.name) {
      // Unchanged keeps the current (always-valid) name.
      emit(state.copyWith(draftName: name, status: SettingsNameStatus.valid));
      return;
    }
    if (name.isEmpty) {
      // The label can't be cleared → not committable, no error shown.
      emit(state.copyWith(draftName: name, status: SettingsNameStatus.idle));
      return;
    }
    if (!UsernameRules.hasValidCharset(name)) {
      emit(state.copyWith(draftName: name, status: SettingsNameStatus.invalidCharset));
      return;
    }
    emit(state.copyWith(draftName: name, status: SettingsNameStatus.checking));
    add(SettingsRootEvent.availabilityRequested(name));
  }

  Future<void> _onAvailabilityRequested(SettingsAvailabilityRequested event, Emitter<SettingsRootState> emit) async {
    if (state.draftName != event.name || state.status != SettingsNameStatus.checking) return;
    await executeLogic(() async {
      // TODO(backend): real server uniqueness check.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (state.draftName != event.name) return;
      final taken = UsernameRules.isTaken(event.name); // case-sensitive (FR-032)
      emit(state.copyWith(status: taken ? SettingsNameStatus.taken : SettingsNameStatus.valid));
      // Fail-safe: a failed uniqueness check must NOT report the name as available
      // (would let a possibly-taken label be committed). Fall back to a neutral,
      // non-committable state so the user re-checks. `// TODO(backend):` retry UX.
    }, onError: (error, exception, stackTrace) => emit(state.copyWith(status: SettingsNameStatus.idle)));
  }

  Future<void> _onNameSubmitted(NameSubmitted event, Emitter<SettingsRootState> emit) async {
    if (!state.canSave) return;
    // Persist the validated new label to the session (feature 015). Empty/invalid/taken
    // drafts never reach here (canSave). The write broadcasts on watchLabel so live
    // surfaces (desktop rail avatar) update without a restart.
    final draft = state.draftName;
    final result = await sessionRepository.updateLabel(label: draft);
    result.match<void>(
      onData: (_) => emit(state.copyWith(name: draft, editing: false, status: SettingsNameStatus.idle)),
      // Keep the edit open on a persistence failure — never show a saved name that
      // did not persist. The mock store never errors; defensive only.
      onError: (_) {},
    );
  }

  void _onNameEditCancelled(NameEditCancelled event, Emitter<SettingsRootState> emit) {
    emit(state.copyWith(editing: false, draftName: state.name, status: SettingsNameStatus.idle));
  }

  void _onIdRevealToggled(IdRevealToggled event, Emitter<SettingsRootState> emit) {
    emit(state.copyWith(idRevealed: !state.idRevealed));
  }
}
