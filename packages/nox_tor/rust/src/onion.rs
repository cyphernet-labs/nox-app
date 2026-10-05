//! The v3 onion address of a public key (rend-spec-v3).
//!
//! In Rust because the Dart side has no SHA3, and a version-2 pairing link
//! carries the service's public key, not its address.

use data_encoding::BASE32_NOPAD;
use sha3::{Digest, Sha3_256};

const VERSION: u8 = 3;

/// `base32(pub ‖ SHA3-256(".onion checksum" ‖ pub ‖ 0x03)[0..2] ‖ 0x03)`,
/// lowercase, with `.onion`.
pub fn onion_from_pubkey(pubkey: &[u8; 32]) -> String {
    let mut hasher = Sha3_256::new();
    hasher.update(b".onion checksum");
    hasher.update(pubkey);
    hasher.update([VERSION]);
    let sum = hasher.finalize();

    let mut raw = Vec::with_capacity(35);
    raw.extend_from_slice(pubkey);
    raw.extend_from_slice(&sum[..2]);
    raw.push(VERSION);
    format!("{}.onion", BASE32_NOPAD.encode(&raw).to_ascii_lowercase())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The vector the server pins in feature 039: RFC 8032 test 1's public
    /// key, address computed independently.
    #[test]
    fn rfc8032_vector() {
        let pubkey: [u8; 32] = [
            0xd7, 0x5a, 0x98, 0x01, 0x82, 0xb1, 0x0a, 0xb7, 0xd5, 0x4b, 0xfe, 0xd3, 0xc9, 0x64, 0x07, 0x3a, 0x0e, 0xe1,
            0x72, 0xf3, 0xda, 0xa6, 0x23, 0x25, 0xaf, 0x02, 0x1a, 0x68, 0xf7, 0x07, 0x51, 0x1a,
        ];
        assert_eq!(onion_from_pubkey(&pubkey), "25njqamcweflpvkl73j4szahhihoc4xt3ktcgjnpaingr5yhkenl5sid.onion");
    }
}
