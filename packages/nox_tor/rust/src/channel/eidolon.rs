//! Eidolon over the TLS channel binding: who is at each end of the channel.
//!
//! The app is the initiator, and its message is the first thing it writes into
//! TLS: 160 bytes, the device's Ed25519 public key, a signature over that key
//! and one over the channel binding. The server checks both signatures and
//! answers with the same three over its own key; the app checks those, and
//! that the key is the one the pairing link named - the only key it accepts.
//! Signatures are RFC 8032 without added randomness, so the shared vectors in
//! `specs/044-secure-channel/contracts/eidolon-vectors.json` hold byte for
//! byte on both sides.
//!
//! A key that is not the expected one is `wrong_server`: some other server
//! answered. Anything else wrong with the answer is `protocol`, and a valid key
//! over the wrong binding is how a man in the middle shows: he relays between
//! two TLS sessions, and the server signed the binding of the other one.

use std::io;
use std::ops::DerefMut;
use std::panic::{catch_unwind, AssertUnwindSafe};

use cypher::{Cert, EcPk, EcSign};
use eidolon::{EidolonState, Error};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use zeroize::{Zeroize, Zeroizing};

use super::code;

/// Either side's message: key (32), signature over the key (64), signature
/// over the channel binding (64).
pub const MESSAGE_LEN: usize = 160;

/// The device's Ed25519 seed as Dart hands it over: wiped when dropped, and
/// boxed so that moving it moves a pointer rather than leaving copies behind.
pub type DeviceSeed = Box<Zeroizing<[u8; 32]>>;

/// The device's key pair for one exchange.
///
/// ec25519 wipes a secret key on drop with `Mem::wipe(self.0)`, which takes the
/// array by value and so wipes a copy: this wipes the key itself. The copies
/// ec25519 makes on the stack while deriving and signing are beyond reach.
struct DeviceKey(ec25519::KeyPair);

impl Drop for DeviceKey {
    fn drop(&mut self) {
        self.0.sk.deref_mut().zeroize();
    }
}

/// The app's side of the exchange, between its message and the server's.
pub struct Initiator {
    key: DeviceKey,
    state: EidolonState<ec25519::Signature>,
}

impl Initiator {
    /// `seed` must not be all zero: ec25519 panics on it (`nox_chan_open`
    /// turns such a seed away).
    pub fn new(seed: &[u8; 32], server_key: &[u8; 32], binding: &[u8; 32]) -> Self {
        let key = DeviceKey(ec25519::KeyPair::from_seed(ec25519::Seed::new(*seed)));
        let (pk, sk) = (key.0.pk, &key.0.sk);
        let cert = Cert { pk, sig: EcSign::sign(sk, pk.to_pk_compressed()) };
        let mut state = EidolonState::initiator(cert, vec![ec25519::PublicKey::new(*server_key)]);
        state.init(binding);
        Initiator { key, state }
    }

    /// The device's message.
    pub fn message(&mut self) -> Result<Vec<u8>, i32> {
        self.state.advance(&[], &self.key.0.sk).map_err(|_| code::INTERNAL)
    }

    /// Checks the server's answer. The server's key when it is the expected one.
    pub fn verify(&mut self, answer: &[u8]) -> Result<[u8; 32], i32> {
        if answer.len() != MESSAGE_LEN || !signatures_canonical(answer) {
            return Err(code::PROTOCOL);
        }
        // signatures_canonical keeps the one panic known in there out of reach;
        // whatever else might panic in a library is a refusal too.
        let checked = catch_unwind(AssertUnwindSafe(|| self.state.advance(answer, &self.key.0.sk)));
        match checked {
            Ok(Ok(_)) => self.state.remote_cert().map(|cert| *cert.pk).ok_or(code::INTERNAL),
            Ok(Err(Error::Unauthorized(_))) => Err(code::WRONG_SERVER),
            Ok(Err(_)) | Err(_) => Err(code::PROTOCOL),
        }
    }
}

