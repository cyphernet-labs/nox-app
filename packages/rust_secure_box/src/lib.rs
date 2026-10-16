//! RustSecureBox: the keys and signatures behind the check every NOX connection
//! passes (`POST /auth`, then `POST /auth2`, right after TLS 1.3).
//!
//! ONE library, the same source on both sides:
//!
//! - the app links it into its Rust module (`packages/nox_tor`) and calls the
//!   four functions below directly;
//! - the server runs it as WebAssembly translated into Go (`build-wasm.sh`,
//!   `client_backend/internal/securebox`), through the C ABI in `wasm.rs`.
//!
//! What it does is keys and signatures, and nothing else. Who connects, what
//! goes over the wire and who is let in are the app's and the server's
//! business. The interface is fixed by `specs/050-rust-secure-box/contracts/
//! rust-secure-box.md`; an implementation behind it must be:
//!
//! - **stateless** - it keeps nothing between calls, every key is passed in;
//! - **thread-safe** - any number of threads may call it at once;
//! - **computation only** - no files, no network, no calls into the system.
//!   The one thing that comes from outside is random bytes: from the system in
//!   the app, from the host (`env.rsb_random`) in WebAssembly (`random.rs`).
//!
//! ⚠️ This is the STUB (`stub.rs`). The real RustSecureBox - written by the
//! customer's developer - is Ed25519 as in RFC 8032, with the same sizes: a
//! 32-byte private key (the seed), a 32-byte public key and a 64-byte
//! signature, the same logic and the same keys as the check it replaced. The
//! stub keeps the sizes and the behaviour - its own signature passes, any
//! other does not - but not the strength: anyone who knows a public key can
//! forge its signatures. The server says so in its log and on its service page
//! while the stub is in (it recognises the stub by `PROBE_PRIVATE_KEY`).
//! Public keys of the stub match neither Ed25519 nor the real box, so every
//! device pairs again when the stub goes in and again when it goes out.

mod random;
mod stub;
#[cfg(target_arch = "wasm32")]
mod wasm;

use std::fmt;

use zeroize::Zeroize;

/// A private key: 32 bytes.
pub const PRIVATE_KEY_LEN: usize = 32;
/// A public key: 32 bytes.
pub const PUBLIC_KEY_LEN: usize = 32;
/// A challenge: 32 random bytes.
pub const CHALLENGE_LEN: usize = 32;
/// A signature: 64 bytes.
pub const SIGNATURE_LEN: usize = 64;

pub type PrivateKey = [u8; PRIVATE_KEY_LEN];
pub type PublicKey = [u8; PUBLIC_KEY_LEN];
pub type Challenge = [u8; CHALLENGE_LEN];
pub type Signature = [u8; SIGNATURE_LEN];

/// The private key the server asks for the public key of to tell whether the
/// stub is in (FR-022). Not all zero: Ed25519 libraries refuse - or panic on -
/// an all-zero seed, and the question must not turn into an error once the
/// real box is in.
pub const PROBE_PRIVATE_KEY: PrivateKey = [0x01; PRIVATE_KEY_LEN];

/// Why a call failed. A signature that does not verify is not an error:
/// `check_signature` answers `Ok(false)` for it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    /// A key the implementation does not accept.
    InvalidArgument,
    /// No random bytes to be had.
    Random,
    /// Anything else that went wrong inside the implementation.
    Internal,
}

impl Error {
    /// The code the C ABI returns for it: -1, -2, -3.
    pub const fn code(self) -> i32 {
        match self {
            Error::InvalidArgument => -1,
            Error::Random => -2,
            Error::Internal => -3,
        }
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Error::InvalidArgument => "RustSecureBox: invalid argument",
            Error::Random => "RustSecureBox: no random bytes",
            Error::Internal => "RustSecureBox: internal error",
        })
    }
}

impl std::error::Error for Error {}

/// A new key pair. The private half is wiped when the pair is dropped; copy it
/// out only into storage that wipes it too.
pub struct KeyPair {
    pub private_key: PrivateKey,
    pub public_key: PublicKey,
}

impl Drop for KeyPair {
    fn drop(&mut self) {
        self.private_key.zeroize();
    }
}

impl fmt::Debug for KeyPair {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("KeyPair").field("private_key", &"[redacted]").finish_non_exhaustive()
    }
}

/// A new key pair: what a device makes once, before its first pairing, and
/// the server at its first start.
pub fn generate_keys() -> Result<KeyPair, Error> {
    stub::generate_keys()
}

/// A new random challenge, and the public key of `own` - the two things a side
/// shows the other at the start of the check.
pub fn get_challenge(own: &PrivateKey) -> Result<(Challenge, PublicKey), Error> {
    stub::get_challenge(own)
}

/// The signature of `own` over the OTHER side's challenge.
pub fn sign_challenge(own: &PrivateKey, theirs: &Challenge) -> Result<Signature, Error> {
    stub::sign_challenge(own, theirs)
}

/// Whether `signature` is `public_key`'s over `challenge`: `Ok(false)` when it
/// is not, `Err` only when the question could not be answered.
pub fn check_signature(public_key: &PublicKey, challenge: &Challenge, signature: &Signature) -> Result<bool, Error> {
    stub::check_signature(public_key, challenge, signature)
}
