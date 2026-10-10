//! The vault (phase 048): what the app keeps on the device's disk, sealed under
//! the local-database key.
//!
//! The key is 32 random bytes the app keeps in the system keystore, for this
//! device only, and hands over with `nox_vault_set_key` once it has read them.
//! Here it lives in one buffer of the process, overwritten in place when a new
//! key is set and wiped by `nox_vault_clear`. Each call builds the ring key it
//! needs from it under the lock and lets the lock go before the work.
//!
//! Two kinds of thing are sealed, both with ChaCha20-Poly1305:
//!
//! - **A record** - a line of the local database - under the key itself, with a
//!   fresh random nonce: `nonce (12) ‖ ciphertext ‖ tag (16)`.
//! - **A chunk of a file** - an attachment, a copy of an outgoing file - under
//!   the file's own key, `HKDF-SHA256(key, info = "nox/devfile/v1|" ‖ name)`
//!   with no salt (RFC 5869: HashLen zeros); the nonce is `0⁴ ‖ index (8, BE)`
//!   and the AAD `index (8, BE) ‖ last (1)`: `ciphertext ‖ tag (16)`. A chunk
//!   opens only in its own file, at its own place, and as what it was sealed as
//!   (the last one or not), so a file cut short at a chunk boundary shows when
//!   its new end is opened as the last chunk. The file around the chunks (the
//!   header, the size of a chunk) is the app's: the server's format (047) under
//!   a key of the device.
//!
//! The nonce of a chunk is its index, so a name names ONE content, and a chunk
//! is sealed once it is whole (the last one once the file is): different bytes
//! at the same index of the same name - another file under a name used before,
//! or the start of a chunk sealed early and again once complete - reuse a nonce
//! under one key, which ChaCha20-Poly1305 does not survive. The same bytes
//! sealed again - a download repeated from where it broke off - give the same
//! chunk and reveal nothing.
//!
//! A forged record or chunk and one sealed under another key are one refusal:
//! there is no telling them apart, and neither opens.
//!
//! The contract is `specs/048-device-data-at-rest/contracts/ffi-vault.md`.

use std::sync::Mutex;
use std::{ptr, slice};

use ring::aead::{Aad, LessSafeKey, Nonce, Tag, UnboundKey, CHACHA20_POLY1305, NONCE_LEN};
use ring::hkdf::{Salt, HKDF_SHA256};
use ring::rand::{SecureRandom, SystemRandom};
use zeroize::{Zeroize, Zeroizing};

use crate::engine::lock;

/// The local-database key.
pub const KEY_LEN: usize = 32;

/// What sealing adds to a chunk: its tag.
pub const TAG_LEN: usize = 16;

/// What sealing adds to a record: its nonce and its tag.
pub const RECORD_OVERHEAD: usize = NONCE_LEN + TAG_LEN;

/// The info of a file key, before the file's name.
pub const FILE_KEY_INFO: &[u8] = b"nox/devfile/v1|";

/// The returns of the vault's C ABI.
pub mod code {
    pub const OK: i32 = 0;
    /// Forged, cut short, or sealed under another key: it does not open.
    pub const RET_FORGED: i32 = -4;
    pub const RET_INVALID_ARGUMENT: i32 = -7;
    /// No key is set: none was, or it was cleared.
    pub const RET_NO_KEY: i32 = -9;
    /// A panic, or no randomness from the system. The contract names only the
    /// three above; this is the channel's INTERNAL, whose -7 and -9 they share.
    pub const RET_INTERNAL: i32 = -11;
}

/// The key, while the app has one set.
static KEY: Mutex<Option<Zeroizing<[u8; KEY_LEN]>>> = Mutex::new(None);

/// Sets the key, over one set before. An all-zero key is refused: no real key
/// is one, and a buffer the app forgot to fill is. A refused key leaves the
/// vault as it was.
pub fn set_key(key: &[u8; KEY_LEN]) -> i32 {
    if key.iter().all(|&b| b == 0) {
        return code::RET_INVALID_ARGUMENT;
    }
    let mut slot = lock(&KEY);
    // Straight from the caller's bytes into the buffer the key lives in, over
    // the key before: no copy of it is left on this stack.
    slot.get_or_insert_with(|| Zeroizing::new([0; KEY_LEN])).copy_from_slice(key);
    code::OK
}

