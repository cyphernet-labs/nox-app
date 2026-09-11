import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/model/device/device_model.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/device/device_repository.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';

part 'devices_bloc.freezed.dart';
part 'devices_event.dart';
part 'devices_state.dart';

/// 7.3 Devices — the list of keys allowed to speak as this person, and the way
/// to cut one off.
///
/// Always read from the server, never from a cache: a stale list would offer to
/// revoke a device that is already gone and hide one added from elsewhere.
///
/// Reading from the server is necessary and was not sufficient. Until phase 038
/// the read happened once, when the screen was built, so the second half of
/// that promise was not kept: a device added from elsewhere stayed hidden until
/// somebody left the screen and came back. Two subscriptions close it —
/// `device.paired` from the server, and the live channel coming back after a
/// break, because that event does not survive a disconnect.
class DevicesBloc extends BaseBloc<DevicesEvent, DevicesState> {
  DevicesBloc() : super(const DevicesState()) {
    // sequential(), like every other paginated load in the project. Two reads
    // can now be in flight at once - the person's own, and one the screen
    // started by itself - and letting them race means the slower answer wins:
    // a stale list overwrites a fresher one, or a failed background read lands
    // on a state the pending first load had already cleared and leaves an empty
    // list looking loaded.
    on<DevicesInitialize>(_onInitialize, transformer: sequential());
    on<DevicesRevokeRequested>(_onRevokeRequested);
    on<DevicesInviteRequested>(_onInviteRequested);
    on<DevicesInviteDismissed>((_, emit) => emit(state.copyWith(inviteLink: null, inviteFailed: false)));
    on<DevicesDeviceListChanged>(_onDeviceListChanged);
    on<DevicesConnectionRestored>((_, _) => add(const DevicesEvent.initialize(refresh: true)));
  }

  DeviceRepository? get _repository => getIt.isRegistered<DeviceRepository>() ? getIt<DeviceRepository>() : null;

  StreamSubscription<void>? _pairedSub;
  StreamSubscription<SessionPhase>? _phaseSub;

  /// Whether the channel was live at the previous tick, or null before the
  /// first one.
  ///
  /// Null matters. `watchPhase` replays its current value to a new listener, so
  /// the very first tick says what is already true rather than that anything
  /// changed — and treating it as an edge would re-read the list the instant
  /// the screen subscribes, on top of the read `initialize` is already doing.
  /// The first tick is the baseline; only a later false → true is news.
  bool? _wasCurrent;

  @override
  Future<void> close() {
    _pairedSub?.cancel();
    _phaseSub?.cancel();
    return super.close();
  }

  Future<void> _onInitialize(DevicesInitialize event, Emitter<DevicesState> emit) async {
    // A refresh leaves the screen alone: the list stays visible while the new
    // one is fetched. Only a first load is allowed to show a spinner, because
    // only then is there nothing to look at.
    if (!event.refresh) emit(state.copyWith(loading: true, failed: false, actionFailed: false));
    final repository = _repository;
    if (repository == null) {
      // Mock flavors have no live channel and therefore no devices to show.
      emit(state.copyWith(loading: false, devices: const <DeviceModel>[]));
      return;
    }
    // Subscribed here rather than in the constructor, for the same reason the
    // repository is resolved here: it exists only on the live environment, and
    // a mock flavour has nothing to listen to.
    //
    // isClosed, because both streams outlive a frame: a device can pair, or the
    // channel can come back, while this screen is being torn down.
    _pairedSub ??= repository.watchDeviceListChanged().listen((_) {
      if (isClosed) return;
      add(const DevicesEvent.deviceListChanged());
    });
    _phaseSub ??= _phaseService.watchPhase().listen((phase) {
      final current = phase.isCurrent;
      final restored = _wasCurrent == false && current;
      _wasCurrent = current;
      if (!restored || isClosed) return;
      // The event above is live and does not survive a break. Without this the
      // person whose connection blinked at the wrong moment keeps a wrong list
      // in the one situation this phase exists for, and nothing tells them.
      add(const DevicesEvent.connectionRestored());
    });

    // Both of these are taken BEFORE the read, and for the same reason: an
    // answer describes the world as it was when the question was asked.
    //
    // The KEYS are what says a device joined while this one was away - the live
    // event never reached us, and the list is the only evidence. Not the
    // length: a pairing that coincides with a revocation leaves the count
    // exactly where it was, and the spent QR would then survive the one
    // reconnect it exists to be dismissed on.
    //
    // The INVITE is captured so this read cannot outlive its own subject. It
    // may take a second to answer; the person may mint a new invite while it is
    // in flight; and that one is not the token the joining device spent. Only
    // the invite that was on screen when the read started can be.
    final knownKeys = state.devices.map((d) => d.deviceKey).toSet();
    final inviteAtStart = state.inviteLink;
    final result = await repository.getDevices();
    result.match<void>(
      onData: (devices) {
        // The card has to go for the reason it goes on the event - the QR on it
        // is spent, and the server will refuse it. Without this the reconnect
        // path shows the new device and the dead QR above it at the same time.
        final joined = devices.any((d) => !knownKeys.contains(d.deviceKey));
        final spent = joined && state.inviteLink == inviteAtStart;
        emit(state.copyWith(loading: false, devices: devices, failed: false, inviteLink: spent ? null : state.inviteLink));
      },
      // A refresh that fails LEAVES THE SCREEN AS IT FOUND IT — it neither
      // raises the error nor lowers one that is already up.
      //
      // Both halves are load-bearing, and the first draft of this only had the
      // one. Not raising it keeps the list: what is shown is the last thing the
      // server actually said, and trading it for an error screen over a request
      // nobody made is the wrong direction. Not LOWERING it matters just as
      // much: a failed first load leaves the error on screen, and a background
      // refresh that also failed would otherwise clear it — swapping a truthful
      // "we could not load your devices" for an empty list and an invitation to
      // add one. The same erasure would silently take away the notice that a
      // revoke did not work.
      onError: (_) => emit(state.copyWith(loading: false, failed: event.refresh ? state.failed : true)),
    );
  }