/// Writes the device's message, reads exactly the server's, checks it.
///
/// Nothing is written before the message, and nothing after it here: the
/// stream goes on to Dart only once the answer checked.
pub async fn handshake<S>(
    stream: &mut S,
    seed: DeviceSeed,
    server_key: &[u8; 32],
    binding: &[u8; 32],
) -> Result<[u8; 32], i32>
where
    S: AsyncRead + AsyncWrite + Unpin,
{
    let mut initiator = Initiator::new(&seed, server_key, binding);
    // The key pair holds all the seed did; the seed need not wait for the reply.
    drop(seed);
    let message = initiator.message()?;
    stream.write_all(&message).await.map_err(|_| code::NETWORK)?;
    stream.flush().await.map_err(|_| code::NETWORK)?;
    let mut answer = [0u8; MESSAGE_LEN];
    if let Err(e) = stream.read_exact(&mut answer).await {
        return Err(match e.kind() {
            // Gone before a whole answer: a server that speaks something else,
            // or one that refused the device's message - it closes without a
            // word.
            io::ErrorKind::UnexpectedEof => code::PROTOCOL,
            // rustls refused a record or an alert came.
            io::ErrorKind::InvalidData => code::TLS,
            _ => code::NETWORK,
        });
    }
    initiator.verify(&answer)
}

/// ℓ, the order of the Ed25519 group, little-endian.
const ORDER: [u8; 32] = [
    0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, 0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde, 0x14, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0x10,
];

/// Whether both signatures of a message carry a scalar S below ℓ.
///
/// Not a rule Eidolon lacks - ec25519 refuses such a signature too - but
/// cyphergraphy maps that refusal (`Error::NonCanonical`) with `unreachable!`,
/// so the server, or anyone in the middle, could make the check panic rather
/// than fail. Any reply that is not Eidolon at all - an older server's HTTP
/// answer, say - is printable text, far above ℓ.
fn signatures_canonical(message: &[u8]) -> bool {
    [&message[64..96], &message[128..160]].into_iter().all(below_order)
}

