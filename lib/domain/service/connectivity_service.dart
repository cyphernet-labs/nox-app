/// Domain seam over device connectivity (feature F3). Wraps the platform plugin so
/// blocs stay testable/mockable (mirrors CameraPermissionService / FilePickerService).
/// "Online" = the device reports at least one active network — the closest real-flow
/// proxy for the design's Offline state while the backend (real reachability) is TBD.
abstract class ConnectivityService {
  /// The current online state (one-shot).
  Future<bool> isOnline();

  /// Emits the CURRENT online state on listen (seed), then a value on every change.
  Stream<bool> watchOnline();
}
