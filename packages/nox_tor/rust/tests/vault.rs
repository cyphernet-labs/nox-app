//! The vault through the C ABI the app calls (048): records and file chunks
//! round, and every way one must not open - another key, a flipped bit, a cut,
//! another file, another index, the other `last` - plus the key's own life:
//! none, set, replaced, cleared.
//!
//! The key is process-wide, so the tests take turns. Outputs are taken the way
//! Dart takes them: copied, the buffer freed.

use std::ffi::{c_char, CString};
use std::ptr;
use std::sync::{Mutex, MutexGuard};

use nox_tor::vault::{code, RECORD_OVERHEAD, TAG_LEN};
use nox_tor::{
    nox_chan_buf_free, nox_vault_clear, nox_vault_open, nox_vault_open_chunk, nox_vault_seal, nox_vault_seal_chunk,
    nox_vault_set_key,
};

const KEY: [u8; 32] = [0x11; 32];
const OTHER_KEY: [u8; 32] = [0x22; 32];
const NAME: &str = "nox_attachments/f_0123456789abcdef.jpg";

/// One test at a time, each starting with `key` set (or none).
fn turn(key: Option<&[u8; 32]>) -> MutexGuard<'static, ()> {
    static SERIAL: Mutex<()> = Mutex::new(());
    let guard = SERIAL.lock().unwrap_or_else(|p| p.into_inner());
    nox_vault_clear();
    if let Some(key) = key {
        set_key(key);
    }
    guard
}

fn set_key(key: &[u8; 32]) {
    assert_eq!(unsafe { nox_vault_set_key(key.as_ptr()) }, code::OK);
}

/// A call's output copied out and freed, or its code.
fn taken(rc: i32, out: *mut u8, out_len: usize) -> Result<Vec<u8>, i32> {
    if rc != code::OK {
        assert!(out.is_null() && out_len == 0, "nothing handed over on {rc}");
        return Err(rc);
    }
    if out_len == 0 {
        assert!(out.is_null(), "an empty output is null");
        return Ok(Vec::new());
    }
    let bytes = unsafe { std::slice::from_raw_parts(out, out_len) }.to_vec();
    unsafe { nox_chan_buf_free(out, out_len) };
    Ok(bytes)
}

type RecordFn = unsafe extern "C" fn(*const u8, usize, *mut *mut u8, *mut usize) -> i32;
type ChunkFn = unsafe extern "C" fn(*const c_char, u64, i32, *const u8, usize, *mut *mut u8, *mut usize) -> i32;

fn record(f: RecordFn, data: &[u8]) -> Result<Vec<u8>, i32> {
    let (mut out, mut out_len) = (ptr::null_mut(), 0);
    let rc = unsafe { f(data.as_ptr(), data.len(), &mut out, &mut out_len) };
    taken(rc, out, out_len)
}

fn seal(data: &[u8]) -> Result<Vec<u8>, i32> {
    record(nox_vault_seal, data)
}

fn open(data: &[u8]) -> Result<Vec<u8>, i32> {
    record(nox_vault_open, data)
}

fn chunk(f: ChunkFn, name: &str, index: u64, last: bool, data: &[u8]) -> Result<Vec<u8>, i32> {
    let name = CString::new(name).unwrap();
    let (mut out, mut out_len) = (ptr::null_mut(), 0);
    let rc = unsafe { f(name.as_ptr(), index, i32::from(last), data.as_ptr(), data.len(), &mut out, &mut out_len) };
    taken(rc, out, out_len)
}

fn seal_chunk(name: &str, index: u64, last: bool, data: &[u8]) -> Result<Vec<u8>, i32> {
    chunk(nox_vault_seal_chunk, name, index, last, data)
}

fn open_chunk(name: &str, index: u64, last: bool, data: &[u8]) -> Result<Vec<u8>, i32> {
    chunk(nox_vault_open_chunk, name, index, last, data)
}

