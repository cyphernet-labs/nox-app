/// Tells when the device's network changed - Wi-Fi to cellular and back, a new
/// Wi-Fi, a VPN (phase 040). Not whether it is online: that is
/// `ConnectivityService`. A change is the moment to check whether the direct
/// path to the server works again.
abstract class NetworkChangeService {
  /// One event per change; nothing on listen.
  Stream<void> watchChanges();
}
