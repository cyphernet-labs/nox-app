import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';

part 'app_root_event.dart';
part 'app_root_state.dart';
part 'app_root_bloc.freezed.dart';

/// App-level state: one concrete state with copyWith (NOT a trio) — it is always
/// "live", carrying themeMode from start. Themes are static AppTheme.light()/dark().
class AppRootBloc extends BaseBloc<AppRootEvent, AppRootState> {
  AppRootBloc() : super(const AppRootState(themeMode: ThemeMode.system)) {
    on<Initialize>(_onInitialize);
    on<SetTheme>(_onSetTheme);
  }

  FutureOr<void> _onInitialize(Initialize event, Emitter<AppRootState> emit) async {
    // Hook for global startup (e.g. load a persisted themeMode).
  }

  FutureOr<void> _onSetTheme(SetTheme event, Emitter<AppRootState> emit) async {
    emit(state.copyWith(themeMode: event.themeMode));
  }
}
