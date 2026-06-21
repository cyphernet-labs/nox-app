import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/general/username_rules.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';
import 'package:nox_app/presentation/base/bloc_transformers.dart';

part 'settings_root_bloc.freezed.dart';
part 'settings_root_event.dart';
part 'settings_root_state.dart';

/// Settings-root form state (7.1): the identity card's inline name-edit reuses the
/// exact 2.3 rules — immediate client charset validation + a debounced (~300ms),
/// CASE-SENSITIVE uniqueness check against the mock dataset — plus the masked/raw
/// identifier reveal. Identity values are stubs. Logout is handled by a
/// self-contained dialog in the page (not here). `// TODO(backend):` real identity
/// load + name persistence + uniqueness.
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

  /// Stub identifier (a long key-like string; the real anonymous identifier is
  /// server-assigned and read in the backend phase).
  static const String mockRawId = 'NOX-7c1f9a4e2b8d40f3-a6e5c2179bd0e83f-9f2a7c4e1b6d8a30';

  Future<void> _onInitialize(SettingsInitialize event, Emitter<SettingsRootState> emit) async {
    // TODO(backend): load the real identity (name + identifier). Stub: brief delay
    // so the Initial-loading state (spinner in the ID position) is observable.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    emit(state.copyWith(initialLoading: false));
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

  void _onNameSubmitted(NameSubmitted event, Emitter<SettingsRootState> emit) {
    if (!state.canSave) return;
    // TODO(backend): persist the new label. Empty drafts never reach here (canSave).
    emit(state.copyWith(name: state.draftName, editing: false, status: SettingsNameStatus.idle));
  }

  void _onNameEditCancelled(NameEditCancelled event, Emitter<SettingsRootState> emit) {
    emit(state.copyWith(editing: false, draftName: state.name, status: SettingsNameStatus.idle));
  }

  void _onIdRevealToggled(IdRevealToggled event, Emitter<SettingsRootState> emit) {
    emit(state.copyWith(idRevealed: !state.idRevealed));
  }
}