  /// Another device of this person was paired.
  ///
  /// The list is re-read rather than patched: the server is the authority on
  /// who may speak as this person, and the event carries nothing to patch with.
  ///
  /// The invite card goes too, whichever invite was actually spent. The event
  /// deliberately does not say — naming it would put a token on the wire — and
  /// the rare cost (two live invites, the unused one hidden early) is one tap
  /// on `Add a device`. Leaving the card up is worse: it offers a QR that the
  /// server will now refuse, and the refusal reads as the app being broken.
  Future<void> _onDeviceListChanged(DevicesDeviceListChanged event, Emitter<DevicesState> emit) async {
    emit(state.copyWith(inviteLink: null, inviteFailed: false));
    add(const DevicesEvent.initialize(refresh: true));
  }

  SessionPhaseService get _phaseService => getIt<SessionPhaseService>();

  Future<void> _onRevokeRequested(DevicesRevokeRequested event, Emitter<DevicesState> emit) async {
    final repository = _repository;
    if (repository == null) return;

    // A fresh attempt takes down the notice about the previous one. It has no
    // other way off the screen - there is no dismiss control and the person is
    // already where the list lives - so without this it describes a revoke that
    // is no longer the one being watched. If this attempt fails too it comes
    // straight back, which is the whole of what the notice is for.
    emit(state.copyWith(actionFailed: false));

    // Revoking the device in your hand IS a logout - the contract calls logout
    // a special case of revocation. Going through the logout path wipes the
    // local data and moves the navigation; merely deleting the row would leave
    // the app sitting there with a session the server no longer honours.
    if (state.devices.any((d) => d.isCurrent && d.deviceKey == event.deviceKey)) {
      final out = await authRepository.logout();
      // A failed wipe leaves the person signed in with data that should be
      // gone. Settings surfaces the same failure; so does this.
      if (!out.hasData) emit(state.copyWith(actionFailed: true));
      return;
    }

    final result = await repository.revoke(deviceKey: event.deviceKey);
    // Re-read rather than removing the row locally: the server is the authority
    // on what is still allowed, and a revoke that silently failed would
    // otherwise leave a device looking gone while it is still connecting.
    result.match<void>(onData: (_) => add(const DevicesEvent.initialize()), onError: (_) => emit(state.copyWith(actionFailed: true)));
  }

  Future<void> _onInviteRequested(DevicesInviteRequested event, Emitter<DevicesState> emit) async {
    final repository = _repository;
    if (repository == null) {
      // No live channel in this build. Saying so beats a button that does
      // nothing at all when tapped.
      emit(state.copyWith(inviteFailed: true));
      return;
    }
    final result = await repository.inviteDevice();
    result.match<void>(
      onData: (link) => emit(state.copyWith(inviteLink: link, inviteFailed: false)),
      onError: (_) => emit(state.copyWith(inviteFailed: true)),
    );
  }
}
