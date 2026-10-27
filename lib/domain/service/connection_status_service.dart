import 'package:nox_app/domain/model/connection/connection_status.dart';

/// Where the connection stands and by which path - the one source the corner
/// indicator and the connection banners read (phase 040).
abstract class ConnectionStatusService {
  ConnectionStatus get status;

  /// The current status on listen, then every change.
  Stream<ConnectionStatus> watchStatus();
}
