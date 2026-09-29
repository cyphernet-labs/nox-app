//! The embedded Tor client of the NOX app (phase 040): Arti behind a C ABI.
//!
//! The contract is `specs/040-tor-app/contracts/ffi.md`. No function blocks
//! and none lets a panic cross into the app: each body runs under
//! `catch_unwind`, and a panic comes back as the INTERNAL code.

pub mod bridge;
pub mod engine;
pub mod obsolete;
pub mod onion;
pub mod status;

use std::ffi::{c_char, CStr};
use std::panic::{catch_unwind, UnwindSafe};

use status::{error, NoxTorStatus};

const VERSION: &CStr = c"arti-client 0.47.0";

fn guarded(f: impl FnOnce() -> i32 + UnwindSafe) -> i32 {
    catch_unwind(f).unwrap_or(-(error::INTERNAL as i32))
}

/// # Safety
/// `ptr` must be null or a valid NUL-terminated string.
unsafe fn read_str<'a>(ptr: *const c_char) -> Option<&'a str> {
    if ptr.is_null() {
        return None;
    }
    CStr::from_ptr(ptr).to_str().ok()
}

/// # Safety
/// Both arguments are NUL-terminated UTF-8 paths.
#[no_mangle]
pub unsafe extern "C" fn nox_tor_start(state_dir: *const c_char, cache_dir: *const c_char) -> i32 {
    guarded(|| {
        let (Some(state_dir), Some(cache_dir)) = (read_str(state_dir), read_str(cache_dir)) else {
            return error::RET_INVALID_ARGUMENT;
        };
        engine::start(state_dir, cache_dir)
    })
}

#[no_mangle]
pub extern "C" fn nox_tor_stop() {
    let _ = guarded(|| {
        engine::stop();
        0
    });
}

/// # Safety
/// `onion_host` is NUL-terminated; `client_key32` points at 32 bytes.
#[no_mangle]
pub unsafe extern "C" fn nox_tor_set_target(onion_host: *const c_char, port: u16, client_key32: *const u8) -> i32 {
    guarded(|| {
        let Some(host) = read_str(onion_host) else {
            return error::RET_INVALID_ARGUMENT;
        };
        if client_key32.is_null() || !host.ends_with(".onion") {
            return error::RET_INVALID_ARGUMENT;
        }
        let mut key = [0u8; 32];
        key.copy_from_slice(std::slice::from_raw_parts(client_key32, 32));
        engine::set_target(host, port, key)
    })
}

#[no_mangle]
pub extern "C" fn nox_tor_clear_target() -> i32 {
    guarded(engine::clear_target)
}

#[no_mangle]
pub extern "C" fn nox_tor_set_dormant(dormant: bool) {
    let _ = guarded(|| {
        engine::set_dormant(dormant);
        0
    });
}

/// # Safety
/// `out` points at a writable `NoxTorStatus`.
#[no_mangle]
pub unsafe extern "C" fn nox_tor_status(out: *mut NoxTorStatus) -> i32 {
    guarded(|| {
        if out.is_null() {
            return error::RET_INVALID_ARGUMENT;
        }
        *out = engine::status();
        0
    })
}

/// # Safety
/// `out32` points at 32 writable bytes.
#[no_mangle]
pub unsafe extern "C" fn nox_tor_bridge_secret(out32: *mut u8) -> i32 {
    guarded(|| {
        if out32.is_null() {
            return error::RET_INVALID_ARGUMENT;
        }
        match engine::bridge_secret() {
            Some(secret) => {
                std::ptr::copy_nonoverlapping(secret.as_ptr(), out32, 32);
                0
            }
            None => error::RET_NOT_STARTED,
        }
    })
}

