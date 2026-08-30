/// Domain seam over device connectivity (feature F3). Wraps the platform plugin so
/// blocs stay testable/mockable (mirrors CameraPermissionService / FilePickerService).
/// "Online" = the device reports at least one active network. This is a PROXY for
/// the design's Offline state: real reachability becomes a session phase
/// (no socket → connecting → catching-up → live) with the transport in phase 027,
/// which is what these consumers move onto.
abstract class ConnectivityService {
  /// The current online state (one-shot).
  Future<bool> isOnline();

  /// Emits the CURRENT online state on listen (seed), then a value on every change.
  Stream<bool> watchOnline();
}
