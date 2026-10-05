import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/connection/connection_status.dart';
import 'package:nox_app/domain/service/connection_status_service.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';

part 'connection_indicator_bloc.freezed.dart';
part 'connection_indicator_event.dart';
part 'connection_indicator_state.dart';

/// The corner of the screen that says how the connection goes (phase 040,
/// FR-027): only deviations from the usual - the `Tor` badge, `Connecting…`.
///
/// Follows [ConnectionStatusService] and nothing else, so the corner and the
/// banners can never disagree about where the connection stands.
class ConnectionIndicatorBloc extends BaseBloc<ConnectionIndicatorEvent, ConnectionIndicatorState> {
  ConnectionIndicatorBloc() : super(ConnectionIndicatorState(status: getIt<ConnectionStatusService>().status)) {
    on<Started>(_onStarted);
    on<StatusChanged>(_onStatusChanged);
  }

  StreamSubscription<ConnectionStatus>? _statusSub;

  void _onStarted(Started event, Emitter<ConnectionIndicatorState> emit) {
    _statusSub ??= getIt<ConnectionStatusService>().watchStatus().listen((status) => add(ConnectionIndicatorEvent.statusChanged(status)));
  }

  void _onStatusChanged(StatusChanged event, Emitter<ConnectionIndicatorState> emit) => emit(state.copyWith(status: event.status));

  @override
  Future<void> close() {
    _statusSub?.cancel();
    return super.close();
  }
}