/// # Safety
/// `pub32` points at 32 bytes; `out` at `out_len` writable bytes.
#[no_mangle]
pub unsafe extern "C" fn nox_tor_onion_from_pubkey(pub32: *const u8, out: *mut c_char, out_len: usize) -> i32 {
    guarded(|| {
        if pub32.is_null() || out.is_null() {
            return error::RET_INVALID_ARGUMENT;
        }
        let mut key = [0u8; 32];
        key.copy_from_slice(std::slice::from_raw_parts(pub32, 32));
        let address = onion::onion_from_pubkey(&key);
        let bytes = address.as_bytes();
        if out_len < bytes.len() + 1 {
            return error::RET_INVALID_ARGUMENT;
        }
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), out as *mut u8, bytes.len());
        *out.add(bytes.len()) = 0;
        0
    })
}

#[no_mangle]
pub extern "C" fn nox_tor_version() -> *const c_char {
    VERSION.as_ptr()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;
    use std::sync::Mutex;

    /// The engine is process-wide; tests that start it take turns.
    static SERIAL: Mutex<()> = Mutex::new(());

    #[test]
    fn set_target_rejects_what_is_not_an_onion_service_or_a_key() {
        let _turn = SERIAL.lock().unwrap_or_else(|p| p.into_inner());
        let key = [1u8; 32];
        let host = CString::new("example.com").unwrap();
        assert_eq!(unsafe { nox_tor_set_target(host.as_ptr(), 443, key.as_ptr()) }, error::RET_INVALID_ARGUMENT);
        let onion = CString::new("25njqamcweflpvkl73j4szahhihoc4xt3ktcgjnpaingr5yhkenl5sid.onion").unwrap();
        assert_eq!(unsafe { nox_tor_set_target(onion.as_ptr(), 443, std::ptr::null()) }, error::RET_INVALID_ARGUMENT);
        // A well-formed target before start is refused, not silently kept.
        engine::reset_for_test();
        assert_eq!(unsafe { nox_tor_set_target(onion.as_ptr(), 443, key.as_ptr()) }, error::RET_NOT_STARTED);
    }

    #[test]
    fn onion_from_pubkey_writes_a_terminated_string_and_checks_the_room() {
        let mut out = [0 as c_char; 63];
        let key = [0u8; 32];
        assert_eq!(unsafe { nox_tor_onion_from_pubkey(key.as_ptr(), out.as_mut_ptr(), out.len()) }, 0);
        let s = unsafe { CStr::from_ptr(out.as_ptr()) }.to_str().unwrap();
        assert!(s.ends_with(".onion") && s.len() == 62);
        let mut small = [0 as c_char; 10];
        assert_eq!(
            unsafe { nox_tor_onion_from_pubkey(key.as_ptr(), small.as_mut_ptr(), small.len()) },
            error::RET_INVALID_ARGUMENT
        );
    }

    #[test]
    fn obsolete_stops_the_runtime_and_stays_reported() {
        let _turn = SERIAL.lock().unwrap_or_else(|p| p.into_inner());
        engine::reset_for_test();
        let dir = std::env::temp_dir().join(format!("nox_tor_test_{}", std::process::id()));
        let state = CString::new(dir.join("state").to_str().unwrap()).unwrap();
        let cache = CString::new(dir.join("cache").to_str().unwrap()).unwrap();
        assert_eq!(unsafe { nox_tor_start(state.as_ptr(), cache.as_ptr()) }, 0);
        engine::simulate_obsolete_for_test();
        // The teardown runs on its own thread.
        let mut seen = NoxTorStatus::default();
        for _ in 0..100 {
            unsafe { nox_tor_status(&mut seen) };
            if seen.state == status::state::OBSOLETE {
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
        assert_eq!(seen.state, status::state::OBSOLETE);
        // A new start is refused, and stop does not make the app forget.
        assert_eq!(unsafe { nox_tor_start(state.as_ptr(), cache.as_ptr()) }, -(error::SOFTWARE_DEPRECATED as i32));
        nox_tor_stop();
        unsafe { nox_tor_status(&mut seen) };
        assert_eq!(seen.state, status::state::OBSOLETE);
        engine::reset_for_test();
        let _ = std::fs::remove_dir_all(dir);
    }
}
