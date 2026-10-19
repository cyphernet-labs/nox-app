//! What ANY RustSecureBox must do - the stub now, the real one later. Nothing
//! here knows how a key or a signature is made; the shared vectors
//! (`vectors.rs`) belong to whichever implementation they name.

use std::collections::HashSet;
use std::thread;

use rust_secure_box::{
    check_signature, generate_keys, get_challenge, sign_challenge, CHALLENGE_LEN, PROBE_PRIVATE_KEY,
};

#[test]
fn the_public_key_of_a_challenge_is_the_one_the_pair_was_made_with() {
    let pair = generate_keys().unwrap();
    let (_, public_key) = get_challenge(&pair.private_key).unwrap();
    assert_eq!(public_key, pair.public_key);
}

#[test]
fn a_sides_own_signature_verifies() {
    let device = generate_keys().unwrap();
    let server = generate_keys().unwrap();
    let (challenge, _) = get_challenge(&server.private_key).unwrap();
    let signature = sign_challenge(&device.private_key, &challenge).unwrap();
    assert_eq!(check_signature(&device.public_key, &challenge, &signature), Ok(true));
}

#[test]
fn another_keys_signature_does_not() {
    let device = generate_keys().unwrap();
    let stranger = generate_keys().unwrap();
    let (challenge, _) = get_challenge(&device.private_key).unwrap();
    let signature = sign_challenge(&stranger.private_key, &challenge).unwrap();
    assert_eq!(check_signature(&device.public_key, &challenge, &signature), Ok(false));
}

#[test]
fn a_signature_over_another_challenge_does_not() {
    let device = generate_keys().unwrap();
    let (signed, _) = get_challenge(&device.private_key).unwrap();
    let (other, _) = get_challenge(&device.private_key).unwrap();
    let signature = sign_challenge(&device.private_key, &signed).unwrap();
    assert_eq!(check_signature(&device.public_key, &other, &signature), Ok(false));
}

#[test]
fn a_signature_with_any_byte_changed_does_not() {
    let device = generate_keys().unwrap();
    let (challenge, _) = get_challenge(&device.private_key).unwrap();
    let signature = sign_challenge(&device.private_key, &challenge).unwrap();
    for at in 0..signature.len() {
        let mut changed = signature;
        changed[at] ^= 0x01;
        assert_eq!(check_signature(&device.public_key, &challenge, &changed), Ok(false), "byte {at}");
    }
}

#[test]
fn challenges_do_not_repeat() {
    let pair = generate_keys().unwrap();
    let challenges: HashSet<[u8; CHALLENGE_LEN]> =
        (0..1000).map(|_| get_challenge(&pair.private_key).unwrap().0).collect();
    assert_eq!(challenges.len(), 1000);
}

#[test]
fn key_pairs_do_not_repeat() {
    let keys: HashSet<_> = (0..100).map(|_| generate_keys().unwrap().public_key).collect();
    assert_eq!(keys.len(), 100);
}

#[test]
fn the_probe_key_has_a_public_key() {
    // The server asks this of every implementation; an error there would turn
    // the stub warning into a failure.
    assert!(get_challenge(&PROBE_PRIVATE_KEY).is_ok());
}

#[test]
fn sixteen_threads_get_the_answers_one_thread_gets() {
    let pair = generate_keys().unwrap();
    let (challenge, _) = get_challenge(&pair.private_key).unwrap();
    let expected = sign_challenge(&pair.private_key, &challenge).unwrap();
    let (private_key, public_key) = (pair.private_key, pair.public_key);
    let threads: Vec<_> = (0..16)
        .map(|_| {
            thread::spawn(move || {
                for _ in 0..200 {
                    let signature = sign_challenge(&private_key, &challenge).unwrap();
                    assert_eq!(signature, expected);
                    assert_eq!(check_signature(&public_key, &challenge, &signature), Ok(true));
                    assert_eq!(get_challenge(&private_key).unwrap().1, public_key);
                }
            })
        })
        .collect();
    for t in threads {
        t.join().unwrap();
    }
}
