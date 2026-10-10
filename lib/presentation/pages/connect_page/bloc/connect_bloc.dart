import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/exception/pairing_exception.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/connection/connection_problem.dart';
import 'package:nox_app/domain/model/connection/connection_settings.dart';
import 'package:nox_app/domain/model/connection/connection_status.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/domain/service/connection_status_service.dart';
import 'package:nox_app/domain/service/tor_service.dart';
import 'package:nox_app/general/connection/address_format.dart';
import 'package:nox_app/general/pairing/pairing_link.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';

part 'connect_bloc.freezed.dart';
part 'connect_event.dart';
part 'connect_state.dart';

/// The connection screen (phase 045, FR-013): between a pairing link and the
/// pairing itself, whichever way the link arrived - pasted, scanned, or read
/// from a QR image.
///
/// The fields start with what the link carries - its first direct address
/// and the onion address its service key derives - and the person may change
/// both: whoever answers at an address must still prove the key the link
/// names before the token goes out, so an edited address can lead nowhere
/// else. `Use Tor` starts off. `Connect` checks the format of what was
/// edited, then pairs through [AuthRepository.signIn] with these settings;
/// the app-state spine moves on from a pairing that lands.
///
/// An invite pairs only once the device that issued it answers (phase 046):
/// the screen then waits, with Cancel as the one thing left to press, and
/// ends declined, expired, or - on Cancel - closed. A wait the app was closed
/// in is [resume]d: the screen comes back with what was set for it and
/// presents the same link at once, which is the same request (FR-011).
class ConnectBloc extends BaseBloc<ConnectEvent, ConnectState> {
  ConnectBloc({required this.link, this.resume = false, ConnectionSettings? settings, ConnectState? initialState})
    : super(initialState ?? _initial(link, resume ? settings : null)) {
    on<ServerAddressChanged>(_onServerAddressChanged);
    on<OnionAddressChanged>(_onOnionAddressChanged);
    on<UseTorChanged>(_onUseTorChanged);
    on<ConnectRequested>(_onConnectRequested);
    on<ConnectionStatusChanged>(_onConnectionStatusChanged);
    on<ApprovalAwaited>(_onApprovalAwaited);
    on<CancelRequested>(_onCancelRequested);
    _statusSub = getIt<ConnectionStatusService>().watchStatus().listen((status) => add(ConnectEvent.connectionStatusChanged(status)));
    _approvalSub = authRepository.watchAwaitingApproval().listen((waiting) => add(ConnectEvent.approvalAwaited(waiting: waiting)));
    if (resume) add(const ConnectEvent.connectRequested());
  }

  /// The pairing link, as it arrived.
  final String link;

  /// The screen came back for a wait the app was closed in (FR-011): it
  /// presents the link again at once.
  final bool resume;

  StreamSubscription<ConnectionStatus>? _statusSub;
  StreamSubscription<bool>? _approvalSub;

  @override
  Future<void> close() {
    _statusSub?.cancel();
    _approvalSub?.cancel();
    return super.close();
  }

  /// The fields as the link fills them, or - for a resumed wait - as they
  /// were set when it began.
  static ConnectState _initial(String link, ConnectionSettings? settings) {
    final fromLink = initialFor(link);
    if (settings == null) return fromLink;
    final onion = settings.onionAddress;
    return fromLink.copyWith(
      serverAddress: settings.serverAddress,
      onionAddress: onion == null ? '' : AddressFormat.onionHostOf(onion),
      useTor: settings.useTor,
    );
  }

  /// The fields as the link fills them: its first direct address - the
  /// public one when the server set one (contract §8A) - and its onion
  /// address, empty when it carries none.
  static ConnectState initialFor(String link) {
    final parsed = PairingLink.tryParse(link);
    final direct = parsed?.directAddresses ?? const <String>[];
    final serviceKey = parsed?.onionServiceKey;
    final onion = serviceKey == null ? null : _derive(serviceKey);
    final server = direct.isEmpty ? '' : direct.first;
    return ConnectState(serverAddress: server, onionAddress: onion ?? '', linkServerAddress: server, linkOnionAddress: onion ?? '');
  }

  /// The Tor module's arithmetic: the onion address of a service key. Null
  /// where the module is absent.
  static String? _derive(Uint8List publicKey) =>
      getIt.isRegistered<TorService>() ? getIt<TorService>().onionFromPublicKey(publicKey) : null;

  void _onServerAddressChanged(ServerAddressChanged event, Emitter<ConnectState> emit) {
    if (state.isBusy) return;
    emit(_edited(state.copyWith(serverAddress: event.value, serverAddressInvalid: !_serverValid(event.value, state))));
  }

  void _onOnionAddressChanged(OnionAddressChanged event, Emitter<ConnectState> emit) {
    if (state.isBusy) return;
    emit(_edited(state.copyWith(onionAddress: event.value, onionAddressInvalid: _onionFor(event.value, state) == null)));
  }

