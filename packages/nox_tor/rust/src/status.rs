//! The status snapshot the app polls, and the codes it carries.
//!
//! One small `repr(C)` struct rather than a stream of callbacks: the Dart side
//! polls it on its own schedule, and a snapshot under a short lock can never
//! leave a callback half-delivered when the runtime is torn down.

use std::sync::Mutex;

/// What the app reads through `nox_tor_status`.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct NoxTorStatus {
    pub state: u8,
    pub bootstrap_percent: u8,
    pub error: u8,
    pub reserved: u8,
    pub port: u16,
    pub reserved2: u16,
}

/// `NoxTorStatus::state`.
pub mod state {
    pub const STOPPED: u8 = 0;
    pub const BOOTSTRAPPING: u8 = 1;
    pub const READY: u8 = 2;
    pub const DORMANT: u8 = 3;
    pub const FAILED: u8 = 4;
    /// The network no longer accepts this client. Terminal for the process:
    /// the runtime is already gone (see `obsolete`).
    pub const OBSOLETE: u8 = 5;
}

/// `NoxTorStatus::error`, and the negative return codes of the C ABI.
pub mod error {
    pub const NONE: u8 = 0;
    pub const MISSING_CLIENT_AUTH: u8 = 1;
    pub const WRONG_CLIENT_AUTH: u8 = 2;
    pub const TIMEOUT: u8 = 3;
    pub const NETWORK: u8 = 4;
    pub const INTERNAL: u8 = 5;
    pub const SOFTWARE_DEPRECATED: u8 = 6;

    pub const RET_INVALID_ARGUMENT: i32 = -7;
    pub const RET_NOT_STARTED: i32 = -8;
}

/// The snapshot behind a short lock. Every writer replaces fields in one
/// critical section, so a reader never sees half an update.
#[derive(Default)]
pub struct StatusCell(Mutex<NoxTorStatus>);

impl StatusCell {
    pub fn get(&self) -> NoxTorStatus {
        *self.0.lock().unwrap_or_else(|p| p.into_inner())
    }

    pub fn update(&self, f: impl FnOnce(&mut NoxTorStatus)) {
        let mut guard = self.0.lock().unwrap_or_else(|p| p.into_inner());
        // OBSOLETE is final: nothing that happens after the runtime is gone may
        // make the app believe Tor is usable again.
        if guard.state == state::OBSOLETE {
            return;
        }
        f(&mut guard);
    }

    pub fn reset(&self) {
        *self.0.lock().unwrap_or_else(|p| p.into_inner()) = NoxTorStatus::default();
    }

    pub fn force_obsolete(&self) {
        let mut guard = self.0.lock().unwrap_or_else(|p| p.into_inner());
        guard.state = state::OBSOLETE;
        guard.error = error::SOFTWARE_DEPRECATED;
        guard.port = 0;
    }
}

/// Maps an Arti error to the code the app understands. The kinds are the only
/// thing read: the message may carry an onion address and must not travel.
pub fn classify(e: &arti_client::Error) -> u8 {
    use arti_client::{ErrorKind, HasKind};
    match e.kind() {
        ErrorKind::OnionServiceMissingClientAuth => error::MISSING_CLIENT_AUTH,
        ErrorKind::OnionServiceWrongClientAuth => error::WRONG_CLIENT_AUTH,
        ErrorKind::SoftwareDeprecated => error::SOFTWARE_DEPRECATED,
        // On this device rather than out on the network: a bug, or the state,
        // cache or key store out of reach.
        ErrorKind::Internal
        | ErrorKind::BadApiUsage
        | ErrorKind::FsPermissions
        | ErrorKind::PersistentStateAccessFailed
        | ErrorKind::PersistentStateCorrupted
        | ErrorKind::CacheAccessFailed
        | ErrorKind::CacheCorrupted
        | ErrorKind::KeystoreAccessFailed
        | ErrorKind::KeystoreCorrupted => error::INTERNAL,
        _ => error::NETWORK,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn obsolete_is_final() {
        let cell = StatusCell::default();
        cell.force_obsolete();
        cell.update(|s| s.state = state::READY);
        assert_eq!(cell.get().state, state::OBSOLETE);
        assert_eq!(cell.get().error, error::SOFTWARE_DEPRECATED);
    }

    #[test]
    fn the_struct_is_eight_bytes_with_a_stable_layout() {
        assert_eq!(std::mem::size_of::<NoxTorStatus>(), 8);
        let s = NoxTorStatus { state: 2, bootstrap_percent: 100, error: 0, reserved: 0, port: 4242, reserved2: 0 };
        let bytes: [u8; 8] = unsafe { std::mem::transmute(s) };
        assert_eq!(bytes[0], 2);
        assert_eq!(bytes[1], 100);
        assert_eq!(u16::from_ne_bytes([bytes[4], bytes[5]]), 4242);
    }
}
