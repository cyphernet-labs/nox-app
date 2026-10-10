import 'dart:async';
import 'dart:typed_data';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/model/connection/connection_problem.dart';
import 'package:nox_app/domain/model/connection/connection_status.dart';
import 'package:nox_app/domain/model/connection/server_addresses.dart';
import 'package:nox_app/domain/repository/connection/server_addresses_repository.dart';
import 'package:nox_app/domain/service/connection_status_service.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';
import 'package:nox_app/domain/service/tor_service.dart';
import 'package:nox_app/general/connection/address_format.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';

part 'connection_settings_bloc.freezed.dart';
part 'connection_settings_event.dart';
part 'connection_settings_state.dart';

/// Settings > Connection (phase 045, FR-014): the same two address fields as
/// the connection screen, and `Use Tor`, after pairing.
///
/// The fields show the addresses in effect - the person's own edit, else what
/// the server says about itself, else what the pairing link carried. `Save`
/// applies them, offered only for a change that passes the format check; a
/// value equal to what the server says is no edit at all, so the server's word
/// keeps the field from then on (FR-015). `Use Tor` applies the moment it is
/// switched. Whatever is applied, the channel starts again at once
/// ([SessionPhaseService.reconnect]), so the next attempt goes by the new
/// settings. A changed onion address is simply typed in - no pairing again.
/// Above the fields, a line says why there is no connection when it is down.
class ConnectionSettingsBloc extends BaseBloc<ConnectionSettingsEvent, ConnectionSettingsState> {
  ConnectionSettingsBloc() : super(const ConnectionSettingsState()) {
    on<ConnectionSettingsInitialize>(_onInitialize);
    on<ConnectionSettingsServerAddressChanged>(_onServerAddressChanged);
    on<ConnectionSettingsOnionAddressChanged>(_onOnionAddressChanged);
    // One write at a time, in order: a Save and a switch of Use Tor are both
    // read-modify-writes of one record, and each restarts the channel.
    on<ConnectionSettingsSaveRequested>(_onSaveRequested, transformer: sequential());
    on<ConnectionSettingsUseTorChanged>(_onUseTorChanged, transformer: sequential());
    on<ConnectionSettingsStoredChanged>(_onStoredChanged);
    on<ConnectionSettingsConnectionStatusChanged>(_onConnectionStatusChanged);
  }

  final ServerAddressesRepository _addresses = getIt<ServerAddressesRepository>();

  StreamSubscription<ServerAddresses>? _storedSub;
  StreamSubscription<ConnectionStatus>? _statusSub;

  /// The first direct address of the pairing link (`session.server_address`):
  /// what the address field falls back to.
  String _linkAddress = '';

  @override
  Future<void> close() {
    _storedSub?.cancel();
    _statusSub?.cancel();
    return super.close();
  }

  Future<void> _onInitialize(ConnectionSettingsInitialize event, Emitter<ConnectionSettingsState> emit) async {
    _linkAddress = (await sessionRepository.serverAddress()).data ?? '';
    // The section can be left while the read above is under way. close() then
    // has already cancelled the subscriptions that existed - none - and one
    // made now would outlive the bloc: it holds the bloc and both streams for
    // the rest of the process, and its next value is an add() on a closed
    // bloc, which throws into the zone rather than anywhere it is handled.
    if (isClosed) return;
    // The watch hands over what is stored on listen, and every change after.
    _storedSub ??= _addresses.watch().listen((stored) => add(ConnectionSettingsEvent.storedChanged(stored)), onError: (Object _) {});
    _statusSub ??= getIt<ConnectionStatusService>().watchStatus().listen(
      (status) => add(ConnectionSettingsEvent.connectionStatusChanged(status)),
    );
  }

  /// What is stored, into the fields. A field the person is in the middle of
  /// changing keeps what they typed; one they have not touched follows - a
  /// new address from the server shows up while the section is open
  /// (US4, scenario 3).
  void _onStoredChanged(ConnectionSettingsStoredChanged event, Emitter<ConnectionSettingsState> emit) {
    final stored = event.stored;
    final applied = stored.fieldAddress(_linkAddress) ?? '';
    final appliedOnion = _hostOf(stored.effectiveOnion);
    final serverEdited = !state.loading && state.serverAddress.trim() != state.appliedServerAddress;
    final onionEdited = !state.loading && state.onionAddress.trim() != state.appliedOnionAddress;
    final next = state.copyWith(
      loading: false,
      appliedServerAddress: applied,
      appliedOnionAddress: appliedOnion,
      serverDefaultAddress: stored.public ?? _linkAddress,
      serverDefaultOnion: _hostOf(stored.onion),
      useTor: stored.useTor,
      serverAddress: serverEdited ? state.serverAddress : applied,
      onionAddress: onionEdited ? state.onionAddress : appliedOnion,
    );
    emit(
      next.copyWith(
        serverAddressInvalid: !_serverValid(next.serverAddress, next),
        onionAddressInvalid: _onionFor(next.onionAddress, next) == null,
      ),
    );
  }

