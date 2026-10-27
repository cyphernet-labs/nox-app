/// Normalized camera permission outcome consumed by the scanner (2.2). Projects
/// the two backends (permission_handler on iOS/Android; mobile_scanner controller
/// state on macOS) into one set. `restricted`/`limited` fold into
/// [permanentlyDenied] (same UX: Open settings). `unavailable` = no camera at the
/// device level (or a platform-channel failure) -> Fatal (3.1).
enum CameraPermissionStatus { granted, denied, permanentlyDenied, unavailable }
