import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/model/app/app_state_model.dart';
import 'package:nox_app/domain/model/app/app_state_type.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';

part 'app_root_event.dart';
part 'app_root_state.dart';
part 'app_root_bloc.freezed.dart';

/// App-level BLoC: carries the theme and drives top-level navigation from the
/// reactive [AppStateRepository]. Subscribes once on [Initialize]; each emission
/// becomes [UpdateAppState]. Two-phase apply: the first resolved state lands in
/// `lastAppState` but is NOT applied — the splash animation dispatches
/// [ApplyAppState] when it finishes; every later change applies immediately.
class AppRootBloc extends BaseBloc<AppRootEvent, AppRootState> {
  AppRootBloc() : super(AppRootState.initial()) {
    on<Initialize>(_onInitialize);
    on<SetTheme>(_onSetTheme);
    on<UpdateAppState>(_onUpdateAppState);
    on<ApplyAppState>(_onApplyAppState);
  }

  StreamSubscription<RepositoryResult<AppStateModel>>? _appStateSubscription;

  FutureOr<void> _onInitialize(Initialize event, Emitter<AppRootState> emit) async {
    _appStateSubscription ??= appStateRepository.watchAppState().listen(
      (result) => add(AppRootEvent.updateAppState(result: result)),
    );
  }

  FutureOr<void> _onSetTheme(SetTheme event, Emitter<AppRootState> emit) async {
    emit(state.copyWith(themeMode: event.themeMode));
  }

  FutureOr<void> _onUpdateAppState(UpdateAppState event, Emitter<AppRootState> emit) async {
    if (!event.result.hasData) return;
    final isNeedApply = state.isReady; // already past first boot?
    emit(state.copyWith(lastAppState: event.result.data!, isReady: true));
    // First emission (isReady was false): hold — the splash releases it via ApplyAppState.
    if (isNeedApply) add(const AppRootEvent.applyAppState());
  }

  FutureOr<void> _onApplyAppState(ApplyAppState event, Emitter<AppRootState> emit) async {
    if (state.isReady) emit(state.copyWith(appliedAppState: state.lastAppState));
  }

  @override
  Future<void> close() {
    _appStateSubscription?.cancel();
    _appStateSubscription = null;
    return super.close();
  }
}
