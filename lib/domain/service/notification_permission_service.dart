/// Normalized OS notification-permission outcome consumed by the 7.2 Notifications
/// screen. `denied` folds permanentlyDenied / restricted (same UX: the "blocked"
/// banner + Open settings). Desktop platforms with no runtime notification-permission
/// model report `granted`.
enum NotificationPermissionStatus { granted, denied }

/// A thin OS notification-permission abstraction consumed by the Notifications screen
/// (7.2 — a BLoC-less UI-first widget). A domain seam over `permission_handler` so the
/// screen stays testable without an OS query, and the plugin is swappable — mirrors the
/// QR feature's `CameraPermissionService` and `FilePickerService`.
///
/// No-throw everywhere: the "blocked" banner is a soft nudge, not a gate, so an
/// indeterminate query resolves to `granted` (don't nag) rather than surfacing an error.
abstract class NotificationPermissionService {
  /// Current OS notification-permission status WITHOUT raising a prompt. Desktop (no
  /// runtime permission model) and any platform-channel failure → `granted`.
  Future<NotificationPermissionStatus> status();

  /// Deep-link to the app's system notification settings: `permission_handler`
  /// (`openAppSettings`) on iOS/Android, `url_launcher` on macOS; a benign no-op on
  /// Windows/Linux (no per-app notification settings surface). Never throws.
  Future<void> openSettings();
}
