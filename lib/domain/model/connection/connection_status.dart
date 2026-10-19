import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/model/connection/connection_path.dart';
import 'package:nox_app/domain/model/connection/connection_problem.dart';

part 'connection_status.freezed.dart';

/// Where the connection to the server stands, for the interface (phase 040).
///
/// Named LinkState rather than ConnectionState: Flutter's widgets library
/// already exports a ConnectionState, and every presentation file imports it.
enum LinkState {
  /// A path is being chosen or brought up, including a Tor bootstrap.
  connecting,

  /// Greeted; the server is replaying what was missed.
  catchingUp,

  /// Up to date.
  online,

  /// A whole attempt failed and nothing has succeeded since. Kept through
  /// the retries that follow, so the banner does not blink on every one.
  offline,

  /// The server reached through its onion address presented a key the pairing
  /// link did not name (FR-030). Never caused by a direct address (FR-005).
  /// Its [ConnectionStatus.problem] is [ConnectionProblem.otherServer].
  serverMismatch,

  /// The server will never accept this build (contract §2.1).
  unsupported,
}

@freezed
abstract class ConnectionStatus with _$ConnectionStatus {
  const ConnectionStatus._();

  const factory ConnectionStatus({
    required LinkState state,

    /// The path in use or being brought up; null until one is chosen.
    ConnectionPath? path,

    /// The Tor network no longer accepts the client built into this version.
    @Default(false) bool torObsolete,

    /// Why there is no connection, when that is known (phase 045): shown in
    /// place of «No connection». Null while connected or coming up, and when
    /// the cause cannot be told.
    ConnectionProblem? problem,
  }) = _ConnectionStatus;

  static const ConnectionStatus initial = ConnectionStatus(state: LinkState.connecting);

  bool get isOffline => state == LinkState.offline;

  /// What raises «No connection»: no path was found, or the server refuses
  /// this build for good (contract §2.1). The second is silent otherwise - the
  /// corner shows nothing for it and sending waits for ever.
  bool get showsNoConnection => state == LinkState.offline || state == LinkState.unsupported;
  bool get isServerMismatch => state == LinkState.serverMismatch;
  bool get isCurrent => state == LinkState.online;

  /// The corner says `Connecting…` (FR-027).
  bool get showsConnecting => state == LinkState.connecting || state == LinkState.catchingUp;

  /// The corner carries the Tor badge (FR-028).
  bool get showsTorBadge => path == ConnectionPath.tor && (showsConnecting || state == LinkState.online);
}