/// Every copy of `sealed` with one bit flipped, one byte at a time.
fn flipped(sealed: &[u8]) -> impl Iterator<Item = Vec<u8>> + '_ {
    (0..sealed.len()).map(|at| {
        let mut copy = sealed.to_vec();
        copy[at] ^= 0x01;
        copy
    })
}

// --- Records ---------------------------------------------------------------

#[test]
fn a_record_goes_round() {
    let _turn = turn(Some(&KEY));
    for plain in [&b"a message of the local database"[..], b"", &[0u8; 70_000]] {
        let sealed = seal(plain).unwrap();
        assert_eq!(sealed.len(), plain.len() + RECORD_OVERHEAD);
        assert_eq!(open(&sealed).unwrap(), plain);
    }
}

#[test]
fn two_seals_of_one_record_differ_from_the_nonce_on() {
    let _turn = turn(Some(&KEY));
    let (first, second) = (seal(b"same").unwrap(), seal(b"same").unwrap());
    assert_ne!(first[..12], second[..12], "a fresh nonce each time");
    assert_ne!(first[12..], second[12..]);
    assert_eq!(open(&first).unwrap(), open(&second).unwrap());
}

#[test]
fn a_record_under_another_key_is_forged() {
    let _turn = turn(Some(&KEY));
    let sealed = seal(b"secret").unwrap();
    set_key(&OTHER_KEY);
    assert_eq!(open(&sealed), Err(code::RET_FORGED));
}

#[test]
fn a_record_with_any_bit_flipped_or_cut_short_is_forged() {
    let _turn = turn(Some(&KEY));
    let sealed = seal(b"secret").unwrap();
    for forged in flipped(&sealed) {
        assert_eq!(open(&forged), Err(code::RET_FORGED));
    }
    for len in 0..sealed.len() {
        assert_eq!(open(&sealed[..len]), Err(code::RET_FORGED), "{len} bytes");
    }
}

// --- Chunks ----------------------------------------------------------------

#[test]
fn a_chunk_goes_round() {
    let _turn = turn(Some(&KEY));
    let full = vec![0xA5u8; 64 * 1024];
    for (index, last, plain) in
        [(0, false, &full[..]), (1, false, &full[..]), (2, true, &b"the tail"[..]), (0, true, b"")]
    {
        let sealed = seal_chunk(NAME, index, last, plain).unwrap();
        assert_eq!(sealed.len(), plain.len() + TAG_LEN);
        assert_eq!(open_chunk(NAME, index, last, &sealed).unwrap(), plain, "{index}");
    }
}

/// Deterministic: the same bytes at the same place of the same file are the
/// same chunk - a download repeated from where it broke off writes nothing new.
#[test]
fn a_chunk_sealed_again_is_the_same_chunk() {
    let _turn = turn(Some(&KEY));
    assert_eq!(seal_chunk(NAME, 3, false, b"bytes").unwrap(), seal_chunk(NAME, 3, false, b"bytes").unwrap());
}

#[test]
fn a_chunk_opens_only_as_what_it_was_sealed_as() {
    let _turn = turn(Some(&KEY));
    let inner = seal_chunk(NAME, 4, false, b"middle").unwrap();
    let last = seal_chunk(NAME, 4, true, b"end").unwrap();
    // A file cut at a chunk boundary: its new end was not sealed as the last.
    assert_eq!(open_chunk(NAME, 4, true, &inner), Err(code::RET_FORGED));
    // A last chunk with more said to follow it.
    assert_eq!(open_chunk(NAME, 4, false, &last), Err(code::RET_FORGED));
}

#[test]
fn a_chunk_opens_only_at_its_own_index() {
    let _turn = turn(Some(&KEY));
    let sealed = seal_chunk(NAME, 7, false, b"seventh").unwrap();
    for index in [0, 6, 8, 7 + (1 << 32), u64::MAX] {
        assert_eq!(open_chunk(NAME, index, false, &sealed), Err(code::RET_FORGED), "{index}");
    }
}

