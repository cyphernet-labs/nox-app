import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/repository/device/device_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/identity/identity_resolver.dart';
import 'package:nox_app/general/username_rules.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';

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
    on<NameSubmitted>(_onNameSubmitted);
    on<NameEditCancelled>(_onNameEditCancelled);
    on<IdRevealToggled>(_onIdRevealToggled);
  }

  Future<void> _onInitialize(SettingsInitialize event, Emitter<SettingsRootState> emit) async {
    // Load the user's own identifier for Show QR (FR-014) + the display label (7.1)
    // from the 009 session spine. Empty/error never fabricates a fake id (that would
    // flow into a real scannable QR) — it degrades to an empty rawId; the label
    // degrades to the default via resolveIdentity. Settings is authorized-only, so the
    // id/label are normally present.
    final result = await sessionRepository.readSession();
    result.match<void>(
      // Load the real display label from the session (feature 015); a missing/empty
      // label degrades to the default via resolveIdentity, matching the state default.
      onData: (session) =>
          // The public author id, not a secret. The login identifier this used
          // to show no longer exists: a person is recognised by a paired key,
          // so there is nothing here worth hiding behind a reveal.
          // The SERVER-minted id only. resolveIdentity falls back to the login
          // identifier, whose slot now holds the pairing TOKEN - showing that
          // as "Your ID" would put a credential on screen and in the clipboard.
          emit(state.copyWith(initialLoading: false, rawId: session?.authorId ?? '', name: resolveIdentity(session).label)),
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
    // Decided here: there is no availability to check. Person labels are not
    // unique (owner, 2026-09-02), so charset and length - already applied
    // above - are the whole rule. The debounced handler this used to schedule
    // waited 200ms and compared against four hardcoded strings.
    emit(state.copyWith(draftName: name, status: SettingsNameStatus.valid));
  }

  Future<void> _onNameSubmitted(NameSubmitted event, Emitter<SettingsRootState> emit) async {
    if (!state.canSave) return;
    final draft = state.draftName;

    // The SERVER first. Persisting locally and then telling it would show a
    // saved name that the next greeting silently reverts - and reverting from
    // the already-updated state re-showed the very name that failed, which is
    // how the previous attempt at this was ineffective.
    final devices = getIt.isRegistered<DeviceRepository>() ? getIt<DeviceRepository>() : null;
    if (devices != null) {
      final sent = await devices.setLabel(label: draft);
      if (!sent.hasData) {
        // Keep the edit open on the OLD name. Nothing was saved anywhere, so
        // nothing is claimed.
        emit(state.copyWith(draftName: state.name, editing: true, status: SettingsNameStatus.idle));
        return;
      }
    }

    // Only now is it true. The write broadcasts on watchLabel so live surfaces
    // (desktop rail avatar) update without a restart.
    final result = await sessionRepository.updateLabel(label: draft);
    result.match<void>(
      onData: (_) => emit(state.copyWith(name: draft, editing: false, status: SettingsNameStatus.idle)),
      // Keep the edit open on a persistence failure - never show a saved name
      // that did not persist.
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
