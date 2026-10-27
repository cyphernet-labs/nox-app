/// Linear-ish app lifecycle phase the top-level navigator cares about.
/// NOX-adapted (no guest, no role): `registrationPending` is the first-login
/// `Set username` (2.3) gate. `init` is the boot sentinel (before first resolve).
enum AppStateType { init, unauthorized, registrationPending, authorized }
