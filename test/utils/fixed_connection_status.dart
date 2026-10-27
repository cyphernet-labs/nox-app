import 'dart:async';

import 'package:nox_app/domain/model/connection/connection_path.dart';
import 'package:nox_app/domain/model/connection/connection_status.dart';
import 'package:nox_app/domain/service/connection_status_service.dart';

/// A [ConnectionStatusService] a test sets by hand: the current [value] on
/// listen, then every [emit].
class FixedConnectionStatusService implements ConnectionStatusService {
  FixedConnectionStatusService([this.value = const ConnectionStatus(state: LinkState.online)]);

  /// The four corners of the contract (contracts/ui-states.md).
  static const ConnectionStatus direct = ConnectionStatus(state: LinkState.online, path: ConnectionPath.direct);
  static const ConnectionStatus tor = ConnectionStatus(state: LinkState.online, path: ConnectionPath.tor);
  static const ConnectionStatus connecting = ConnectionStatus(state: LinkState.connecting);
  static const ConnectionStatus connectingTor = ConnectionStatus(state: LinkState.connecting, path: ConnectionPath.tor);

  ConnectionStatus value;
  final StreamController<ConnectionStatus> _changes = StreamController<ConnectionStatus>.broadcast();

  void emit(ConnectionStatus next) {
    value = next;
    _changes.add(next);
  }

  @override
  ConnectionStatus get status => value;

  @override
  Stream<ConnectionStatus> watchStatus() async* {
    yield value;
    yield* _changes.stream;
  }
}