#[test]
fn a_chunk_opens_only_in_its_own_file() {
    let _turn = turn(Some(&KEY));
    let sealed = seal_chunk(NAME, 0, true, b"one file").unwrap();
    for other in ["nox_attachments/f_0123456789abcdef.png", "f_0123456789abcdef.jpg", "nox_attachments"] {
        assert_eq!(open_chunk(other, 0, true, &sealed), Err(code::RET_FORGED), "{other}");
    }
}

#[test]
fn a_chunk_under_another_key_is_forged() {
    let _turn = turn(Some(&KEY));
    let sealed = seal_chunk(NAME, 0, true, b"secret").unwrap();
    set_key(&OTHER_KEY);
    assert_eq!(open_chunk(NAME, 0, true, &sealed), Err(code::RET_FORGED));
}

#[test]
fn a_chunk_with_any_bit_flipped_or_cut_short_is_forged() {
    let _turn = turn(Some(&KEY));
    let sealed = seal_chunk(NAME, 0, true, b"secret").unwrap();
    for forged in flipped(&sealed) {
        assert_eq!(open_chunk(NAME, 0, true, &forged), Err(code::RET_FORGED));
    }
    for len in 0..sealed.len() {
        assert_eq!(open_chunk(NAME, 0, true, &sealed[..len]), Err(code::RET_FORGED), "{len} bytes");
    }
}

// --- The key -----------------------------------------------------------------

#[test]
fn without_a_key_nothing_seals_or_opens() {
    let _turn = turn(None);
    assert_eq!(seal(b"x"), Err(code::RET_NO_KEY));
    assert_eq!(open(&[0; 40]), Err(code::RET_NO_KEY));
    assert_eq!(seal_chunk(NAME, 0, true, b"x"), Err(code::RET_NO_KEY));
    assert_eq!(open_chunk(NAME, 0, true, &[0; 40]), Err(code::RET_NO_KEY));
}

#[test]
fn clear_wipes_the_key_and_only_the_same_key_brings_the_data_back() {
    let _turn = turn(Some(&KEY));
    let record = seal(b"kept").unwrap();
    let chunk = seal_chunk(NAME, 0, true, b"kept").unwrap();
    nox_vault_clear();
    assert_eq!(seal(b"x"), Err(code::RET_NO_KEY));
    assert_eq!(open(&record), Err(code::RET_NO_KEY));
    assert_eq!(open_chunk(NAME, 0, true, &chunk), Err(code::RET_NO_KEY));
    // A second clear is no error.
    nox_vault_clear();
    set_key(&KEY);
    assert_eq!(open(&record).unwrap(), b"kept");
    assert_eq!(open_chunk(NAME, 0, true, &chunk).unwrap(), b"kept");
}

#[test]
fn a_new_key_replaces_the_one_before() {
    let _turn = turn(Some(&KEY));
    let sealed = seal(b"under the first").unwrap();
    set_key(&OTHER_KEY);
    assert_eq!(open(&sealed), Err(code::RET_FORGED));
    set_key(&KEY);
    assert_eq!(open(&sealed).unwrap(), b"under the first");
}

#[test]
fn a_refused_key_leaves_the_vault_as_it_was() {
    let _turn = turn(Some(&KEY));
    let sealed = seal(b"still mine").unwrap();
    assert_eq!(unsafe { nox_vault_set_key(ptr::null()) }, code::RET_INVALID_ARGUMENT);
    assert_eq!(unsafe { nox_vault_set_key([0u8; 32].as_ptr()) }, code::RET_INVALID_ARGUMENT, "all zeros");
    assert_eq!(open(&sealed).unwrap(), b"still mine");

    nox_vault_clear();
    assert_eq!(unsafe { nox_vault_set_key([0u8; 32].as_ptr()) }, code::RET_INVALID_ARGUMENT);
    assert_eq!(seal(b"x"), Err(code::RET_NO_KEY));
}

// --- Arguments ---------------------------------------------------------------

