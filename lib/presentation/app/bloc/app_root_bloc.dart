import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/model/app/app_state_model.dart';
import 'package:nox_app/domain/model/app/app_state_type.dart';
import 'package:nox_app/domain/model/device/pair_request.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/domain/service/pair_request_service.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';

part 'app_root_event.dart';
part 'app_root_state.dart';
part 'app_root_bloc.freezed.dart';

/// App-level BLoC: carries the theme and drives top-level navigation from the
/// reactive [AppStateRepository]. Subscribes once on [Initialize]; each emission
/// becomes [UpdateAppState]. Two-phase apply: the first resolved state lands in
/// `lastAppState` but is NOT applied — the splash animation dispatches
/// [ApplyAppState] when it finishes; every later change applies immediately.
///
/// It also carries the one question the app asks over any screen (phase 046):
/// a new device that presented an invite this device issued waits for
/// `Allow` or `Deny` here, and [PairRequestService] says which requests wait.
class AppRootBloc extends BaseBloc<AppRootEvent, AppRootState> {
  AppRootBloc() : super(AppRootState.initial()) {
    on<Initialize>(_onInitialize);
    on<SetTheme>(_onSetTheme);
    on<UpdateAppState>(_onUpdateAppState);
    on<ApplyAppState>(_onApplyAppState);
    on<PairRequestsChanged>(_onPairRequestsChanged);
    on<PairRequestAnswered>(_onPairRequestAnswered);
  }

  StreamSubscription<RepositoryResult<AppStateModel>>? _appStateSubscription;
  StreamSubscription<List<PairRequest>>? _pairRequestsSubscription;

  /// Only where there is a live channel to be asked over.
  PairRequestService? get _pairRequests => getIt.isRegistered<PairRequestService>() ? getIt<PairRequestService>() : null;

  FutureOr<void> _onInitialize(Initialize event, Emitter<AppRootState> emit) async {
    // Apply the persisted theme before wiring the app-state stream (defaults to
    // system on a missing/unrecognized value — never errors).
    final theme = await settingsRepository.readThemeMode();
    theme.match<void>(
      onData: (mode) => emit(state.copyWith(themeMode: mode)),
      onError: (_) {},
    );
    _appStateSubscription ??= appStateRepository.watchAppState().listen((result) => add(AppRootEvent.updateAppState(result: result)));
    _pairRequestsSubscription ??= _pairRequests?.watchRequests().listen((requests) {
      if (!isClosed) add(AppRootEvent.pairRequestsChanged(requests));
    });
  }

  /// The oldest waiting request is the one asked about; the next one waits
  /// its turn. A new question starts clean: what was said about the last one
  /// - an answer on its way, one that failed - is over with it.
  void _onPairRequestsChanged(PairRequestsChanged event, Emitter<AppRootState> emit) {
    final head = event.requests.firstOrNull;
    if (head?.requestId == state.pairRequest?.requestId) {
      if (head != state.pairRequest) emit(state.copyWith(pairRequest: head));
      return;
    }
    emit(state.copyWith(pairRequest: head, pairAnswering: null, pairAnswerFailed: false));
  }

  /// Sends the answer. One at a time, and only to the request on screen: a
  /// second press, or a press on a dialog whose request has just closed,
  /// sends nothing. A success needs nothing here - the service drops the
  /// request, and the dialog goes with it.
  Future<void> _onPairRequestAnswered(PairRequestAnswered event, Emitter<AppRootState> emit) async {
    final service = _pairRequests;
    if (service == null || state.pairRequest?.requestId != event.requestId || state.pairAnswering != null) return;
    emit(state.copyWith(pairAnswering: event.allow, pairAnswerFailed: false));
    final result = await service.answer(requestId: event.requestId, allow: event.allow);
    // The question may be another one by now: this answer closed its own.
    if (state.pairRequest?.requestId != event.requestId) return;
    result.match<void>(
      onData: (_) => emit(state.copyWith(pairAnswering: null)),
      onError: (_) => emit(state.copyWith(pairAnswering: null, pairAnswerFailed: true)),
    );
  }

  FutureOr<void> _onSetTheme(SetTheme event, Emitter<AppRootState> emit) async {
    // Apply live (optimistic), then persist. On a save failure, revert to the prior
    // theme and bump the error tick so AppRoot shows the save-error notice.
    final previous = state.themeMode;
    emit(state.copyWith(themeMode: event.themeMode));
    final result = await settingsRepository.setThemeMode(event.themeMode);
    result.match<void>(
      onData: (_) {},
      onError: (_) => emit(state.copyWith(themeMode: previous, settingsSaveErrorTick: state.settingsSaveErrorTick + 1)),
    );
  }

  FutureOr<void> _onUpdateAppState(UpdateAppState event, Emitter<AppRootState> emit) async {
    event.result.match<void>(
      onData: (model) => _land(model, emit),
      // Never expected today (the repository emits only success). Still LAND it: log,
      // then release the splash to a safe unauthorized (Login) state — an error-first
      // emission must not stall the reveal forever (it would never set isReady).
      onError: (exception) {
        logRepository.error(target: this, error: exception);
        _land(const AppStateModel(state: AppStateType.unauthorized, session: null), emit);
      },
    );
  }

  /// Land a resolved state: record it as `lastAppState` + mark ready. HOLD the first
  /// transition (gate on whether the first state was APPLIED — `appliedAppState` still
  /// `init` — not merely on `isReady`, which this emit itself flips true; otherwise a
  /// second emission arriving during the splash-hold window would escape the gate and
  /// navigate mid-reveal). Every later change applies immediately.
  void _land(AppStateModel model, Emitter<AppRootState> emit) {
    final alreadyApplied = state.appliedAppState.state != AppStateType.init;
    emit(state.copyWith(lastAppState: model, isReady: true));
    if (alreadyApplied) add(const AppRootEvent.applyAppState());
  }

  FutureOr<void> _onApplyAppState(ApplyAppState event, Emitter<AppRootState> emit) async {
    if (state.isReady) emit(state.copyWith(appliedAppState: state.lastAppState));
  }

  @override
  Future<void> close() {
    _appStateSubscription?.cancel();
    _appStateSubscription = null;
    _pairRequestsSubscription?.cancel();
    _pairRequestsSubscription = null;
    return super.close();
  }
}
