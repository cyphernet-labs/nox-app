//! The STUB behind the interface - the file the real RustSecureBox replaces.
//!
//! What the real one does (the customer's developer writes it): Ed25519 as in
//! RFC 8032, the same logic and the same keys as the check it replaced -
//!
//! - `generate_keys`: a random 32-byte seed is the private key, its Ed25519
//!   point the 32-byte public key;
//! - `get_challenge`: 32 random bytes, and the public key of the seed;
//! - `sign_challenge`: the 64-byte Ed25519 signature over the challenge;
//! - `check_signature`: Ed25519 verification, strict - a non-canonical S is a
//!   signature that does not verify, never a panic.
//!
//! What the stub does instead: a public key is a hash of the private key, and
//! a "signature" a hash of the public key and the challenge. So it behaves
//! like the real thing in everything but strength - a side's own signature
//! verifies, another key's, another challenge's or a changed byte's does not,
//! and every refusal of the check can be tested with it - but ANYONE WHO KNOWS
//! A PUBLIC KEY CAN FORGE ITS SIGNATURES. With the stub in, the two sides are
//! not really checked. Its public keys match no Ed25519 key, so a device pairs
//! again when the stub goes in and when it goes out.

use sha2::{Digest, Sha256, Sha512};
use zeroize::Zeroize;

use crate::{random, Challenge, Error, KeyPair, PrivateKey, PublicKey, Signature, CHALLENGE_LEN, PRIVATE_KEY_LEN};

/// Separates the stub's two hashes from each other and from anything else.
const PUBLIC_KEY_DOMAIN: &[u8] = b"RustSecureBox stub public key v1";
const SIGNATURE_DOMAIN: &[u8] = b"RustSecureBox stub signature v1";

pub(crate) fn generate_keys() -> Result<KeyPair, Error> {
    let mut private_key = [0u8; PRIVATE_KEY_LEN];
    random::fill(&mut private_key)?;
    let pair = KeyPair { private_key, public_key: public_key(&private_key) };
    private_key.zeroize();
    Ok(pair)
}

pub(crate) fn get_challenge(own: &PrivateKey) -> Result<(Challenge, PublicKey), Error> {
    let mut challenge = [0u8; CHALLENGE_LEN];
    random::fill(&mut challenge)?;
    Ok((challenge, public_key(own)))
}

pub(crate) fn sign_challenge(own: &PrivateKey, theirs: &Challenge) -> Result<Signature, Error> {
    Ok(tag(&public_key(own), theirs))
}

pub(crate) fn check_signature(
    public_key: &PublicKey,
    challenge: &Challenge,
    signature: &Signature,
) -> Result<bool, Error> {
    let expected = tag(public_key, challenge);
    // Every byte is compared whatever the earlier ones were.
    let difference = expected.iter().zip(signature.iter()).fold(0u8, |acc, (a, b)| acc | (a ^ b));
    Ok(difference == 0)
}

fn public_key(private_key: &PrivateKey) -> PublicKey {
    let mut hash = Sha256::new();
    hash.update(PUBLIC_KEY_DOMAIN);
    hash.update(private_key);
    hash.finalize().into()
}

fn tag(public_key: &PublicKey, challenge: &Challenge) -> Signature {
    let mut hash = Sha512::new();
    hash.update(SIGNATURE_DOMAIN);
    hash.update(public_key);
    hash.update(challenge);
    hash.finalize().into()
}
