//! POST /auth, then POST /auth2: who is at each end of the channel (contract
//! §1, feature 050).
//!
//! The first two requests of every connection, right after TLS:
//!
//! ```text
//! app → POST /auth  {"pk", "challenge"}               the device's key, a fresh challenge
//! app ← 200         {"pk", "challenge", "signature"}  the server's key, its challenge, its
//!                                                     signature over the device's challenge
//! app → POST /auth2 {"signature"}                     the device's signature over the server's
//! app ← 200                                           the stream goes on to Dart
//! ```
//!
//! Keys, challenges and signatures are RustSecureBox's (`rust_secure_box`), the
//! one library the app and the server share. The answer to /auth is checked
//! before anything else goes out: the server's signature over the device's own
//! challenge first, then its key against the one the pairing link named. A
//! signature that does not hold is `protocol` - whatever answered is not a
//! server of ours; a valid answer from another key is `wrong_server` - another
//! NOX server is at the address. Only then is /auth2 sent, and only once it is
//! answered does a byte of Dart's reach the stream.
//!
//! Nothing is read past an answer: headers are read a byte at a time (rustls
//! buffers the records anyway) and a body exactly to its Content-Length, so
//! the stream goes on to Dart with nothing taken out of it.

use std::io;
use std::panic::{catch_unwind, AssertUnwindSafe};

use data_encoding::BASE64URL_NOPAD;
use rust_secure_box as rsb;
use serde_json::Value;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use zeroize::Zeroizing;

use super::code;

/// The device's private key as Dart hands it over: wiped when dropped, and
/// boxed so that moving it moves a pointer rather than leaving copies behind.
pub type DeviceKey = Box<Zeroizing<rsb::PrivateKey>>;

/// The longest status line and headers an answer may have.
const MAX_HEAD: usize = 8 * 1024;
/// The longest body an answer may have: the server's is 211 bytes.
const MAX_BODY: usize = 1024;
/// The most headers an answer may have.
const MAX_HEADERS: usize = 32;