fn below_order(scalar: &[u8]) -> bool {
    // Little-endian: from the most significant byte down, the first difference
    // decides. Equal to ℓ is not below it.
    for (byte, order) in scalar.iter().rev().zip(ORDER.iter().rev()) {
        if byte != order {
            return byte < order;
        }
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::duplex;

    /// A field of the shared vectors, decoded.
    fn vector(name: &str) -> Vec<u8> {
        let json = include_str!("../../tests/data/eidolon-vectors.json");
        let field = format!("\"{name}\": \"");
        let start = json.find(&field).unwrap_or_else(|| panic!("{name} in the vectors")) + field.len();
        let end = start + json[start..].find('"').unwrap();
        data_encoding::HEXLOWER.decode(&json.as_bytes()[start..end]).unwrap()
    }

    fn key(name: &str) -> [u8; 32] {
        vector(name).try_into().unwrap()
    }

    fn initiator(binding: &[u8; 32]) -> Initiator {
        Initiator::new(&key("device_seed"), &key("server_public_key"), binding)
    }

    #[test]
    fn the_seed_gives_the_device_key_of_the_vectors() {
        let pair = ec25519::KeyPair::from_seed(ec25519::Seed::new(key("device_seed")));
        assert_eq!(*pair.pk, key("device_public_key"));
    }

    #[test]
    fn the_device_message_is_the_shared_vector_byte_for_byte() {
        let mut app = initiator(&key("channel_binding"));
        assert_eq!(app.message().unwrap(), vector("app_message"));
    }

    #[test]
    fn the_servers_answer_opens_the_channel_with_its_key() {
        let mut app = initiator(&key("channel_binding"));
        app.message().unwrap();
        assert_eq!(app.verify(&vector("server_message")), Ok(key("server_public_key")));
    }

    #[test]
    fn another_servers_answer_is_wrong_server() {
        let mut app = initiator(&key("channel_binding"));
        app.message().unwrap();
        assert_eq!(app.verify(&vector("wrong_server_message")), Err(code::WRONG_SERVER));
    }

    /// What a man in the middle can relay: the right server's answer, signed
    /// over the binding of his other session.
    #[test]
    fn the_servers_answer_over_another_binding_is_protocol() {
        let mut other = key("channel_binding");
        other[0] ^= 0xff;
        let mut app = initiator(&other);
        app.message().unwrap();
        assert_eq!(app.verify(&vector("server_message")), Err(code::PROTOCOL));
    }

    #[test]
    fn an_answer_of_another_length_is_protocol() {
        let answer = vector("server_message");
        for len in [0, 159, 161] {
            let mut app = initiator(&key("channel_binding"));
            app.message().unwrap();
            let mut sized = answer.clone();
            sized.resize(len, 0);
            assert_eq!(app.verify(&sized), Err(code::PROTOCOL), "{len} bytes");
        }
    }

    #[test]
    fn a_key_signature_that_does_not_verify_is_protocol() {
        for byte in [33, 70, 100, 150] {
            let mut answer = vector("server_message");
            answer[byte] ^= 0x01;
            let mut app = initiator(&key("channel_binding"));
            app.message().unwrap();
            assert_eq!(app.verify(&answer), Err(code::PROTOCOL), "byte {byte} flipped");
        }
    }

    fn with_scalar(at: usize, scalar: [u8; 32]) -> Vec<u8> {
        let mut answer = vector("server_message");
        answer[at..at + 32].copy_from_slice(&scalar);
        answer
    }

    #[test]
    fn a_non_canonical_signature_is_protocol_not_a_panic() {
        for at in [64, 128] {
            for scalar in [ORDER, [0xff; 32]] {
                let mut app = initiator(&key("channel_binding"));
                app.message().unwrap();
                assert_eq!(app.verify(&with_scalar(at, scalar)), Err(code::PROTOCOL), "S at {at}");
            }
        }
    }

    /// Why signatures_canonical exists. Should a new eidolon-auth or
    /// cyphergraphy stop panicking here, the guard may go.
    #[test]
    fn without_the_guard_the_library_panics_on_one() {
        let mut app = initiator(&key("channel_binding"));
        app.message().unwrap();
        let answer = with_scalar(64, ORDER);
        let panicked = catch_unwind(AssertUnwindSafe(|| app.state.advance(&answer, &app.key.0.sk))).is_err();
        assert!(panicked);
    }

    #[test]
    fn the_scalar_check_draws_the_line_at_the_order() {
        let mut below = ORDER;
        below[0] -= 1;
        assert!(below_order(&below));
        assert!(!below_order(&ORDER));
        let mut above = ORDER;
        above[0] += 1;
        assert!(!below_order(&above));
        assert!(below_order(&[0; 32]));
        // The vectors' own signatures pass, as every real one does.
        assert!(signatures_canonical(&vector("server_message")));
        assert!(signatures_canonical(&vector("app_message")));
    }

    fn seed() -> DeviceSeed {
        Box::new(Zeroizing::new(key("device_seed")))
    }

    #[tokio::test]
    async fn the_message_goes_first_and_exactly_the_answer_is_read() {
        let (mut app_io, mut server_io) = duplex(4096);
        let server = tokio::spawn(async move {
            let mut message = [0u8; MESSAGE_LEN];
            server_io.read_exact(&mut message).await.unwrap();
            server_io.write_all(&vector("server_message")).await.unwrap();
            server_io.write_all(b"after").await.unwrap();
            (message.to_vec(), server_io)
        });
        let got = handshake(&mut app_io, seed(), &key("server_public_key"), &key("channel_binding")).await;
        assert_eq!(got, Ok(key("server_public_key")));
        let (message, _server_io) = server.await.unwrap();
        assert_eq!(message, vector("app_message"));
        // What follows the answer is the stream's, not the exchange's.
        let mut after = [0u8; 5];
        app_io.read_exact(&mut after).await.unwrap();
        assert_eq!(&after, b"after");
    }

    #[tokio::test]
    async fn a_wrong_server_hears_the_message_and_nothing_else() {
        let (mut app_io, mut server_io) = duplex(4096);
        let server = tokio::spawn(async move {
            let mut message = [0u8; MESSAGE_LEN];
            server_io.read_exact(&mut message).await.unwrap();
            server_io.write_all(&vector("wrong_server_message")).await.unwrap();
            let mut rest = Vec::new();
            server_io.read_to_end(&mut rest).await.unwrap();
            rest
        });
        let got = handshake(&mut app_io, seed(), &key("server_public_key"), &key("channel_binding")).await;
        assert_eq!(got, Err(code::WRONG_SERVER));
        drop(app_io);
        assert_eq!(server.await.unwrap(), Vec::<u8>::new());
    }

    #[tokio::test]
    async fn an_answer_cut_short_is_protocol() {
        let (mut app_io, mut server_io) = duplex(4096);
        tokio::spawn(async move {
            let mut message = [0u8; MESSAGE_LEN];
            server_io.read_exact(&mut message).await.unwrap();
            server_io.write_all(&vector("server_message")[..100]).await.unwrap();
        });
        let got = handshake(&mut app_io, seed(), &key("server_public_key"), &key("channel_binding")).await;
        assert_eq!(got, Err(code::PROTOCOL));
    }
}
