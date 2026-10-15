//! The stub's shared vectors: the answers that are not random - a public key
//! for a private key, a signature for a key and a challenge, a verdict - which
//! the server's WebAssembly copy must give byte for byte too
//! (`client_backend/internal/securebox`). They belong to the STUB: a real
//! RustSecureBox brings vectors of its own in the same format.
//!
//! `cargo test --test vectors -- --ignored write_vectors` writes them; every
//! other run checks the crate against them, and that the two copies - the
//! specification's and this crate's - are the same file.

use std::fs;
use std::path::PathBuf;

use rust_secure_box::{check_signature, get_challenge, sign_challenge, PrivateKey, PROBE_PRIVATE_KEY};
use serde_json::Value;

const SPEC_COPY: &str = "../../specs/050-rust-secure-box/contracts/rsb-vectors.json";
const CRATE_COPY: &str = "tests/data/rsb-vectors.json";

fn path(relative: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(relative)
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn unhex<const N: usize>(text: &str) -> [u8; N] {
    assert_eq!(text.len(), 2 * N, "{text}");
    let mut out = [0u8; N];
    for (i, byte) in out.iter_mut().enumerate() {
        *byte = u8::from_str_radix(&text[2 * i..2 * i + 2], 16).unwrap();
    }
    out
}

/// Fixed private keys: the probe, the edges, and a few that look random.
fn private_keys() -> Vec<PrivateKey> {
    let mut counting = [0u8; 32];
    for (i, b) in counting.iter_mut().enumerate() {
        *b = u8::try_from(i).unwrap();
    }
    let mut keys = vec![PROBE_PRIVATE_KEY, [0x00; 32], [0xff; 32], counting];
    let mut state = 0x9e37_79b9_7f4a_7c15u64;
    for _ in 0..4 {
        let mut key = [0u8; 32];
        for b in key.iter_mut() {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            *b = state.to_le_bytes()[0];
        }
        keys.push(key);
    }
    keys
}

fn challenges() -> Vec<[u8; 32]> {
    let mut descending = [0u8; 32];
    for (i, b) in descending.iter_mut().enumerate() {
        *b = 0xff - u8::try_from(i).unwrap();
    }
    vec![[0x00; 32], [0xaa; 32], descending]
}

fn public_key(private_key: &PrivateKey) -> [u8; 32] {
    get_challenge(private_key).unwrap().1
}

/// The vectors as this crate computes them, in the file's exact layout.
fn render() -> String {
    let keys = private_keys();
    let mut out = String::from("{\n  \"implementation\": \"stub-v1\",\n");
    out += &format!(
        "  \"probe\": {{\"private_key\": \"{}\", \"public_key\": \"{}\"}},\n",
        hex(&PROBE_PRIVATE_KEY),
        hex(&public_key(&PROBE_PRIVATE_KEY))
    );
    let rows: Vec<String> = keys
        .iter()
        .map(|k| format!("    {{\"private_key\": \"{}\", \"public_key\": \"{}\"}}", hex(k), hex(&public_key(k))))
        .collect();
    out += &format!("  \"keys\": [\n{}\n  ],\n", rows.join(",\n"));
    let mut rows = Vec::new();
    for k in &keys {
        for c in challenges() {
            rows.push(format!(
                "    {{\"private_key\": \"{}\", \"challenge\": \"{}\", \"signature\": \"{}\"}}",
                hex(k),
                hex(&c),
                hex(&sign_challenge(k, &c).unwrap())
            ));
        }
    }
    out += &format!("  \"signatures\": [\n{}\n  ],\n", rows.join(",\n"));
    let mut rows = Vec::new();
    let check = |pk: &[u8; 32], c: &[u8; 32], sig: &[u8; 64]| {
        let valid = check_signature(pk, c, sig).unwrap();
        format!(
            "    {{\"public_key\": \"{}\", \"challenge\": \"{}\", \"signature\": \"{}\", \"valid\": {valid}}}",
            hex(pk),
            hex(c),
            hex(sig)
        )
    };
    for (i, k) in keys.iter().enumerate() {
        let c = challenges()[i % 3];
        let sig = sign_challenge(k, &c).unwrap();
        let pk = public_key(k);
        rows.push(check(&pk, &c, &sig));
        let other_pk = public_key(&keys[(i + 1) % keys.len()]);
        rows.push(check(&other_pk, &c, &sig));
        let other_c = challenges()[(i + 1) % 3];
        rows.push(check(&pk, &other_c, &sig));
        let mut changed = sig;
        changed[i * 7 % 64] ^= 0x80;
        rows.push(check(&pk, &c, &changed));
    }
    out += &format!("  \"checks\": [\n{}\n  ]\n}}\n", rows.join(",\n"));
    out
}

#[test]
#[ignore = "writes the vectors; run on purpose when the stub changes"]
fn write_vectors() {
    let text = render();
    fs::write(path(SPEC_COPY), &text).unwrap();
    fs::write(path(CRATE_COPY), &text).unwrap();
}

#[test]
fn both_copies_are_the_same_file() {
    let spec = fs::read_to_string(path(SPEC_COPY)).unwrap();
    let ours = fs::read_to_string(path(CRATE_COPY)).unwrap();
    assert_eq!(spec, ours);
}

#[test]
fn the_crate_gives_the_vectors() {
    let file = fs::read_to_string(path(CRATE_COPY)).unwrap();
    assert_eq!(file, render(), "the stub changed: regenerate the vectors on purpose");
}

#[test]
fn every_vector_holds_when_read_back() {
    let file: Value = serde_json::from_str(&fs::read_to_string(path(CRATE_COPY)).unwrap()).unwrap();
    assert_eq!(file["implementation"], "stub-v1");
    for row in file["keys"].as_array().unwrap().iter().chain([&file["probe"]]) {
        let sk = unhex::<32>(row["private_key"].as_str().unwrap());
        assert_eq!(public_key(&sk), unhex::<32>(row["public_key"].as_str().unwrap()));
    }
    for row in file["signatures"].as_array().unwrap() {
        let sk = unhex::<32>(row["private_key"].as_str().unwrap());
        let c = unhex::<32>(row["challenge"].as_str().unwrap());
        assert_eq!(sign_challenge(&sk, &c).unwrap(), unhex::<64>(row["signature"].as_str().unwrap()));
    }
    let checks = file["checks"].as_array().unwrap();
    assert!(checks.iter().any(|r| r["valid"] == true) && checks.iter().any(|r| r["valid"] == false));
    for row in checks {
        let pk = unhex::<32>(row["public_key"].as_str().unwrap());
        let c = unhex::<32>(row["challenge"].as_str().unwrap());
        let sig = unhex::<64>(row["signature"].as_str().unwrap());
        assert_eq!(check_signature(&pk, &c, &sig).unwrap(), row["valid"].as_bool().unwrap());
    }
}