/// Runs the check on `stream` as the device with `device`, for a server that
/// must prove `server_key`; `host` is what the Host header says. The server's
/// key when it passed.
pub async fn handshake<S>(stream: &mut S, device: DeviceKey, server_key: &[u8; 32], host: &str) -> Result<[u8; 32], i32>
where
    S: AsyncRead + AsyncWrite + Unpin,
{
    let (ours, device_public) = guarded(|| rsb::get_challenge(&device))?;
    let body = format!(
        r#"{{"pk":"{}","challenge":"{}"}}"#,
        BASE64URL_NOPAD.encode(&device_public),
        BASE64URL_NOPAD.encode(&ours)
    );
    post(stream, host, "/auth", body.as_bytes()).await?;
    let answer = read_answer(stream).await?;
    let (server_public, theirs, signature) = parse_auth_answer(&answer)?;

    if !verified(&server_public, &ours, &signature)? {
        return Err(code::PROTOCOL);
    }
    if server_public != *server_key {
        return Err(code::WRONG_SERVER);
    }

    let mine = guarded(|| rsb::sign_challenge(&device, &theirs))?;
    // The key did all it had to; it need not wait for the last answer.
    drop(device);
    let body = format!(r#"{{"signature":"{}"}}"#, BASE64URL_NOPAD.encode(&mine));
    post(stream, host, "/auth2", body.as_bytes()).await?;
    if !read_answer(stream).await?.is_empty() {
        return Err(code::PROTOCOL);
    }
    Ok(server_public)
}

/// A call into RustSecureBox. An error - or a panic in an implementation that
/// should not have one - is `internal`: the check could not be made, which is
/// neither another server nor a broken network.
fn guarded<T>(call: impl FnOnce() -> Result<T, rsb::Error>) -> Result<T, i32> {
    match catch_unwind(AssertUnwindSafe(call)) {
        Ok(Ok(value)) => Ok(value),
        Ok(Err(_)) | Err(_) => Err(code::INTERNAL),
    }
}

/// RustSecureBox's verdict on the server's signature over our challenge. A
/// public key the library refuses outright came from the other side: to the
/// check it is a key whose signature does not hold, not a failure of ours.
fn verified(public: &rsb::PublicKey, challenge: &rsb::Challenge, signature: &rsb::Signature) -> Result<bool, i32> {
    match catch_unwind(AssertUnwindSafe(|| rsb::check_signature(public, challenge, signature))) {
        Ok(Ok(valid)) => Ok(valid),
        Ok(Err(rsb::Error::InvalidArgument)) => Ok(false),
        Ok(Err(_)) | Err(_) => Err(code::INTERNAL),
    }
}

/// Writes one request and flushes it.
async fn post<S>(stream: &mut S, host: &str, path: &str, body: &[u8]) -> Result<(), i32>
where
    S: AsyncWrite + Unpin,
{
    let mut request = format!(
        "POST {path} HTTP/1.1\r\nHost: {host}\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n",
        body.len()
    )
    .into_bytes();
    request.extend_from_slice(body);
    stream.write_all(&request).await.map_err(|e| io_code(&e))?;
    stream.flush().await.map_err(|e| io_code(&e))
}

/// Reads one answer and returns its body - only for a 200 with a
/// Content-Length; anything else is `protocol`.
async fn read_answer<S>(stream: &mut S) -> Result<Vec<u8>, i32>
where
    S: AsyncRead + Unpin,
{
    let mut head = Vec::with_capacity(256);
    let mut byte = [0u8; 1];
    while !head.ends_with(b"\r\n\r\n") {
        if head.len() >= MAX_HEAD {
            return Err(code::PROTOCOL);
        }
        match stream.read(&mut byte).await {
            // Gone before a whole answer: a server that speaks something
            // else, or one that refused and closed.
            Ok(0) => return Err(code::PROTOCOL),
            Ok(_) => head.push(byte[0]),
            Err(e) => return Err(io_code(&e)),
        }
    }
    let mut headers = [httparse::EMPTY_HEADER; MAX_HEADERS];
    let mut answer = httparse::Response::new(&mut headers);
    if !matches!(answer.parse(&head), Ok(httparse::Status::Complete(_))) {
        return Err(code::PROTOCOL);
    }
    if answer.code != Some(200) {
        return Err(code::PROTOCOL);
    }
    let mut length = None;
    for header in answer.headers.iter() {
        if header.name.eq_ignore_ascii_case("transfer-encoding") {
            return Err(code::PROTOCOL);
        }
        if header.name.eq_ignore_ascii_case("content-length") {
            let value = std::str::from_utf8(header.value).ok().and_then(|v| v.trim().parse::<usize>().ok());
            match (length, value) {
                (_, None) => return Err(code::PROTOCOL),
                (Some(seen), Some(v)) if seen != v => return Err(code::PROTOCOL),
                (_, Some(v)) => length = Some(v),
            }
        }
    }
    let length = length.ok_or(code::PROTOCOL)?;
    if length > MAX_BODY {
        return Err(code::PROTOCOL);
    }
    let mut body = vec![0u8; length];
    stream.read_exact(&mut body).await.map_err(|e| io_code(&e))?;
    Ok(body)
}

/// The server's key, its challenge and its signature from the answer to /auth.
fn parse_auth_answer(body: &[u8]) -> Result<(rsb::PublicKey, rsb::Challenge, rsb::Signature), i32> {
    let value: Value = serde_json::from_slice(body).map_err(|_| code::PROTOCOL)?;
    let field = |name: &str| value.get(name).and_then(Value::as_str).ok_or(code::PROTOCOL);
    Ok((decode(field("pk")?)?, decode(field("challenge")?)?, decode(field("signature")?)?))
}

/// A base64url value of exactly N bytes.
fn decode<const N: usize>(text: &str) -> Result<[u8; N], i32> {
    let raw = BASE64URL_NOPAD.decode(text.as_bytes()).map_err(|_| code::PROTOCOL)?;
    raw.try_into().map_err(|_| code::PROTOCOL)
}

fn io_code(e: &io::Error) -> i32 {
    match e.kind() {
        io::ErrorKind::UnexpectedEof => code::PROTOCOL,
        // rustls refused a record or an alert came.
        io::ErrorKind::InvalidData => code::TLS,
        _ => code::NETWORK,
    }
}

/// The Host header for an address: `host:port`, an IPv6 literal in brackets.
pub fn host_header(host: &str, port: u16) -> String {
    if host.contains(':') && !host.starts_with('[') {
        format!("[{host}]:{port}")
    } else {
        format!("{host}:{port}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::{duplex, DuplexStream};

    fn pair() -> rsb::KeyPair {
        rsb::generate_keys().unwrap()
    }

    fn device_key(pair: &rsb::KeyPair) -> DeviceKey {
        Box::new(Zeroizing::new(pair.private_key))
    }

    /// One request off the stream: the path and the body.
    async fn read_request(io: &mut DuplexStream) -> (String, Vec<u8>) {
        let mut head = Vec::new();
        let mut byte = [0u8; 1];
        while !head.ends_with(b"\r\n\r\n") {
            assert_eq!(io.read(&mut byte).await.unwrap(), 1, "the device stopped mid-request");
            head.push(byte[0]);
        }
        let mut headers = [httparse::EMPTY_HEADER; 16];
        let mut req = httparse::Request::new(&mut headers);
        req.parse(&head).unwrap();
        let length: usize = req
            .headers
            .iter()
            .find(|h| h.name.eq_ignore_ascii_case("content-length"))
            .map(|h| std::str::from_utf8(h.value).unwrap().parse().unwrap())
            .unwrap();
        let path = req.path.unwrap().to_owned();
        let mut body = vec![0u8; length];
        io.read_exact(&mut body).await.unwrap();
        (path, body)
    }

    fn answer(status: u16, body: &str) -> Vec<u8> {
        format!("HTTP/1.1 {status} X\r\nContent-Length: {}\r\n\r\n{body}", body.len()).into_bytes()
    }

    /// What a server of ours answers to /auth: its key, a challenge and its
    /// signature over the device's challenge - here by `signer`, and over
    /// `over` when given instead of the device's own.
    fn auth_answer(
        server: &rsb::KeyPair,
        signer: &rsb::KeyPair,
        request: &[u8],
        over: Option<rsb::Challenge>,
    ) -> (Vec<u8>, rsb::Challenge) {
        let request: Value = serde_json::from_slice(request).unwrap();
        let theirs: rsb::Challenge = decode(request["challenge"].as_str().unwrap()).unwrap();
        let (ours, _) = rsb::get_challenge(&server.private_key).unwrap();
        let signature = rsb::sign_challenge(&signer.private_key, &over.unwrap_or(theirs)).unwrap();
        let body = format!(
            r#"{{"pk":"{}","challenge":"{}","signature":"{}"}}"#,
            BASE64URL_NOPAD.encode(&server.public_key),
            BASE64URL_NOPAD.encode(&ours),
            BASE64URL_NOPAD.encode(&signature)
        );
        (answer(200, &body), ours)
    }

    #[tokio::test]
    async fn the_device_shows_its_key_and_signs_the_servers_challenge() {
        let (server, device) = (pair(), pair());
        let (server_public, device_public) = (server.public_key, device.public_key);
        let (mut app, mut io) = duplex(64 * 1024);
        let serving = tokio::spawn(async move {
            let (path, body) = read_request(&mut io).await;
            assert_eq!(path, "/auth");
            let request: Value = serde_json::from_slice(&body).unwrap();
            let pk: rsb::PublicKey = decode(request["pk"].as_str().unwrap()).unwrap();
            assert_eq!(pk, device_public, "the device shows its own key");
            let (bytes, ours) = auth_answer(&server, &server, &body, None);
            io.write_all(&bytes).await.unwrap();
            let (path, body) = read_request(&mut io).await;
            assert_eq!(path, "/auth2");
            let request: Value = serde_json::from_slice(&body).unwrap();
            let signature: rsb::Signature = decode(request["signature"].as_str().unwrap()).unwrap();
            assert!(rsb::check_signature(&pk, &ours, &signature).unwrap(), "the device signs the server's challenge");
            io.write_all(&answer(200, "")).await.unwrap();
            io
        });
        assert_eq!(handshake(&mut app, device_key(&device), &server_public, "h:1").await, Ok(server_public));
        serving.await.unwrap();
    }

    /// The whole exchange against a server whose key the device expects.
    async fn exchange(server: rsb::KeyPair, expect: [u8; 32]) -> (Result<[u8; 32], i32>, Vec<u8>) {
        let device = pair();
        let (mut app, mut io) = duplex(64 * 1024);
        let serving = tokio::spawn(async move {
            let (_, body) = read_request(&mut io).await;
            let (bytes, _) = auth_answer(&server, &server, &body, None);
            io.write_all(&bytes).await.unwrap();
            // Whatever the device sends next, if anything: /auth2 is read
            // whole and answered.
            let mut rest = Vec::new();
            let mut byte = [0u8; 1];
            while let Ok(1) = io.read(&mut byte).await {
                rest.push(byte[0]);
                if rest.ends_with(b"\r\n\r\n") {
                    break;
                }
            }
            if rest.starts_with(b"POST /auth2") {
                let mut headers = [httparse::EMPTY_HEADER; 16];
                let mut request = httparse::Request::new(&mut headers);
                request.parse(&rest).unwrap();
                let length: usize = request
                    .headers
                    .iter()
                    .find(|h| h.name.eq_ignore_ascii_case("content-length"))
                    .map(|h| std::str::from_utf8(h.value).unwrap().parse().unwrap())
                    .unwrap();
                let mut body = vec![0u8; length];
                io.read_exact(&mut body).await.unwrap();
                io.write_all(&answer(200, "")).await.unwrap();
                io.write_all(b"after").await.unwrap();
            }
            (rest, io)
        });
        let got = handshake(&mut app, device_key(&device), &expect, "h:1").await;
        if got.is_ok() {
            let mut after = [0u8; 5];
            app.read_exact(&mut after).await.unwrap();
            assert_eq!(&after, b"after", "the bytes after /auth2's answer are the stream's");
        }
        drop(app);
        let (rest, _io) = serving.await.unwrap();
        (got, rest)
    }

    #[tokio::test]
    async fn the_servers_proved_key_opens_the_channel() {
        let server = pair();
        let expect = server.public_key;
        let (got, rest) = exchange(server, expect).await;
        assert_eq!(got, Ok(expect));
        assert!(rest.starts_with(b"POST /auth2 HTTP/1.1\r\n"));
    }

    #[tokio::test]
    async fn another_servers_key_is_wrong_server_and_auth2_never_goes() {
        let (server, other) = (pair(), pair());
        let (got, rest) = exchange(server, other.public_key).await;
        assert_eq!(got, Err(code::WRONG_SERVER));
        assert!(rest.is_empty(), "the device sent {:?} after a wrong server", String::from_utf8_lossy(&rest));
    }

    /// An answer to /auth, and what the device makes of it.
    async fn after_auth(
        answer_bytes: impl FnOnce(&rsb::KeyPair, &[u8]) -> Vec<u8> + Send + 'static,
    ) -> Result<[u8; 32], i32> {
        let (server, device) = (pair(), pair());
        let expect = server.public_key;
        let (mut app, mut io) = duplex(64 * 1024);
        let serving = tokio::spawn(async move {
            let (_, body) = read_request(&mut io).await;
            io.write_all(&answer_bytes(&server, &body)).await.unwrap();
            // And then nothing: a server that answered something else has
            // nothing more to say - which leaves an answer cut short cut short.
            io.shutdown().await.unwrap();
            let mut rest = Vec::new();
            let _ = io.read_to_end(&mut rest).await;
            rest
        });
        let got = handshake(&mut app, device_key(&device), &expect, "h:1").await;
        // The device's end goes, so the server's read ends: whatever the
        // device sent after the bad answer is in hand, and asserted here.
        drop(app);
        let rest = serving.await.unwrap();
        assert!(rest.is_empty(), "the device went on after a bad answer: {:?}", String::from_utf8_lossy(&rest));
        got
    }

    #[tokio::test]
    async fn a_signature_over_another_challenge_is_protocol() {
        let got = after_auth(|server, body| auth_answer(server, server, body, Some([7u8; 32])).0).await;
        assert_eq!(got, Err(code::PROTOCOL));
    }

    #[tokio::test]
    async fn another_keys_signature_under_the_expected_key_is_protocol() {
        let signer = pair();
        let got = after_auth(move |server, body| auth_answer(server, &signer, body, None).0).await;
        assert_eq!(got, Err(code::PROTOCOL));
    }

    #[tokio::test]
    async fn the_signature_is_checked_before_the_key() {
        // Another key AND a signature that does not hold: the key never gets
        // looked at, so this is a broken answer, not another server.
        let other = pair();
        let got = after_auth(move |_, body| auth_answer(&other, &other, body, Some([7u8; 32])).0).await;
        assert_eq!(got, Err(code::PROTOCOL));
    }

    #[tokio::test]
    async fn every_other_answer_is_protocol() {
        let answers: Vec<(&str, Vec<u8>)> = vec![
            ("a refusal", answer(401, "")),
            ("a 404 of some web server", answer(404, "<html>not found</html>")),
            ("no Content-Length", b"HTTP/1.1 200 OK\r\n\r\n{}".to_vec()),
            ("chunked", b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\n{}\r\n0\r\n\r\n".to_vec()),
            ("a body over 1 KiB", answer(200, &"x".repeat(MAX_BODY + 1))),
            ("not JSON", answer(200, "hello")),
            ("a key of 31 bytes", answer(200, r#"{"pk":"AAAA","challenge":"AAAA","signature":"AAAA"}"#)),
            ("headers that never end", [b"HTTP/1.1 200 OK\r\n".to_vec(), vec![b'x'; MAX_HEAD]].concat()),
            ("160 bytes of Eidolon", vec![0x42; 160]),
        ];
        for (what, bytes) in answers {
            let got = after_auth(move |_, _| bytes).await;
            assert_eq!(got, Err(code::PROTOCOL), "{what}");
        }
    }

    #[tokio::test]
    async fn a_server_that_closes_after_auth_is_protocol() {
        let device = pair();
        let (mut app, mut io) = duplex(64 * 1024);
        tokio::spawn(async move {
            let _ = read_request(&mut io).await;
        });
        assert_eq!(handshake(&mut app, device_key(&device), &[0u8; 32], "h:1").await, Err(code::PROTOCOL));
    }

    #[test]
    fn the_host_header_brackets_an_ipv6_literal() {
        assert_eq!(host_header("192.168.1.61", 8443), "192.168.1.61:8443");
        assert_eq!(host_header("fd00::1", 8443), "[fd00::1]:8443");
        assert_eq!(host_header("nox.example", 443), "nox.example:443");
    }
}
