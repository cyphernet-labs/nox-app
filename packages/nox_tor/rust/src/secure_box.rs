//! RustSecureBox for Dart (phase 050): the four functions of the library the
//! channel check runs on, for what the app does with keys outside a channel -
//! making the device's pair once before its first pairing, and reading the
//! public key of the private one it keeps
//! (`specs/050-rust-secure-box/contracts/ffi-box.md`).
//!
//! Returns: 0 success; `nox_box_check_signature` 1 valid, 0 invalid; -1 an
//! invalid argument (a null pointer among them), -2 no random bytes, -3 an
//! internal error or a panic, which never crosses into Dart. Every call is
//! short and synchronous, from any thread.

use std::panic::{catch_unwind, UnwindSafe};
use std::ptr;

use rust_secure_box as rsb;
use zeroize::Zeroizing;

const INVALID_ARGUMENT: i32 = -1;

fn box_guarded(f: impl FnOnce() -> Result<i32, rsb::Error> + UnwindSafe) -> i32 {
    match catch_unwind(f) {
        Ok(Ok(code)) => code,
        Ok(Err(e)) => e.code(),
        Err(_) => rsb::Error::Internal.code(),
    }
}

/// # Safety
/// `p` is null or points at N readable bytes.
unsafe fn read<const N: usize>(p: *const u8) -> Option<Zeroizing<[u8; N]>> {
    (!p.is_null()).then(|| Zeroizing::new(unsafe { ptr::read(p.cast::<[u8; N]>()) }))
}

/// # Safety
/// `p` points at `bytes.len()` writable bytes.
unsafe fn write(p: *mut u8, bytes: &[u8]) {
    unsafe { ptr::copy_nonoverlapping(bytes.as_ptr(), p, bytes.len()) };
}

/// A new pair: the private key in `private_out[32]`, the public in
/// `public_out[32]`.
///
/// # Safety
/// Each pointer is null or points at 32 writable bytes.
#[no_mangle]
pub unsafe extern "C" fn nox_box_generate_keys(private_out: *mut u8, public_out: *mut u8) -> i32 {
    if private_out.is_null() || public_out.is_null() {
        return INVALID_ARGUMENT;
    }
    box_guarded(|| {
        let pair = rsb::generate_keys()?;
        unsafe {
            write(private_out, &pair.private_key);
            write(public_out, &pair.public_key);
        }
        Ok(0)
    })
}

/// A new challenge in `challenge_out[32]` and the public key of `private_key`
/// in `public_out[32]`.
///
/// # Safety
/// `private_key` is null or points at 32 readable bytes; each output is null
/// or points at 32 writable ones.
#[no_mangle]
pub unsafe extern "C" fn nox_box_get_challenge(
    private_key: *const u8,
    challenge_out: *mut u8,
    public_out: *mut u8,
) -> i32 {
    let Some(own) = (unsafe { read::<32>(private_key) }) else {
        return INVALID_ARGUMENT;
    };
    if challenge_out.is_null() || public_out.is_null() {
        return INVALID_ARGUMENT;
    }
    box_guarded(move || {
        let (challenge, public_key) = rsb::get_challenge(&own)?;
        unsafe {
            write(challenge_out, &challenge);
            write(public_out, &public_key);
        }
        Ok(0)
    })
}

/// The signature of `private_key` over `challenge` in `signature_out[64]`.
///
/// # Safety
/// `private_key` and `challenge` are null or point at 32 readable bytes each;
/// `signature_out` is null or points at 64 writable ones.
#[no_mangle]
pub unsafe extern "C" fn nox_box_sign_challenge(
    private_key: *const u8,
    challenge: *const u8,
    signature_out: *mut u8,
) -> i32 {
    let (Some(own), Some(theirs)) = (unsafe { read::<32>(private_key) }, unsafe { read::<32>(challenge) }) else {
        return INVALID_ARGUMENT;
    };
    if signature_out.is_null() {
        return INVALID_ARGUMENT;
    }
    box_guarded(move || {
        let signature = rsb::sign_challenge(&own, &theirs)?;
        unsafe { write(signature_out, &signature) };
        Ok(0)
    })
}

/// 1 when `signature` is `public_key`'s over `challenge`, 0 when it is not.
///
/// # Safety
/// `public_key` and `challenge` are null or point at 32 readable bytes each,
/// `signature` at 64.
#[no_mangle]
pub unsafe extern "C" fn nox_box_check_signature(
    public_key: *const u8,
    challenge: *const u8,
    signature: *const u8,
) -> i32 {
    let (Some(public_key), Some(challenge), Some(signature)) =
        (unsafe { read::<32>(public_key) }, unsafe { read::<32>(challenge) }, unsafe { read::<64>(signature) })
    else {
        return INVALID_ARGUMENT;
    };
    box_guarded(move || Ok(i32::from(rsb::check_signature(&public_key, &challenge, &signature)?)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_pair_signs_and_its_signature_checks_through_the_c_abi() {
        let (mut private_key, mut public_key) = ([0u8; 32], [0u8; 32]);
        assert_eq!(unsafe { nox_box_generate_keys(private_key.as_mut_ptr(), public_key.as_mut_ptr()) }, 0);
        let (mut challenge, mut again) = ([0u8; 32], [0u8; 32]);
        assert_eq!(
            unsafe { nox_box_get_challenge(private_key.as_ptr(), challenge.as_mut_ptr(), again.as_mut_ptr()) },
            0
        );
        assert_eq!(again, public_key, "the challenge comes with the pair's own public key");
        let mut signature = [0u8; 64];
        assert_eq!(
            unsafe { nox_box_sign_challenge(private_key.as_ptr(), challenge.as_ptr(), signature.as_mut_ptr()) },
            0
        );
        assert_eq!(unsafe { nox_box_check_signature(public_key.as_ptr(), challenge.as_ptr(), signature.as_ptr()) }, 1);
        signature[0] ^= 1;
        assert_eq!(unsafe { nox_box_check_signature(public_key.as_ptr(), challenge.as_ptr(), signature.as_ptr()) }, 0);
    }

    #[test]
    fn a_null_pointer_is_an_invalid_argument() {
        let null = ptr::null_mut::<u8>();
        let (mut a, mut b, mut sig) = ([0u8; 32], [0u8; 32], [0u8; 64]);
        assert_eq!(unsafe { nox_box_generate_keys(null, b.as_mut_ptr()) }, -1);
        assert_eq!(unsafe { nox_box_generate_keys(a.as_mut_ptr(), null) }, -1);
        assert_eq!(unsafe { nox_box_get_challenge(null, a.as_mut_ptr(), b.as_mut_ptr()) }, -1);
        assert_eq!(unsafe { nox_box_get_challenge(a.as_ptr(), null, b.as_mut_ptr()) }, -1);
        assert_eq!(unsafe { nox_box_sign_challenge(a.as_ptr(), null, sig.as_mut_ptr()) }, -1);
        assert_eq!(unsafe { nox_box_sign_challenge(a.as_ptr(), b.as_ptr(), null) }, -1);
        assert_eq!(unsafe { nox_box_check_signature(a.as_ptr(), b.as_ptr(), null) }, -1);
    }
}