  void _onServerAddressChanged(ConnectionSettingsServerAddressChanged event, Emitter<ConnectionSettingsState> emit) {
    emit(state.copyWith(serverAddress: event.value, serverAddressInvalid: !_serverValid(event.value, state), saveFailed: false));
  }

  void _onOnionAddressChanged(ConnectionSettingsOnionAddressChanged event, Emitter<ConnectionSettingsState> emit) {
    emit(state.copyWith(onionAddress: event.value, onionAddressInvalid: _onionFor(event.value, state) == null, saveFailed: false));
  }

  Future<void> _onSaveRequested(ConnectionSettingsSaveRequested event, Emitter<ConnectionSettingsState> emit) async {
    if (!state.canSave) return;
    final server = state.serverAddress.trim();
    final onion = _onionFor(state.onionAddress, state);
    if (!_serverValid(server, state) || onion == null) return;
    emit(state.copyWith(saving: true, saveFailed: false));
    // What equals the server's word is no edit: the field follows the server
    // again from here on.
    final serverDefaultOnion = state.serverDefaultOnion.isEmpty ? '' : '${state.serverDefaultOnion}:${AddressFormat.onionPort}';
    final saved = await _addresses.saveManual(
      manualAddress: server == state.serverDefaultAddress ? null : server,
      manualOnion: onion == serverDefaultOnion ? null : onion,
    );
    if (!saved.hasData) {
      emit(state.copyWith(saving: false, saveFailed: true));
      return;
    }
    // The watch brings the applied values back; the fields say what was
    // saved in the meantime.
    emit(
      state.copyWith(
        saving: false,
        serverAddress: server,
        appliedServerAddress: server,
        onionAddress: _hostOf(onion.isEmpty ? null : onion),
        appliedOnionAddress: _hostOf(onion.isEmpty ? null : onion),
      ),
    );
    await _reconnect();
  }

  Future<void> _onUseTorChanged(ConnectionSettingsUseTorChanged event, Emitter<ConnectionSettingsState> emit) async {
    if (state.loading || event.value == state.useTor) return;
    final previous = state.useTor;
    emit(state.copyWith(useTor: event.value, saveFailed: false));
    final saved = await _addresses.setUseTor(event.value);
    if (!saved.hasData) {
      emit(state.copyWith(useTor: previous, saveFailed: true));
      return;
    }
    await _reconnect();
  }

  void _onConnectionStatusChanged(ConnectionSettingsConnectionStatusChanged event, Emitter<ConnectionSettingsState> emit) {
    final status = event.status;
    final down = status.showsNoConnection || status.isServerMismatch;
    emit(state.copyWith(offline: down, problem: down ? status.problem : null));
  }

  /// Starts the channel again, so the very next attempt goes by what was just
  /// applied rather than waiting out a rung of the ladder on the old settings.
  Future<void> _reconnect() async {
    if (!getIt.isRegistered<SessionPhaseService>()) return;
    await getIt<SessionPhaseService>().reconnect();
  }

  /// A server address in `host:port` form. What is applied now is taken as
  /// it is: it came from the link or the server, and only an edit is checked.
  static bool _serverValid(String value, ConnectionSettingsState state) {
    final text = value.trim();
    if (text.isNotEmpty && text == state.appliedServerAddress) return true;
    return AddressFormat.isServerAddress(text);
  }

  /// `<56>.onion:443` to store, empty for none, or null for what cannot be
  /// one. What is applied now is taken as it is, like the server address.
  static String? _onionFor(String value, ConnectionSettingsState state) {
    final text = value.trim();
    if (text.isEmpty) return '';
    if (text == state.appliedOnionAddress) return '$text:${AddressFormat.onionPort}';
    return AddressFormat.normalizeOnion(text, derive: _derive);
  }

  static String? _derive(Uint8List publicKey) =>
      getIt.isRegistered<TorService>() ? getIt<TorService>().onionFromPublicKey(publicKey) : null;

  static String _hostOf(String? stored) => stored == null || stored.isEmpty ? '' : AddressFormat.onionHostOf(stored);
}
