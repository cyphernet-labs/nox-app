//! The C ABI of the WebAssembly build - how the server's Go copy calls the four
//! functions (`specs/050-rust-secure-box/contracts/rust-secure-box.md`).
//!
//! Every argument has a fixed size, so the host needs no allocator in here: it
//! writes the inputs into the exchange buffer `rsb_io` gives it, passes
//! pointers into that buffer and reads the outputs from the same place. One
//! instance serves one call at a time - the host keeps a pool of them - so the
//! buffer is never shared between two calls.
//!
//! Returns: 0 success; `rsb_check_signature` 1 valid, 0 invalid; -1 an invalid
//! argument, -2 no random bytes, -3 an internal error. A panic aborts, which is
//! a trap: the host turns it into an error and throws the instance away.

use std::cell::UnsafeCell;
use std::ptr;

use crate::{Error, CHALLENGE_LEN, PRIVATE_KEY_LEN, PUBLIC_KEY_LEN, SIGNATURE_LEN};

/// Room for the largest call: a public key, a challenge and a signature in,
/// with space to spare.
const IO_LEN: usize = 256;

struct Io(UnsafeCell<[u8; IO_LEN]>);

// SAFETY: a WebAssembly instance runs one call at a time; nothing in here ever
// runs on two threads.
unsafe impl Sync for Io {}

static IO: Io = Io(UnsafeCell::new([0; IO_LEN]));

/// The exchange buffer: 256 bytes the host reads and writes the arguments in.
#[no_mangle]
pub extern "C" fn rsb_io() -> *mut u8 {
    IO.0.get().cast()
}

/// # Safety
/// `p` is null or points at `N` readable bytes.
unsafe fn read<const N: usize>(p: *const u8) -> Option<[u8; N]> {
    (!p.is_null()).then(|| unsafe { ptr::read(p.cast::<[u8; N]>()) })
}

/// # Safety
/// `p` is null or points at `bytes.len()` writable bytes.
unsafe fn write(p: *mut u8, bytes: &[u8]) -> bool {
    if p.is_null() {
        return false;
    }
    unsafe { ptr::copy_nonoverlapping(bytes.as_ptr(), p, bytes.len()) };
    true
}

/// # Safety
/// Each pointer is null or points at 32 writable bytes.
#[no_mangle]
pub unsafe extern "C" fn rsb_generate_keys(private_out: *mut u8, public_out: *mut u8) -> i32 {
    if private_out.is_null() || public_out.is_null() {
        return Error::InvalidArgument.code();
    }
    match crate::generate_keys() {
        Ok(pair) => {
            unsafe {
                write(private_out, &pair.private_key);
                write(public_out, &pair.public_key);
            }
            0
        }
        Err(e) => e.code(),
    }
}

/// # Safety
/// `private_key` points at 32 readable bytes; each output at 32 writable ones.
#[no_mangle]
pub unsafe extern "C" fn rsb_get_challenge(private_key: *const u8, challenge_out: *mut u8, public_out: *mut u8) -> i32 {
    let Some(own) = (unsafe { read::<PRIVATE_KEY_LEN>(private_key) }) else {
        return Error::InvalidArgument.code();
    };
    if challenge_out.is_null() || public_out.is_null() {
        return Error::InvalidArgument.code();
    }
    match crate::get_challenge(&own) {
        Ok((challenge, public_key)) => {
            unsafe {
                write(challenge_out, &challenge);
                write(public_out, &public_key);
            }
            0
        }
        Err(e) => e.code(),
    }
}

/// # Safety
/// `private_key` and `challenge` point at 32 readable bytes each,
/// `signature_out` at 64 writable ones.
#[no_mangle]
pub unsafe extern "C" fn rsb_sign_challenge(
    private_key: *const u8,
    challenge: *const u8,
    signature_out: *mut u8,
) -> i32 {
    let (Some(own), Some(theirs)) =
        (unsafe { read::<PRIVATE_KEY_LEN>(private_key) }, unsafe { read::<CHALLENGE_LEN>(challenge) })
    else {
        return Error::InvalidArgument.code();
    };
    match crate::sign_challenge(&own, &theirs) {
        Ok(signature) => {
            if unsafe { write(signature_out, &signature) } {
                0
            } else {
                Error::InvalidArgument.code()
            }
        }
        Err(e) => e.code(),
    }
}

/// # Safety
/// `public_key` and `challenge` point at 32 readable bytes each, `signature`
/// at 64.
#[no_mangle]
pub unsafe extern "C" fn rsb_check_signature(public_key: *const u8, challenge: *const u8, signature: *const u8) -> i32 {
    let (Some(public_key), Some(challenge), Some(signature)) =
        (unsafe { read::<PUBLIC_KEY_LEN>(public_key) }, unsafe { read::<CHALLENGE_LEN>(challenge) }, unsafe {
            read::<SIGNATURE_LEN>(signature)
        })
    else {
        return Error::InvalidArgument.code();
    };
    match crate::check_signature(&public_key, &challenge, &signature) {
        Ok(valid) => i32::from(valid),
        Err(e) => e.code(),
    }
}