  void _onUseTorChanged(UseTorChanged event, Emitter<ConnectState> emit) {
    if (state.isBusy) return;
    emit(_edited(state.copyWith(useTor: event.value)));
  }

  /// A change takes back what the last attempt said: it was about the
  /// settings that were there then.
  ConnectState _edited(ConnectState next) => next.copyWith(status: ConnectStatus.idle, problem: null);

  Future<void> _onConnectRequested(ConnectRequested event, Emitter<ConnectState> emit) async {
    if (state.isBusy) return;
    final serverValid = _serverValid(state.serverAddress, state);
    final onion = _onionFor(state.onionAddress, state);
    if (!serverValid || onion == null) {
      // Nothing goes out on an address that cannot be one (US5, scenario 1).
      emit(state.copyWith(showFieldErrors: true, serverAddressInvalid: !serverValid, onionAddressInvalid: onion == null));
      return;
    }
    emit(
      state.copyWith(
        status: ConnectStatus.connecting,
        problem: null,
        showFieldErrors: true,
        serverAddressInvalid: false,
        onionAddressInvalid: false,
      ),
    );
    // Never throws: a repository answers with a result.
    final result = await authRepository.signIn(
      identifier: link,
      connection: ConnectionSettings(
        serverAddress: state.serverAddress.trim(),
        onionAddress: onion.isEmpty ? null : onion,
        useTor: state.useTor,
      ),
    );
    result.match<void>(
      // The spine takes the app on from here; this screen goes with the rest.
      onData: (_) => emit(state.copyWith(status: ConnectStatus.idle, cancelling: false)),
      onError: (exception) => emit(_failed(exception).copyWith(cancelling: false)),
    );
  }

  /// The request waits for the device that issued the invite (phase 046).
  /// Only a pairing under way moves to waiting: the stream replays its last
  /// value to a new listener, and a stale "waiting" must not take over a
  /// screen that has not pressed Connect.
  void _onApprovalAwaited(ApprovalAwaited event, Emitter<ConnectState> emit) {
    if (!event.waiting || !state.isConnecting) return;
    // What the attempt found on its way there is history now: the request is
    // on the server, which is as far as a connection had to go.
    emit(state.copyWith(status: ConnectStatus.waiting, problem: null));
  }

  /// Withdraws the request (FR-010). The sign-in under way then ends - as
  /// cancelled, and the screen closes, or paired after all when the other
  /// device's Allow got there first.
  Future<void> _onCancelRequested(CancelRequested event, Emitter<ConnectState> emit) async {
    if (!state.isWaiting || state.cancelling) return;
    emit(state.copyWith(cancelling: true));
    await authRepository.cancelPairing();
  }

  ConnectState _failed(Object? exception) {
    switch (exception) {
      case RepositoryException.notFound:
        return state.copyWith(status: ConnectStatus.linkExpired, problem: null);
      case RepositoryException.authentication:
        return state.copyWith(status: ConnectStatus.linkRejected, problem: null);
      case PairingException.declined:
        return state.copyWith(status: ConnectStatus.declined, problem: null);
      case PairingException.cancelled:
        return state.copyWith(status: ConnectStatus.cancelled, problem: null);
      default:
        // The cause the attempt found on its way, if it found one. A malformed
        // onion address the module refused belongs at the field, too.
        final problem = state.problem;
        return state.copyWith(
          status: ConnectStatus.failed,
          onionAddressInvalid: state.onionAddressInvalid || problem == ConnectionProblem.invalidOnion,
        );
    }
  }

  /// The cause of a failing attempt, while it is still under way: shown
  /// under the button at once rather than when the whole budget has run out,
  /// and kept when the attempt ends - the rollback that follows a failure
  /// takes the selector's answer away.
  void _onConnectionStatusChanged(ConnectionStatusChanged event, Emitter<ConnectState> emit) {
    if (!state.isConnecting) return;
    final problem = event.status.problem;
    if (problem == null || problem == state.problem) return;
    emit(state.copyWith(problem: problem));
  }

  /// A server address in `host:port` form; the link's own is taken as it is.
  static bool _serverValid(String value, ConnectState state) {
    final text = value.trim();
    if (text.isNotEmpty && text == state.linkServerAddress) return true;
    return AddressFormat.isServerAddress(text);
  }

  /// The onion address to store - `<56>.onion:443`, or empty for none - or
  /// null when what was typed is not one. The link's own is taken as it is.
  static String? _onionFor(String value, ConnectState state) {
    final text = value.trim();
    if (text.isEmpty) return '';
    if (text == state.linkOnionAddress) return '${state.linkOnionAddress}:${AddressFormat.onionPort}';
    return AddressFormat.normalizeOnion(text, derive: _derive);
  }
}
