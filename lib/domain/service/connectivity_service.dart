/// Domain seam over device connectivity (feature F3). Wraps the platform plugin so
/// blocs stay testable/mockable (mirrors CameraPermissionService / FilePickerService).
/// "Online" = the device reports at least one active network - nothing more.
/// Whether the server answers is the session phase (`SessionPhaseService`) and
/// the connection status (`ConnectionStatusService`); the banners read those.
abstract class ConnectivityService {
  /// The current online state (one-shot).
  Future<bool> isOnline();

  /// Emits the CURRENT online state on listen (seed), then a value on every change.
  Stream<bool> watchOnline();
}
