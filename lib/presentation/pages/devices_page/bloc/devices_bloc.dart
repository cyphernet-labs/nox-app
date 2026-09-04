import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/device/device_model.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/domain/repository/device/device_repository.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';

part 'devices_bloc.freezed.dart';
part 'devices_event.dart';
part 'devices_state.dart';

/// 7.3 Devices — the list of keys allowed to speak as this person, and the way
/// to cut one off.
///
/// Always read from the server, never from a cache: a stale list would offer to
/// revoke a device that is already gone and hide one added from elsewhere.
class DevicesBloc extends BaseBloc<DevicesEvent, DevicesState> {
  DevicesBloc() : super(const DevicesState()) {
    on<DevicesInitialize>(_onInitialize);
    on<DevicesRevokeRequested>(_onRevokeRequested);
    on<DevicesInviteRequested>(_onInviteRequested);
    on<DevicesInviteDismissed>((_, emit) => emit(state.copyWith(inviteLink: null, inviteFailed: false)));
  }

  DeviceRepository? get _repository => getIt.isRegistered<DeviceRepository>() ? getIt<DeviceRepository>() : null;

  Future<void> _onInitialize(DevicesInitialize event, Emitter<DevicesState> emit) async {
    emit(state.copyWith(loading: true, failed: false));
    final repository = _repository;
    if (repository == null) {
      // Mock flavors have no live channel and therefore no devices to show.
      emit(state.copyWith(loading: false, devices: const <DeviceModel>[]));
      return;
    }
    final result = await repository.getDevices();
    result.match<void>(
      onData: (devices) => emit(state.copyWith(loading: false, devices: devices, failed: false)),
      onError: (_) => emit(state.copyWith(loading: false, failed: true)),
    );
  }

  Future<void> _onRevokeRequested(DevicesRevokeRequested event, Emitter<DevicesState> emit) async {
    final repository = _repository;
    if (repository == null) return;
    final result = await repository.revoke(deviceKey: event.deviceKey);
    // Re-read rather than removing the row locally: the server is the authority
    // on what is still allowed, and a revoke that silently failed would
    // otherwise leave a device looking gone while it is still connecting.
    result.match<void>(onData: (_) => add(const DevicesEvent.initialize()), onError: (_) => emit(state.copyWith(failed: true)));
  }

  Future<void> _onInviteRequested(DevicesInviteRequested event, Emitter<DevicesState> emit) async {
    final repository = _repository;
    if (repository == null) return;
    final result = await repository.inviteDevice();
    result.match<void>(
      onData: (link) => emit(state.copyWith(inviteLink: link, inviteFailed: false)),
      onError: (_) => emit(state.copyWith(inviteFailed: true)),
    );
  }
}