/// Wipes the key where it lies. Every seal and open is `RET_NO_KEY` until the
/// next `set_key`.
pub fn clear() {
    let mut slot = lock(&KEY);
    if let Some(key) = slot.as_mut() {
        key.zeroize();
    }
    *slot = None;
}

/// Seals a record: `nonce (12) ‖ ciphertext ‖ tag (16)`.
pub fn seal(data: &[u8]) -> Result<Vec<u8>, i32> {
    let key = with_key(record_key)?;
    let mut nonce = [0u8; NONCE_LEN];
    SystemRandom::new().fill(&mut nonce).map_err(|_| code::RET_INTERNAL)?;
    seal_record(&key, nonce, data)
}

/// Opens a record `seal` made.
pub fn open(sealed: &[u8]) -> Result<Vec<u8>, i32> {
    let key = with_key(record_key)?;
    open_record(&key, sealed)
}

/// Seals chunk `index` of the file `name`: `ciphertext ‖ tag (16)`.
pub fn seal_chunk(name: &str, index: u64, last: bool, data: &[u8]) -> Result<Vec<u8>, i32> {
    check_name(name)?;
    let key = with_key(|key| file_key(key, name))?;
    seal_chunk_with(&key, index, last, data)
}

/// Opens chunk `index` of the file `name`, which must have been sealed at that
/// index of that file, and as the last chunk or not as `last` says.
pub fn open_chunk(name: &str, index: u64, last: bool, sealed: &[u8]) -> Result<Vec<u8>, i32> {
    check_name(name)?;
    let key = with_key(|key| file_key(key, name))?;
    open_chunk_with(&key, index, last, sealed)
}

/// The `last` of the C ABI: 0 or 1. Anything else is a binding that is wrong
/// about the chunk too.
pub fn flag(last: i32) -> Option<bool> {
    match last {
        0 => Some(false),
        1 => Some(true),
        _ => None,
    }
}

/// An empty name would give every file without one the same key.
fn check_name(name: &str) -> Result<(), i32> {
    if name.is_empty() {
        Err(code::RET_INVALID_ARGUMENT)
    } else {
        Ok(())
    }
}

/// Runs `f` over the key under the lock. What `f` builds from it - a ring
/// key - is all that leaves; the work with that runs after the lock is gone.
fn with_key<T>(f: impl FnOnce(&[u8; KEY_LEN]) -> Result<T, i32>) -> Result<T, i32> {
    let slot = lock(&KEY);
    f(slot.as_deref().ok_or(code::RET_NO_KEY)?)
}

/// The key of records: the key itself.
fn record_key(key: &[u8; KEY_LEN]) -> Result<LessSafeKey, i32> {
    UnboundKey::new(&CHACHA20_POLY1305, key).map(LessSafeKey::new).map_err(|_| code::RET_INTERNAL)
}

/// The key of one file's chunks: `HKDF-SHA256(key, info = FILE_KEY_INFO ‖
/// name)`. No salt: RFC 5869 then takes HashLen zeros, which HMAC pads an
/// empty key to as well - Go's `hkdf` with a nil salt gives the same key.
fn file_key(key: &[u8; KEY_LEN], name: &str) -> Result<LessSafeKey, i32> {
    let prk = Salt::new(HKDF_SHA256, &[]).extract(key);
    let info = [FILE_KEY_INFO, name.as_bytes()];
    let okm = prk.expand(&info, &CHACHA20_POLY1305).map_err(|_| code::RET_INTERNAL)?;
    Ok(LessSafeKey::new(UnboundKey::from(okm)))
}

fn seal_record(key: &LessSafeKey, nonce: [u8; NONCE_LEN], data: &[u8]) -> Result<Vec<u8>, i32> {
    // Exactly the size of the result, so handing it over copies nothing.
    let mut out = Vec::with_capacity(RECORD_OVERHEAD + data.len());
    out.extend_from_slice(&nonce);
    out.extend_from_slice(data);
    let nonce = Nonce::assume_unique_for_key(nonce);
    let tag =
        key.seal_in_place_separate_tag(nonce, Aad::empty(), &mut out[NONCE_LEN..]).map_err(|_| code::RET_INTERNAL)?;
    out.extend_from_slice(tag.as_ref());
    Ok(out)
}

fn open_record(key: &LessSafeKey, sealed: &[u8]) -> Result<Vec<u8>, i32> {
    let (nonce, rest) = sealed.split_first_chunk::<NONCE_LEN>().ok_or(code::RET_FORGED)?;
    open_in(key, *nonce, Aad::empty(), rest)
}

