//! The NOX app's native module, behind a C ABI: the channel to its server
//! (phase 044, `nox_chan_*`) and the embedded Tor client (phase 040,
//! `nox_tor_*`) the channel takes to the onion service.
//!
//! The contracts are `specs/044-secure-channel/contracts/ffi-channel.md` and
//! `specs/040-tor-app/contracts/ffi.md`. No function blocks and none lets a
//! panic cross into the app: each body runs under `catch_unwind`, and a panic
//! comes back as the INTERNAL code of its contract.

pub mod channel;
pub mod engine;
pub mod obsolete;
pub mod onion;
pub mod status;

use std::ffi::{c_char, CStr};
use std::panic::{catch_unwind, UnwindSafe};
use std::time::Duration;

use channel::code;
use status::{error, NoxTorStatus};
use zeroize::Zeroizing;

const VERSION: &CStr = c"arti-client 0.47.0";

fn guarded(f: impl FnOnce() -> i32 + UnwindSafe) -> i32 {
    catch_unwind(f).unwrap_or(-(error::INTERNAL as i32))
}

/// `guarded` for the channel's functions, whose INTERNAL is its own.
fn chan_guarded<T: From<i32>>(f: impl FnOnce() -> T + UnwindSafe) -> T {
    catch_unwind(f).unwrap_or_else(|_| T::from(-code::INTERNAL))
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
        // Straight from the caller's bytes into a heap buffer that wipes
        // itself: no copy of the key is left on this stack.
        let mut key = Box::new(Zeroizing::new([0u8; 32]));
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

/// Opens a channel: the handle at once, the outcome as an event (OPEN, or
/// CLOSED with the kind of failure). `target_kind` 0 is a direct address - an
/// IP or a name - and 1 an onion service through the started Tor client.
/// Every event of the channel is posted with `post` (`Dart_PostCObject`) to
/// `events_port`, a native port of the isolate that opens it.
///
/// # Safety
/// `host` is NUL-terminated UTF-8; `device_seed32` and `server_key32` point at
/// 32 bytes each; `post` is `Dart_PostCObject`, or behaves as it does.
#[no_mangle]
pub unsafe extern "C" fn nox_chan_open(
    target_kind: i32,
    host: *const c_char,
    port: u16,
    device_seed32: *const u8,
    server_key32: *const u8,
    connect_timeout_ms: u32,
    post: Option<channel::dart::PostFn>,
    events_port: i64,
) -> i64 {
    chan_guarded(|| {
        let invalid = i64::from(code::RET_INVALID_ARGUMENT);
        let (Some(post), Some(host)) = (post, read_str(host)) else {
            return invalid;
        };
        // 0 is ILLEGAL_PORT: no isolate has it.
        if host.is_empty()
            || port == 0
            || connect_timeout_ms == 0
            || device_seed32.is_null()
            || server_key32.is_null()
            || events_port == 0
        {
            return invalid;
        }
        let (host, port) = (host.to_owned(), port);
        let target = match target_kind {
            0 => channel::Target::Direct { host, port },
            1 => channel::Target::Onion { host, port },
            _ => return invalid,
        };
        // Straight from the caller's bytes into a heap buffer that wipes
        // itself, as the client key: no copy of the seed is left on this stack.
        let mut seed = Box::new(Zeroizing::new([0u8; 32]));
        seed.copy_from_slice(std::slice::from_raw_parts(device_seed32, 32));
        // No real seed is all zero, and ec25519 would panic on one.
        if seed.iter().all(|&b| b == 0) {
            return invalid;
        }
        let mut server_key = [0u8; 32];
        server_key.copy_from_slice(std::slice::from_raw_parts(server_key32, 32));
        let budget = Duration::from_millis(u64::from(connect_timeout_ms));
        channel::open(target, seed, server_key, budget, channel::dart::Port::new(post, events_port))
    })
}

/// Queues a copy of the bytes; returns the queued size after the write.
///
/// # Safety
/// `data` points at `len` bytes, or `len` is 0.
#[no_mangle]
pub unsafe extern "C" fn nox_chan_write(handle: i64, data: *const u8, len: usize) -> i64 {
    chan_guarded(|| {
        if len == 0 {
            return channel::write(handle, &[]);
        }
        if data.is_null() {
            return i64::from(code::RET_INVALID_ARGUMENT);
        }
        channel::write(handle, std::slice::from_raw_parts(data, len))
    })
}

/// Dart passed `len` more inbound bytes on: the module reads again.
#[no_mangle]
pub extern "C" fn nox_chan_ack(handle: i64, len: usize) -> i32 {
    chan_guarded(|| channel::ack(handle, len))
}

/// DRAINED with `code = ticket` once all queued before this call is out.
#[no_mangle]
pub extern "C" fn nox_chan_flush(handle: i64, ticket: i32) -> i32 {
    chan_guarded(|| channel::flush(handle, ticket))
}

/// TLS close_notify after the queue; reading goes on.
#[no_mangle]
pub extern "C" fn nox_chan_shutdown_write(handle: i64) -> i32 {
    chan_guarded(|| channel::shutdown_write(handle))
}

/// Tears the channel down at once; CLOSED follows, and after it the handle
/// is gone.
#[no_mangle]
pub extern "C" fn nox_chan_close(handle: i64) -> i32 {
    chan_guarded(|| channel::close(handle))
}

/// Ends every channel whose isolate is gone, and returns how many there were:
/// a probe goes to each channel's events port, and a port that refuses it
/// belongs to an isolate that died. A new isolate calls this before it opens a
/// channel of its own.
#[no_mangle]
pub extern "C" fn nox_chan_reap() -> i32 {
    chan_guarded(channel::reap)
}

/// Frees a buffer the module handed out as a result.
///
/// # Safety
/// `data` and `len` are what one call handed out, each freed once.
#[no_mangle]
pub unsafe extern "C" fn nox_chan_buf_free(data: *mut u8, len: usize) {
    chan_guarded(|| {
        channel::free_buffer(data, len);
        0
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;
    use std::path::PathBuf;
    use std::sync::Mutex;

    /// The engine is process-wide; tests that start it take turns.
    static SERIAL: Mutex<()> = Mutex::new(());

    const ONION: &str = "25njqamcweflpvkl73j4szahhihoc4xt3ktcgjnpaingr5yhkenl5sid.onion";

    /// A directory that cannot be created, because its parent is a file: the
    /// client cannot be built, so the engine fails without touching the
    /// network. Returns the blocking file, to remove afterwards.
    fn unusable_dir(name: &str) -> (PathBuf, CString) {
        let blocker = std::env::temp_dir().join(format!("nox_tor_{name}_{}", std::process::id()));
        std::fs::write(&blocker, b"").unwrap();
        let dir = CString::new(blocker.join("tor").to_str().unwrap()).unwrap();
        (blocker, dir)
    }

    fn status_now() -> NoxTorStatus {
        let mut seen = NoxTorStatus::default();
        unsafe { nox_tor_status(&mut seen) };
        seen
    }

    /// Polls until the engine reaches `want`, for ten seconds at most.
    fn wait_for(want: u8) -> NoxTorStatus {
        for _ in 0..500 {
            if status_now().state == want {
                break;
            }
            std::thread::sleep(Duration::from_millis(20));
        }
        status_now()
    }

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

    #[test]
    fn a_failed_client_is_rebuilt_by_the_next_start() {
        let _turn = SERIAL.lock().unwrap_or_else(|p| p.into_inner());
        engine::reset_for_test();
        let (blocker, bad) = unusable_dir("failed");
        assert_eq!(unsafe { nox_tor_start(bad.as_ptr(), bad.as_ptr()) }, 0);
        let failed = wait_for(status::state::FAILED);
        assert_eq!(failed.state, status::state::FAILED);
        // A directory out of reach is this device's problem, not the network's.
        assert_eq!(failed.error, error::INTERNAL);
        // The retry is a plain start, with no stop in between. The rebuilt
        // client bootstraps for real; the test needs no network, and stops it
        // before it gets far.
        let dir = std::env::temp_dir().join(format!("nox_tor_retry_{}", std::process::id()));
        let state_dir = dir.join("state");
        let state = CString::new(state_dir.to_str().unwrap()).unwrap();
        let cache = CString::new(dir.join("cache").to_str().unwrap()).unwrap();
        assert_eq!(unsafe { nox_tor_start(state.as_ptr(), cache.as_ptr()) }, 0);
        assert_eq!(status_now().state, status::state::BOOTSTRAPPING);
        // A new client was built, from the new directories.
        for _ in 0..500 {
            if state_dir.exists() {
                break;
            }
            std::thread::sleep(Duration::from_millis(20));
        }
        assert!(state_dir.exists());
        engine::reset_for_test();
        let _ = std::fs::remove_dir_all(dir);
        let _ = std::fs::remove_file(blocker);
    }

    #[test]
    fn a_rebuild_keeps_the_target_the_app_set() {
        let _turn = SERIAL.lock().unwrap_or_else(|p| p.into_inner());
        engine::reset_for_test();
        let (blocker, bad) = unusable_dir("carried");
        assert_eq!(unsafe { nox_tor_start(bad.as_ptr(), bad.as_ptr()) }, 0);
        assert_eq!(wait_for(status::state::FAILED).state, status::state::FAILED);
        let onion = CString::new(ONION).unwrap();
        let key = [1u8; 32];
        assert_eq!(unsafe { nox_tor_set_target(onion.as_ptr(), 443, key.as_ptr()) }, 0);
        // Rebuilt - and failing again, which is beside the point here.
        assert_eq!(unsafe { nox_tor_start(bad.as_ptr(), bad.as_ptr()) }, 0);
        assert_eq!(engine::target_host_for_test().as_deref(), Some(ONION));
        engine::reset_for_test();
        let _ = std::fs::remove_file(blocker);
    }

    /// The key goes into Arti's keystore and nowhere else: no listener, so no
    /// port in the status, and nothing on the loopback for another app to dial.
    #[test]
    fn a_target_opens_no_port() {
        let _turn = SERIAL.lock().unwrap_or_else(|p| p.into_inner());
        engine::reset_for_test();
        let (blocker, bad) = unusable_dir("no_port");
        assert_eq!(unsafe { nox_tor_start(bad.as_ptr(), bad.as_ptr()) }, 0);
        assert_eq!(wait_for(status::state::FAILED).state, status::state::FAILED);
        let onion = CString::new(ONION).unwrap();
        assert_eq!(unsafe { nox_tor_set_target(onion.as_ptr(), 443, [1u8; 32].as_ptr()) }, 0);
        assert_eq!(status_now().port, 0);
        assert_eq!(nox_tor_clear_target(), 0);
        assert_eq!(status_now().port, 0);
        engine::reset_for_test();
        let _ = std::fs::remove_file(blocker);
    }

    /// The app starts its clock on a refusal when the error ENTERS it. One left
    /// over from the previous key would never enter again.
    #[test]
    fn a_new_target_drops_a_key_refusal_and_nothing_else() {
        let _turn = SERIAL.lock().unwrap_or_else(|p| p.into_inner());
        engine::reset_for_test();
        let (blocker, bad) = unusable_dir("refusal");
        assert_eq!(unsafe { nox_tor_start(bad.as_ptr(), bad.as_ptr()) }, 0);
        assert_eq!(wait_for(status::state::FAILED).state, status::state::FAILED);
        let onion = CString::new(ONION).unwrap();
        let key = [1u8; 32];
        for refusal in [error::WRONG_CLIENT_AUTH, error::MISSING_CLIENT_AUTH] {
            engine::set_error_for_test(refusal);
            assert_eq!(unsafe { nox_tor_set_target(onion.as_ptr(), 443, key.as_ptr()) }, 0);
            assert_eq!(status_now().error, error::NONE, "refusal {refusal} outlived the target change");
        }
        engine::set_error_for_test(error::TIMEOUT);
        assert_eq!(unsafe { nox_tor_set_target(onion.as_ptr(), 443, key.as_ptr()) }, 0);
        assert_eq!(status_now().error, error::TIMEOUT, "only a refusal of the key is about the key");
        engine::reset_for_test();
        let _ = std::fs::remove_file(blocker);
    }

    /// The group a hedge was won in stays for the service and key it won for,
    /// and goes with them.
    #[test]
    fn the_connect_group_goes_with_its_target() {
        let _turn = SERIAL.lock().unwrap_or_else(|p| p.into_inner());
        engine::reset_for_test();
        let (blocker, bad) = unusable_dir("group");
        assert_eq!(unsafe { nox_tor_start(bad.as_ptr(), bad.as_ptr()) }, 0);
        assert_eq!(wait_for(status::state::FAILED).state, status::state::FAILED);
        let onion = CString::new(ONION).unwrap();
        let other = CString::new(onion::onion_from_pubkey(&[0u8; 32])).unwrap();
        let (key, other_key) = ([1u8; 32], [2u8; 32]);
        let won = arti_client::IsolationToken::new();
        let set = |host: &CString, key: &[u8; 32]| unsafe { nox_tor_set_target(host.as_ptr(), 443, key.as_ptr()) };

        assert_eq!(set(&onion, &key), 0);
        engine::connect_group_won_for_test(won);
        assert_eq!(set(&onion, &key), 0);
        assert_eq!(engine::connect_group_for_test(), Some(won), "the same target again keeps it");
        assert_eq!(set(&onion, &other_key), 0);
        assert_eq!(engine::connect_group_for_test(), None, "another key forgets it");
        engine::connect_group_won_for_test(won);
        assert_eq!(set(&other, &other_key), 0);
        assert_eq!(engine::connect_group_for_test(), None, "another service forgets it");
        engine::connect_group_won_for_test(won);
        assert_eq!(nox_tor_clear_target(), 0);
        assert_eq!(engine::connect_group_for_test(), None, "clearing the target forgets it");
        engine::reset_for_test();
        let _ = std::fs::remove_file(blocker);
    }

    fn record() -> Option<channel::dart::PostFn> {
        Some(channel::registry::tests::record)
    }

    const PORT: i64 = channel::registry::tests::LIVE;

    /// The code of the handle's CLOSED, waiting for it ten seconds at most.
    fn closed(handle: i64) -> Option<i32> {
        for _ in 0..500 {
            let seen = channel::registry::tests::seen(handle);
            if let Some((_, _, code)) = seen.iter().find(|(kind, _, _)| *kind == channel::event::CLOSED) {
                return Some(*code);
            }
            std::thread::sleep(Duration::from_millis(20));
        }
        None
    }

    fn open_onion(host: &str, budget_ms: u32) -> i64 {
        let host = CString::new(host).unwrap();
        let (seed, key) = ([1u8; 32], [2u8; 32]);
        let handle =
            unsafe { nox_chan_open(1, host.as_ptr(), 443, seed.as_ptr(), key.as_ptr(), budget_ms, record(), PORT) };
        assert!(handle > 0, "{handle}");
        handle
    }

    #[test]
    fn a_channel_is_refused_without_every_argument() {
        let invalid = i64::from(code::RET_INVALID_ARGUMENT);
        let host = CString::new("127.0.0.1").unwrap();
        let empty = CString::new("").unwrap();
        let (seed, key, zero) = ([1u8; 32], [2u8; 32], [0u8; 32]);
        let not_utf8 = [0xffu8, 0xfe, 0];
        let open = |kind, host: *const c_char, port, seed: *const u8, key: *const u8, ms, post| unsafe {
            nox_chan_open(kind, host, port, seed, key, ms, post, PORT)
        };
        let null = std::ptr::null();
        for (refused, why) in [
            (open(0, host.as_ptr(), 443, seed.as_ptr(), key.as_ptr(), 1000, None), "nothing to post with"),
            (
                unsafe { nox_chan_open(0, host.as_ptr(), 443, seed.as_ptr(), key.as_ptr(), 1000, record(), 0) },
                "no port to post to",
            ),
            (open(0, null as *const c_char, 443, seed.as_ptr(), key.as_ptr(), 1000, record()), "no host"),
            (open(0, empty.as_ptr(), 443, seed.as_ptr(), key.as_ptr(), 1000, record()), "an empty host"),
            (
                open(0, not_utf8.as_ptr() as *const c_char, 443, seed.as_ptr(), key.as_ptr(), 1000, record()),
                "not UTF-8",
            ),
            (open(0, host.as_ptr(), 0, seed.as_ptr(), key.as_ptr(), 1000, record()), "port 0"),
            (open(0, host.as_ptr(), 443, null, key.as_ptr(), 1000, record()), "no seed"),
            (open(0, host.as_ptr(), 443, seed.as_ptr(), null, 1000, record()), "no server key"),
            (open(0, host.as_ptr(), 443, seed.as_ptr(), key.as_ptr(), 0, record()), "no time at all"),
            (open(2, host.as_ptr(), 443, seed.as_ptr(), key.as_ptr(), 1000, record()), "an unknown kind"),
            (open(-1, host.as_ptr(), 443, seed.as_ptr(), key.as_ptr(), 1000, record()), "a negative kind"),
            (open(0, host.as_ptr(), 443, zero.as_ptr(), key.as_ptr(), 1000, record()), "an all-zero seed"),
        ] {
            assert_eq!(refused, invalid, "{why}");
        }
    }

    #[test]
    fn a_handle_that_is_not_there_finds_nothing() {
        let closed_handle = i64::from(code::RET_CLOSED);
        for handle in [0, -1, i64::MAX] {
            assert_eq!(unsafe { nox_chan_write(handle, b"x".as_ptr(), 1) }, closed_handle, "{handle}");
            assert_eq!(unsafe { nox_chan_write(handle, std::ptr::null(), 0) }, closed_handle, "{handle}");
            assert_eq!(nox_chan_ack(handle, 0), code::RET_CLOSED);
            assert_eq!(nox_chan_flush(handle, 1), code::RET_CLOSED);
            assert_eq!(nox_chan_shutdown_write(handle), code::RET_CLOSED);
            assert_eq!(nox_chan_close(handle), code::RET_CLOSED);
        }
        // Bytes that are not there are a bad argument before any handle is looked at.
        assert_eq!(unsafe { nox_chan_write(i64::MAX, std::ptr::null(), 5) }, i64::from(code::RET_INVALID_ARGUMENT));
        // Nothing to free is nothing to do.
        unsafe { nox_chan_buf_free(std::ptr::null_mut(), 0) };
    }

    #[test]
    fn an_onion_channel_closes_as_not_ready_until_tor_is_ready() {
        let _turn = SERIAL.lock().unwrap_or_else(|p| p.into_inner());
        engine::reset_for_test();
        let handle = open_onion(ONION, 1000);
        assert_eq!(closed(handle), Some(code::TOR_NOT_READY), "never started");
        let (blocker, bad) = unusable_dir("chan_failed");
        assert_eq!(unsafe { nox_tor_start(bad.as_ptr(), bad.as_ptr()) }, 0);
        assert_eq!(wait_for(status::state::FAILED).state, status::state::FAILED);
        let handle = open_onion(ONION, 1000);
        assert_eq!(closed(handle), Some(code::TOR_NOT_READY), "failed");
        // A broken address is broken whether or not Tor is up.
        let handle = open_onion("nope.onion", 1000);
        assert_eq!(closed(handle), Some(code::TOR_ONION_INVALID));
        engine::reset_for_test();
        let _ = std::fs::remove_file(blocker);
    }

    /// An onion channel runs on the Tor client's runtime, and goes with it: a
    /// stop under a channel still ends that channel with its CLOSED.
    #[test]
    fn an_onion_channel_ends_when_its_tor_client_stops() {
        let _turn = SERIAL.lock().unwrap_or_else(|p| p.into_inner());
        engine::reset_for_test();
        let dir = std::env::temp_dir().join(format!("nox_tor_chan_{}", std::process::id()));
        let state = CString::new(dir.join("state").to_str().unwrap()).unwrap();
        let cache = CString::new(dir.join("cache").to_str().unwrap()).unwrap();
        assert_eq!(unsafe { nox_tor_start(state.as_ptr(), cache.as_ptr()) }, 0);
        // Ready as far as the channel can tell. The client itself is still
        // bootstrapping, and the connect waits for that: nowhere near done
        // when the stop comes.
        for _ in 0..500 {
            if engine::onion_context().is_some() {
                break;
            }
            engine::set_state_for_test(status::state::READY);
            std::thread::sleep(Duration::from_millis(10));
        }
        assert!(engine::onion_context().is_some(), "no client was built");
        let handle = open_onion(ONION, 60_000);
        std::thread::sleep(Duration::from_millis(200));
        assert_eq!(channel::registry::tests::seen(handle), [], "nothing before the connect is through");
        nox_tor_stop();
        assert_eq!(closed(handle), Some(code::NETWORK));
        engine::reset_for_test();
        let _ = std::fs::remove_dir_all(dir);
    }

    /// The app remembers a client the network refused by this string, and only
    /// a different one lets Tor start again. It must move with the pin: one
    /// left behind would keep Tor off after the very update meant to fix it.
    #[test]
    fn the_reported_version_is_the_arti_client_in_the_lock_file() {
        let lock = include_str!("../Cargo.lock");
        let pinned = lock
            .split("[[package]]")
            .find(|entry| entry.lines().any(|line| line.trim() == r#"name = "arti-client""#))
            .and_then(|entry| {
                entry.lines().find_map(|line| line.trim().strip_prefix(r#"version = ""#)?.strip_suffix('"'))
            })
            .expect("arti-client in Cargo.lock");
        assert_eq!(VERSION.to_str().unwrap(), format!("arti-client {pinned}"));
    }
}