#[test]
fn arguments_the_vault_does_not_take() {
    let _turn = turn(Some(&KEY));
    let invalid = Err(code::RET_INVALID_ARGUMENT);
    let (mut out, mut out_len) = (ptr::null_mut(), 0usize);
    let null = ptr::null::<u8>();
    for f in [nox_vault_seal as RecordFn, nox_vault_open] {
        // No room for the answer, or no bytes behind a length.
        assert_eq!(unsafe { f(b"x".as_ptr(), 1, ptr::null_mut(), &mut out_len) }, code::RET_INVALID_ARGUMENT);
        assert_eq!(unsafe { f(b"x".as_ptr(), 1, &mut out, ptr::null_mut()) }, code::RET_INVALID_ARGUMENT);
        assert_eq!(unsafe { f(null, 1, &mut out, &mut out_len) }, code::RET_INVALID_ARGUMENT);
    }
    // No bytes and no length is an empty record.
    let rc = unsafe { nox_vault_seal(null, 0, &mut out, &mut out_len) };
    let sealed = taken(rc, out, out_len).unwrap();
    assert_eq!(open(&sealed).unwrap(), b"");

    let name = CString::new(NAME).unwrap();
    let not_utf8 = [0xffu8, 0xfe, 0];
    for f in [nox_vault_seal_chunk as ChunkFn, nox_vault_open_chunk] {
        let call = |name: *const c_char, last: i32| {
            let (mut out, mut out_len) = (ptr::null_mut(), 0usize);
            let rc = unsafe { f(name, 0, last, b"0123456789abcdef!".as_ptr(), 17, &mut out, &mut out_len) };
            taken(rc, out, out_len)
        };
        assert_eq!(call(ptr::null(), 1), invalid, "no name");
        assert_eq!(call(not_utf8.as_ptr().cast(), 1), invalid, "not UTF-8");
        assert_eq!(call(c"".as_ptr(), 1), invalid, "an empty name");
        for last in [2, -1, i32::MAX] {
            assert_eq!(call(name.as_ptr(), last), invalid, "last {last}");
        }
        assert_eq!(unsafe { f(name.as_ptr(), 0, 1, null, 1, &mut out, &mut out_len) }, code::RET_INVALID_ARGUMENT);
        assert_eq!(
            unsafe { f(name.as_ptr(), 0, 1, b"x".as_ptr(), 1, ptr::null_mut(), &mut out_len) },
            code::RET_INVALID_ARGUMENT
        );
    }
    // Freeing nothing is nothing to do.
    unsafe { nox_chan_buf_free(ptr::null_mut(), 0) };
}

// --- Vectors -------------------------------------------------------------------

/// Sealed by Node's crypto (OpenSSL) and Go's golang.org/x/crypto, which
/// agree byte for byte: the format as documented, not as ring happens to do it.
#[test]
fn what_another_implementation_sealed_opens_here() {
    let key: [u8; 32] = std::array::from_fn(|i| i as u8 + 1);
    let _turn = turn(Some(&key));
    let hex = |s: &str| data_encoding::HEXLOWER.decode(s.as_bytes()).unwrap();
    let record = hex("a0a1a2a3a4a5a6a7a8a9aaabd86d01d5873a7f086e9b06ffda2663d9c47d632d5fe5a75c81a4df4ab49d704d");
    assert_eq!(open(&record).unwrap(), b"NOX vault record");
    let name = "nox_outbox/фото ✓.jpg";
    for (index, last, plain, sealed) in [
        (0, false, "chunk zero", "f92a51a169d07232dfacd3ac1010f9a5bfc46c3d809039817ce6"),
        (1, true, "the last chunk", "0c500b891281ca1cbc2ceb45a011fc69cd63769e838540c0146d1dda5fd1"),
        (0x0102_0304_0506_0708, true, "", "b3b44fc01da87fa76aaaf3256346918e"),
    ] {
        assert_eq!(open_chunk(name, index, last, &hex(sealed)).unwrap(), plain.as_bytes(), "{index}");
        assert_eq!(seal_chunk(name, index, last, plain.as_bytes()).unwrap(), hex(sealed), "{index}");
    }
}