fn seal_chunk_with(key: &LessSafeKey, index: u64, last: bool, data: &[u8]) -> Result<Vec<u8>, i32> {
    let mut out = Vec::with_capacity(data.len() + TAG_LEN);
    out.extend_from_slice(data);
    let nonce = Nonce::assume_unique_for_key(chunk_nonce(index));
    let tag =
        key.seal_in_place_separate_tag(nonce, chunk_aad(index, last), &mut out).map_err(|_| code::RET_INTERNAL)?;
    out.extend_from_slice(tag.as_ref());
    Ok(out)
}

fn open_chunk_with(key: &LessSafeKey, index: u64, last: bool, sealed: &[u8]) -> Result<Vec<u8>, i32> {
    open_in(key, chunk_nonce(index), chunk_aad(index, last), sealed)
}

/// `0⁴ ‖ index (8, BE)`.
fn chunk_nonce(index: u64) -> [u8; NONCE_LEN] {
    let mut nonce = [0u8; NONCE_LEN];
    nonce[4..].copy_from_slice(&index.to_be_bytes());
    nonce
}

/// `index (8, BE) ‖ last (1)`.
fn chunk_aad(index: u64, last: bool) -> Aad<[u8; 9]> {
    let mut aad = [0u8; 9];
    aad[..8].copy_from_slice(&index.to_be_bytes());
    aad[8] = u8::from(last);
    Aad::from(aad)
}

/// Opens `ciphertext ‖ tag` into a buffer of exactly the plaintext's size. A
/// refusal leaves nothing behind: ring zeroes what it decrypted, and the
/// buffer goes.
fn open_in(
    key: &LessSafeKey,
    nonce: [u8; NONCE_LEN],
    aad: Aad<impl AsRef<[u8]>>,
    sealed: &[u8],
) -> Result<Vec<u8>, i32> {
    let (ciphertext, tag) = sealed.split_last_chunk::<TAG_LEN>().ok_or(code::RET_FORGED)?;
    let mut plain = ciphertext.to_vec();
    let nonce = Nonce::assume_unique_for_key(nonce);
    key.open_in_place_separate_tag(nonce, aad, Tag::from(*tag), &mut plain, 0..).map_err(|_| code::RET_FORGED)?;
    Ok(plain)
}

