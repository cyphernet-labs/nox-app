//! The shared vectors: the answers that are not random - a public key for a
//! private key, a signature for a key and a challenge, a verdict - which the
//! server's WebAssembly copy (`client_backend/internal/securebox`) and the
//! app's module must give byte for byte too. They belong to the implementation
//! the file names in `"implementation"`: the stub's are `stub-v1`, and a real
//! RustSecureBox writes its own in the same format.
//!
//! `RSB_IMPLEMENTATION=<name> cargo test --test vectors -- --ignored write_vectors`
//! writes all three copies - the specification's, this crate's and the
//! server's - under that name (without the variable, under the name the crate's
//! copy already has); every other run checks the crate against them, and that
//! the three copies are the same file.

use std::fs;
use std::path::PathBuf;

use rust_secure_box::{check_signature, get_challenge, sign_challenge, PrivateKey, PROBE_PRIVATE_KEY};
use serde_json::Value;

const SPEC_COPY: &str = "../../specs/050-rust-secure-box/contracts/rsb-vectors.json";
const CRATE_COPY: &str = "tests/data/rsb-vectors.json";
const SERVER_COPY: &str = "../../client_backend/internal/securebox/testdata/rsb-vectors.json";

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

/// The name of the implementation the crate's copy of the vectors belongs to.
fn implementation() -> String {
    let file: Value = serde_json::from_str(&fs::read_to_string(path(CRATE_COPY)).unwrap()).unwrap();
    file["implementation"].as_str().unwrap().to_owned()
}

/// The vectors as this crate computes them, in the file's exact layout, under
/// the name of `implementation`.
fn render(implementation: &str) -> String {
    let keys = private_keys();
    let mut out = format!("{{\n  \"implementation\": \"{implementation}\",\n");
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
#[ignore = "writes the vectors; run on purpose when the implementation changes"]
fn write_vectors() {
    let name = std::env::var("RSB_IMPLEMENTATION").unwrap_or_else(|_| implementation());
    assert!(!name.is_empty() && name.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '.'), "{name:?}");
    let text = render(&name);
    for copy in [SPEC_COPY, CRATE_COPY, SERVER_COPY] {
        fs::write(path(copy), &text).unwrap();
    }
}

#[test]
fn the_three_copies_are_the_same_file() {
    let ours = fs::read_to_string(path(CRATE_COPY)).unwrap();
    for copy in [SPEC_COPY, SERVER_COPY] {
        assert_eq!(fs::read_to_string(path(copy)).unwrap(), ours, "{copy}: regenerate with write_vectors");
    }
}

#[test]
fn the_crate_gives_the_vectors() {
    let file = fs::read_to_string(path(CRATE_COPY)).unwrap();
    assert_eq!(file, render(&implementation()), "the implementation changed: regenerate the vectors on purpose");
}

#[test]
fn every_vector_holds_when_read_back() {
    let file: Value = serde_json::from_str(&fs::read_to_string(path(CRATE_COPY)).unwrap()).unwrap();
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