/// The C ABI's half of a seal or an open: checks the buffers, runs `op` over
/// the input and hands its output over - a heap buffer the caller frees with
/// `nox_chan_buf_free`, the allocator of the channel's buffers; an empty
/// output is null. Only a 0 return hands a buffer over.
///
/// # Safety
/// `data` points at `len` bytes, or `len` is 0; `out` and `out_len` are null
/// or point at writable slots.
pub(crate) unsafe fn call(
    data: *const u8,
    len: usize,
    out: *mut *mut u8,
    out_len: *mut usize,
    op: impl FnOnce(&[u8]) -> Result<Vec<u8>, i32>,
) -> i32 {
    if out.is_null() || out_len.is_null() || (data.is_null() && len != 0) || len > isize::MAX as usize {
        return code::RET_INVALID_ARGUMENT;
    }
    *out = ptr::null_mut();
    *out_len = 0;
    let input = if len == 0 { &[][..] } else { slice::from_raw_parts(data, len) };
    match op(input) {
        Ok(bytes) if bytes.is_empty() => code::OK,
        Ok(bytes) => {
            let bytes = bytes.into_boxed_slice();
            *out_len = bytes.len();
            *out = Box::into_raw(bytes).cast::<u8>();
            code::OK
        }
        Err(code) => code,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use data_encoding::HEXLOWER;
    use ring::hmac;

    // Vectors from two implementations other than ring: Node's crypto
    // (OpenSSL) and Go's golang.org/x/crypto, which agree byte for byte.
    const VECTOR_RECORD: &str =
        "a0a1a2a3a4a5a6a7a8a9aaabd86d01d5873a7f086e9b06ffda2663d9c47d632d5fe5a75c81a4df4ab49d704d";
    const VECTOR_NAME: &str = "nox_outbox/фото ✓.jpg";
    const VECTOR_FILE_KEY: &str = "ad5317d3c45af86a392c012da455bea9bb4e6f8cbe6115eb457acc9de4e9ebca";
    const VECTOR_CHUNKS: [(u64, bool, &str, &str); 3] = [
        (0, false, "chunk zero", "f92a51a169d07232dfacd3ac1010f9a5bfc46c3d809039817ce6"),
        (1, true, "the last chunk", "0c500b891281ca1cbc2ceb45a011fc69cd63769e838540c0146d1dda5fd1"),
        (0x0102_0304_0506_0708, true, "", "b3b44fc01da87fa76aaaf3256346918e"),
    ];

    fn vector_key() -> [u8; KEY_LEN] {
        std::array::from_fn(|i| i as u8 + 1)
    }

    fn hex(s: &str) -> Vec<u8> {
        HEXLOWER.decode(s.as_bytes()).unwrap()
    }

    #[test]
    fn a_record_is_its_nonce_the_ciphertext_and_the_tag() {
        let key = record_key(&vector_key()).unwrap();
        let nonce = std::array::from_fn(|i| 0xa0 + i as u8);
        let sealed = seal_record(&key, nonce, b"NOX vault record").unwrap();
        assert_eq!(sealed, hex(VECTOR_RECORD));
        assert_eq!(open_record(&key, &sealed).unwrap(), b"NOX vault record");
    }

    /// RFC 5869 by hand over HMAC-SHA256: extract with HashLen zeros as the
    /// salt, one block of expand. The key a format change would move.
    #[test]
    fn the_file_key_is_hkdf_sha256_of_the_key_over_the_name() {
        let prk = hmac::sign(&hmac::Key::new(hmac::HMAC_SHA256, &[0u8; 32]), &vector_key());
        let mut info = FILE_KEY_INFO.to_vec();
        info.extend_from_slice(VECTOR_NAME.as_bytes());
        info.push(1);
        let okm = hmac::sign(&hmac::Key::new(hmac::HMAC_SHA256, prk.as_ref()), &info);
        assert_eq!(okm.as_ref(), hex(VECTOR_FILE_KEY));

        let derived = file_key(&vector_key(), VECTOR_NAME).unwrap();
        let by_hand = LessSafeKey::new(UnboundKey::new(&CHACHA20_POLY1305, okm.as_ref()).unwrap());
        for (index, last, plain, _) in VECTOR_CHUNKS {
            assert_eq!(
                seal_chunk_with(&derived, index, last, plain.as_bytes()),
                seal_chunk_with(&by_hand, index, last, plain.as_bytes())
            );
        }
    }

    #[test]
    fn chunks_are_the_vectors_byte_for_byte() {
        let key = file_key(&vector_key(), VECTOR_NAME).unwrap();
        for (index, last, plain, sealed) in VECTOR_CHUNKS {
            assert_eq!(seal_chunk_with(&key, index, last, plain.as_bytes()).unwrap(), hex(sealed), "{index}");
            assert_eq!(open_chunk_with(&key, index, last, &hex(sealed)).unwrap(), plain.as_bytes(), "{index}");
        }
    }

    #[test]
    fn the_nonce_and_the_aad_of_a_chunk_carry_its_index_big_endian() {
        assert_eq!(chunk_nonce(0x0102_0304_0506_0708), [0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8]);
        assert_eq!(chunk_aad(0x0102_0304_0506_0708, true).as_ref(), [1, 2, 3, 4, 5, 6, 7, 8, 1]);
        assert_eq!(chunk_aad(7, false).as_ref(), [0, 0, 0, 0, 0, 0, 0, 7, 0]);
    }

    #[test]
    fn last_is_zero_or_one() {
        assert_eq!(flag(0), Some(false));
        assert_eq!(flag(1), Some(true));
        for other in [2, -1, i32::MAX, i32::MIN] {
            assert_eq!(flag(other), None, "{other}");
        }
    }

    #[test]
    fn too_short_to_hold_a_tag_is_forged_not_a_panic() {
        let key = file_key(&vector_key(), VECTOR_NAME).unwrap();
        for len in 0..TAG_LEN {
            assert_eq!(open_chunk_with(&key, 0, true, &vec![0; len]), Err(code::RET_FORGED), "{len}");
        }
        let key = record_key(&vector_key()).unwrap();
        for len in 0..RECORD_OVERHEAD {
            assert_eq!(open_record(&key, &vec![0; len]), Err(code::RET_FORGED), "{len}");
        }
    }
}
