//! The channel end to end, through the C ABI the app calls: real TCP to a TLS
//! 1.3 server standing in for noxd - a throwaway certificate, the RFC 9266
//! binding, eidolon-auth as the responder with the shared vectors' server key -
//! and to the servers that must not get a channel: another key, a man in the
//! middle, an older server that answers HTTP, one that answers nothing.
//!
//! Events are taken the way Dart's port takes them - decoded from the posted
//! message, queued for the test to read on its own thread - and each channel
//! posts to a port of its own, which a test can close the way an isolate's
//! ports close when it dies.

use std::collections::{HashMap, HashSet, VecDeque};
use std::ffi::CString;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{Arc, Condvar, Mutex, MutexGuard, OnceLock};
use std::time::{Duration, Instant};

use cypher::{Cert, EcPk, EcSign};
use eidolon::EidolonState;
use nox_tor::channel::dart::{decode, DartCObject};
use nox_tor::channel::{code, event, CHUNK, WINDOW};
use nox_tor::{
    nox_chan_ack, nox_chan_close, nox_chan_flush, nox_chan_open, nox_chan_reap, nox_chan_shutdown_write, nox_chan_write,
};
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::pki_types::{CertificateDer, PrivateKeyDer, ServerName, UnixTime};
use rustls::{ClientConfig, DigitallySignedStruct, ServerConfig, SignatureScheme, SupportedProtocolVersion};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::runtime::Runtime;
use tokio_rustls::server::TlsStream;
use tokio_rustls::{TlsAcceptor, TlsConnector};

const MESSAGE_LEN: usize = 160;
const BINDING_LABEL: &[u8] = b"EXPORTER-Channel-Binding";
/// Long enough for anything that should happen on a loopback connection.
const PATIENCE: Duration = Duration::from_secs(10);

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|p| p.into_inner())
}

// --- The shared vectors ---------------------------------------------------

fn vector(name: &str) -> Vec<u8> {
    let json = include_str!("data/eidolon-vectors.json");
    let field = format!("\"{name}\": \"");
    let start = json.find(&field).unwrap_or_else(|| panic!("{name} in the vectors")) + field.len();
    let end = start + json[start..].find('"').unwrap();
    data_encoding::HEXLOWER.decode(&json.as_bytes()[start..end]).unwrap()
}

fn key(name: &str) -> [u8; 32] {
    vector(name).try_into().unwrap()
}

// --- Events, as Dart receives them ----------------------------------------

#[derive(Clone, Debug, PartialEq, Eq)]
struct Event {
    kind: i32,
    data: Vec<u8>,
    code: i32,
}

#[derive(Default)]
struct Inbox {
    events: Mutex<HashMap<i64, VecDeque<Event>>>,
    arrived: Condvar,
    /// Ports of isolates that are gone: posts to them are refused.
    closed_ports: Mutex<HashSet<i64>>,
}

fn inbox() -> &'static Inbox {
    static INBOX: OnceLock<Inbox> = OnceLock::new();
    INBOX.get_or_init(Inbox::default)
}

/// `Dart_PostCObject`, as far as the module can tell.
unsafe extern "C" fn on_post(port: i64, message: *mut DartCObject) -> i8 {
    let inbox = inbox();
    if lock(&inbox.closed_ports).contains(&port) {
        return 0;
    }
    let (handle, kind, code, data) = decode(message).expect("an event message");
    if kind != event::PROBE {
        lock(&inbox.events).entry(handle).or_default().push_back(Event { kind, data, code });
        inbox.arrived.notify_all();
    }
    1
}

/// A port of its own for every channel, as if each came from an isolate of
/// its own.
fn new_port() -> i64 {
    static NEXT: AtomicI64 = AtomicI64::new(1000);
    NEXT.fetch_add(1, Ordering::Relaxed)
}

/// One channel as the app holds it: its handle, and the port its events go to.
struct Chan(i64, i64);

impl Chan {
    fn open(kind: i32, host: &str, port: u16, server_key: [u8; 32], budget_ms: u32) -> Chan {
        let host = CString::new(host).unwrap();
        let seed = key("device_seed");
        let events = new_port();
        let handle = unsafe {
            nox_chan_open(
                kind,
                host.as_ptr(),
                port,
                seed.as_ptr(),
                server_key.as_ptr(),
                budget_ms,
                Some(on_post),
                events,
            )
        };
        assert!(handle > 0, "open returned {handle}");
        Chan(handle, events)
    }

    /// The isolate that opened the channel dies: its port refuses everything.
    fn lose_isolate(&self) {
        lock(&inbox().closed_ports).insert(self.1);
    }

    fn direct(addr: SocketAddr, budget_ms: u32) -> Chan {
        Chan::open(0, &addr.ip().to_string(), addr.port(), key("server_public_key"), budget_ms)
    }

    /// The next event, within `within`.
    fn next_within(&self, within: Duration) -> Option<Event> {
        let inbox = inbox();
        let deadline = Instant::now() + within;
        let mut events = lock(&inbox.events);
        loop {
            if let Some(event) = events.get_mut(&self.0).and_then(VecDeque::pop_front) {
                return Some(event);
            }
            let now = Instant::now();
            if now >= deadline {
                return None;
            }
            events = inbox.arrived.wait_timeout(events, deadline - now).unwrap_or_else(|p| p.into_inner()).0;
        }
    }

    fn next(&self) -> Event {
        self.next_within(PATIENCE).unwrap_or_else(|| panic!("channel {}: no event", self.0))
    }

    fn expect(&self, kind: i32) -> Event {
        let got = self.next();
        assert_eq!(got.kind, kind, "channel {}: {got:?}", self.0);
        got
    }

    /// The channel's end, with nothing before it.
    fn closed(&self) -> i32 {
        let code = self.expect(event::CLOSED).code;
        self.assert_quiet(Duration::from_millis(100));
        code
    }

    fn assert_quiet(&self, period: Duration) {
        if let Some(late) = self.next_within(period) {
            panic!("channel {}: {late:?} after all", self.0);
        }
    }

    fn write(&self, bytes: &[u8]) -> i64 {
        unsafe { nox_chan_write(self.0, bytes.as_ptr(), bytes.len()) }
    }

    /// DATA until `len` bytes came, acking each as it comes when `ack`.
    fn take(&self, len: usize, ack: bool) -> Vec<u8> {
        let mut got = Vec::new();
        while got.len() < len {
            let data = self.expect(event::DATA).data;
            assert!(!data.is_empty() && data.len() <= CHUNK, "a DATA of {} bytes", data.len());
            if ack {
                assert_eq!(nox_chan_ack(self.0, data.len()), code::NONE);
            }
            got.extend(data);
        }
        assert_eq!(got.len(), len, "more than asked for");
        got
    }

    /// Every remaining event up to and including CLOSED.
    fn rest(&self) -> Vec<Event> {
        let mut events = Vec::new();
        loop {
            let got = self.next();
            let last = got.kind == event::CLOSED;
            events.push(got);
            if last {
                return events;
            }
        }
    }
}

// --- Servers --------------------------------------------------------------

fn runtime() -> Runtime {
    tokio::runtime::Builder::new_multi_thread().worker_threads(2).enable_all().build().unwrap()
}

fn provider() -> Arc<rustls::crypto::CryptoProvider> {
    Arc::new(rustls::crypto::ring::default_provider())
}

/// A throwaway P-256 certificate, the way noxd makes one at every start.
fn certificate() -> (CertificateDer<'static>, PrivateKeyDer<'static>) {
    let key = rcgen::KeyPair::generate().unwrap();
    let cert = rcgen::CertificateParams::new(Vec::<String>::new()).unwrap().self_signed(&key).unwrap();
    (cert.der().clone(), PrivateKeyDer::from(key))
}

fn server_config(versions: &[&'static SupportedProtocolVersion], tickets: usize) -> Arc<ServerConfig> {
    let (cert, key) = certificate();
    let mut config = ServerConfig::builder_with_provider(provider())
        .with_protocol_versions(versions)
        .unwrap()
        .with_no_client_auth()
        .with_single_cert(vec![cert], key)
        .unwrap();
    config.alpn_protocols = vec![b"http/1.1".to_vec()];
    config.send_tls13_tickets = tickets;
    Arc::new(config)
}

/// noxd's TLS: 1.3 only, no session tickets.
fn noxd_tls() -> Arc<ServerConfig> {
    server_config(&[&rustls::version::TLS13], 0)
}

async fn listen() -> (TcpListener, SocketAddr) {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    (listener, addr)
}

async fn accept(listener: &TcpListener, config: Arc<ServerConfig>) -> TlsStream<TcpStream> {
    let (tcp, _) = listener.accept().await.unwrap();
    TlsAcceptor::from(config).accept(tcp).await.unwrap()
}

fn binding(tls: &TlsStream<TcpStream>) -> [u8; 32] {
    tls.get_ref().1.export_keying_material([0u8; 32], BINDING_LABEL, Some(b"")).unwrap()
}

fn key_pair(seed: [u8; 32]) -> ec25519::KeyPair {
    ec25519::KeyPair::from_seed(ec25519::Seed::new(seed))
}

fn cert(pair: &ec25519::KeyPair) -> Cert<ec25519::Signature> {
    Cert { pk: pair.pk, sig: EcSign::sign(&pair.sk, pair.pk.to_pk_compressed()) }
}

/// noxd's side of Eidolon: any device key whose two signatures hold - over its
/// key and over this connection's binding - and its own message in answer.
fn respond(seed: [u8; 32], message: &[u8], binding: &[u8; 32]) -> Result<Vec<u8>, String> {
    let pair = key_pair(seed);
    let mut state = EidolonState::responder(cert(&pair), vec![]);
    state.init(binding);
    let answer = state.advance(message, &pair.sk).map_err(|e| format!("{e:?}"))?;
    assert_eq!(*state.remote_cert().unwrap().pk, key("device_public_key"));
    Ok(answer)
}

/// The message of the server with `seed` over `binding`, whatever the device
/// sent: what a server that answers anyway sends, and what a relay passes on.
fn message_of(seed: [u8; 32], binding: &[u8; 32]) -> Vec<u8> {
    let pair = key_pair(seed);
    let mut state = EidolonState::initiator(cert(&pair), vec![]);
    state.init(binding);
    state.advance(&[], &pair.sk).unwrap()
}

/// TLS, then the server's side of Eidolon with the vectors' server key.
async fn verified(listener: &TcpListener, config: Arc<ServerConfig>) -> TlsStream<TcpStream> {
    let mut tls = accept(listener, config).await;
    let binding = binding(&tls);
    let mut message = [0u8; MESSAGE_LEN];
    tls.read_exact(&mut message).await.unwrap();
    let answer = respond(key("server_seed"), &message, &binding).expect("the device's message checks out");
    tls.write_all(&answer).await.unwrap();
    tls
}

/// Reads until the peer is gone, by close_notify or not; what came.
async fn read_to_gone<R: AsyncRead + Unpin>(stream: &mut R) -> Vec<u8> {
    let mut got = Vec::new();
    let mut buf = [0u8; 4096];
    while let Ok(n) = stream.read(&mut buf).await {
        if n == 0 {
            break;
        }
        got.extend_from_slice(&buf[..n]);
    }
    got
}

fn pattern(from: usize, len: usize) -> Vec<u8> {
    (from..from + len).map(|i| (i % 251) as u8).collect()
}

/// Trusts any server, for the relay's own connection to the real server.
#[derive(Debug)]
struct TrustAnything;

impl ServerCertVerifier for TrustAnything {
    fn verify_server_cert(
        &self,
        _: &CertificateDer<'_>,
        _: &[CertificateDer<'_>],
        _: &ServerName<'_>,
        _: &[u8],
        _: UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        Ok(ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        _: &[u8],
        _: &CertificateDer<'_>,
        _: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        Ok(HandshakeSignatureValid::assertion())
    }

    fn verify_tls13_signature(
        &self,
        _: &[u8],
        _: &CertificateDer<'_>,
        _: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        Ok(HandshakeSignatureValid::assertion())
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        provider().signature_verification_algorithms.supported_schemes()
    }
}

// --- A channel that opens -------------------------------------------------

#[test]
fn a_verified_channel_carries_bytes_both_ways_and_ends_cleanly() {
    let rt = runtime();
    let (listener, addr) = rt.block_on(listen());
    let server = rt.spawn(async move {
        // rustls's default session tickets: the client stores none, and copes.
        let mut tls = verified(&listener, server_config(&[&rustls::version::TLS13], 2)).await;
        let mut ping = [0u8; 4];
        tls.read_exact(&mut ping).await.unwrap();
        tls.write_all(b"pong").await.unwrap();
        // close_notify and FIN: the app sees its EOF.
        tls.shutdown().await.unwrap();
        (ping, read_to_gone(&mut tls).await)
    });
    let chan = Chan::direct(addr, 5_000);
    assert_eq!(chan.expect(event::OPEN).data, key("server_public_key"));
    assert_eq!(chan.write(b"ping"), 4);
    assert_eq!(chan.take(4, true), b"pong");
    chan.expect(event::EOF);
    assert_eq!(nox_chan_shutdown_write(chan.0), code::NONE);
    // Both directions are over: the channel ends by itself.
    assert_eq!(chan.closed(), code::NONE);
    let (ping, after) = rt.block_on(server).unwrap();
    assert_eq!(&ping, b"ping");
    assert_eq!(after, b"", "nothing after the close_notify");
    assert_eq!(nox_chan_close(chan.0), code::RET_CLOSED, "the handle is gone");
}

#[test]
fn bytes_written_before_the_check_wait_for_it() {
    let rt = runtime();
    let (listener, addr) = rt.block_on(listen());
    let server = rt.spawn(async move {
        let mut tls = accept(&listener, noxd_tls()).await;
        let binding = binding(&tls);
        // Exactly the device's message comes first: `verify` would refuse
        // anything else in these 160 bytes.
        let mut message = [0u8; MESSAGE_LEN];
        tls.read_exact(&mut message).await.unwrap();
        tls.write_all(&respond(key("server_seed"), &message, &binding).unwrap()).await.unwrap();
        let mut early = [0u8; 5];
        tls.read_exact(&mut early).await.unwrap();
        early
    });
    let chan = Chan::direct(addr, 5_000);
    assert_eq!(chan.write(b"early"), 5, "queued while the channel opens");
    chan.expect(event::OPEN);
    assert_eq!(&rt.block_on(server).unwrap(), b"early");
    // The server is gone by now, so an EOF may come first; CLOSED comes last.
    assert_eq!(nox_chan_close(chan.0), code::NONE);
    let events = chan.rest();
    assert!(events.len() <= 2 && events[0].kind != event::DATA, "{events:?}");
    assert_eq!(events.last().unwrap().code, code::NONE);
}

#[test]
fn shutdown_write_goes_after_the_queue_and_reading_goes_on() {
    let rt = runtime();
    let (listener, addr) = rt.block_on(listen());
    let server = rt.spawn(async move {
        let mut tls = verified(&listener, noxd_tls()).await;
        // The request ends with the app's close_notify.
        let request = read_to_gone(&mut tls).await;
        tls.write_all(b"response").await.unwrap();
        tls.shutdown().await.unwrap();
        request
    });
    let chan = Chan::direct(addr, 5_000);
    chan.expect(event::OPEN);
    assert_eq!(chan.write(b"request"), 7);
    assert_eq!(nox_chan_shutdown_write(chan.0), code::NONE);
    assert_eq!(nox_chan_shutdown_write(chan.0), code::NONE, "asking twice is asking once");
    assert_eq!(chan.write(b"more"), i64::from(code::RET_CLOSED), "no write side any more");
    assert_eq!(nox_chan_flush(chan.0, 5), code::NONE);

    let events = chan.rest();
    let data: Vec<u8> = events.iter().filter(|e| e.kind == event::DATA).flat_map(|e| e.data.clone()).collect();
    assert_eq!(data, b"response");
    assert!(events.contains(&Event { kind: event::DRAINED, data: Vec::new(), code: 5 }), "{events:?}");
    let eof = events.iter().position(|e| e.kind == event::EOF).expect("EOF");
    assert!(eof < events.len() - 1);
    assert_eq!(events.last().unwrap().code, code::NONE);
    assert_eq!(rt.block_on(server).unwrap(), b"request");
}

// --- Windows --------------------------------------------------------------

#[test]
fn inbound_bytes_stop_at_the_window_until_dart_acks_them() {
    const TOTAL: usize = 3 * WINDOW;
    let rt = runtime();
    let (listener, addr) = rt.block_on(listen());
    rt.spawn(async move {
        let mut tls = verified(&listener, noxd_tls()).await;
        for at in (0..TOTAL).step_by(CHUNK) {
            tls.write_all(&pattern(at, CHUNK)).await.unwrap();
        }
        tls.shutdown().await.unwrap();
        read_to_gone(&mut tls).await
    });
    let chan = Chan::direct(addr, 5_000);
    chan.expect(event::OPEN);

    // Not one byte past the window while nothing is acked.
    let first = chan.take(WINDOW, false);
    chan.assert_quiet(Duration::from_millis(300));
    assert_eq!(first, pattern(0, WINDOW));

    // An ack opens it again; acked as they come, the rest flows.
    assert_eq!(nox_chan_ack(chan.0, WINDOW), code::NONE);
    let rest = chan.take(TOTAL - WINDOW, true);
    assert_eq!(rest, pattern(WINDOW, TOTAL - WINDOW));
    chan.expect(event::EOF);
    assert_eq!(nox_chan_ack(chan.0, 1), code::RET_INVALID_ARGUMENT, "nothing is left to ack");
    assert_eq!(nox_chan_shutdown_write(chan.0), code::NONE);
    assert_eq!(chan.closed(), code::NONE);
}

#[test]
fn a_write_past_the_window_gets_writable_and_flush_tickets_drain_in_order() {
    const TOTAL: usize = 3 * WINDOW;
    let rt = runtime();
    let (listener, addr) = rt.block_on(listen());
    let server = rt.spawn(async move {
        let mut tls = verified(&listener, noxd_tls()).await;
        // Not reading for a while: the app's queue fills up.
        tokio::time::sleep(Duration::from_millis(300)).await;
        let mut got = vec![0u8; TOTAL];
        tls.read_exact(&mut got).await.unwrap();
        let tail = read_to_gone(&mut tls).await;
        (got, tail)
    });
    let chan = Chan::direct(addr, 5_000);
    chan.expect(event::OPEN);

    let queued = chan.write(&pattern(0, TOTAL));
    assert_eq!(queued, TOTAL as i64, "the whole write is queued");
    assert!(queued > WINDOW as i64);
    assert_eq!(nox_chan_flush(chan.0, 77), code::NONE);
    // WRITABLE once the queue is back within the window; DRAINED once all of
    // it is out - so in that order.
    assert_eq!(chan.next(), Event { kind: event::WRITABLE, data: Vec::new(), code: 0 });
    assert_eq!(chan.next(), Event { kind: event::DRAINED, data: Vec::new(), code: 77 });

    // Nothing queued: answered straight away.
    assert_eq!(nox_chan_flush(chan.0, 78), code::NONE);
    assert_eq!(chan.next(), Event { kind: event::DRAINED, data: Vec::new(), code: 78 });
    // Within the window: no WRITABLE owed.
    assert_eq!(chan.write(b"!"), 1);
    assert_eq!(nox_chan_flush(chan.0, 79), code::NONE);
    assert_eq!(nox_chan_flush(chan.0, 80), code::NONE);
    assert_eq!(chan.next(), Event { kind: event::DRAINED, data: Vec::new(), code: 79 });
    assert_eq!(chan.next(), Event { kind: event::DRAINED, data: Vec::new(), code: 80 });

    assert_eq!(nox_chan_close(chan.0), code::NONE);
    assert_eq!(chan.closed(), code::NONE);
    let (got, tail) = rt.block_on(server).unwrap();
    assert!(got == pattern(0, TOTAL), "the bytes arrived as written");
    assert_eq!(tail, b"!");
}

// --- Closing --------------------------------------------------------------

#[test]
fn a_close_while_opening_ends_the_channel_at_once() {
    let rt = runtime();
    let (listener, addr) = rt.block_on(listen());
    // Takes the connection and never says a word.
    rt.spawn(async move {
        let (_held, _) = listener.accept().await.unwrap();
        std::future::pending::<()>().await;
    });
    let chan = Chan::direct(addr, 30_000);
    std::thread::sleep(Duration::from_millis(100));
    let asked = Instant::now();
    assert_eq!(nox_chan_close(chan.0), code::NONE);
    // Closing: nothing else is taken any more.
    assert_eq!(chan.write(b"x"), i64::from(code::RET_CLOSED));
    assert_eq!(nox_chan_ack(chan.0, 0), code::RET_CLOSED);
    assert_eq!(nox_chan_flush(chan.0, 1), code::RET_CLOSED);
    assert_eq!(nox_chan_shutdown_write(chan.0), code::RET_CLOSED);
    assert_eq!(chan.closed(), code::NONE);
    assert!(asked.elapsed() < Duration::from_secs(2), "{:?}", asked.elapsed());
    assert_eq!(nox_chan_close(chan.0), code::RET_CLOSED);
}

#[test]
fn closed_is_the_last_word_of_an_open_channel() {
    let rt = runtime();
    let (listener, addr) = rt.block_on(listen());
    rt.spawn(async move {
        let mut tls = verified(&listener, noxd_tls()).await;
        // Talks until the app is gone.
        while tls.write_all(&[7u8; 1024]).await.is_ok() {
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    });
    let chan = Chan::direct(addr, 5_000);
    chan.expect(event::OPEN);
    let first = chan.expect(event::DATA);
    assert_eq!(nox_chan_ack(chan.0, first.data.len()), code::NONE);
    assert_eq!(nox_chan_close(chan.0), code::NONE);
    let second = nox_chan_close(chan.0);
    assert!(second == code::NONE || second == code::RET_CLOSED, "{second}");
    let events = chan.rest();
    assert!(events[..events.len() - 1].iter().all(|e| e.kind == event::DATA), "{events:?}");
    assert_eq!(events.last().unwrap().code, code::NONE);
    chan.assert_quiet(Duration::from_millis(300));
    assert_eq!(chan.write(b"x"), i64::from(code::RET_CLOSED));
    assert_eq!(nox_chan_close(chan.0), code::RET_CLOSED);
}

#[test]
fn handles_are_positive_and_never_reused() {
    let rt = runtime();
    let (listener, addr) = rt.block_on(listen());
    drop(listener);
    let first = Chan::direct(addr, 1_000);
    assert_eq!(first.closed(), code::NETWORK);
    let second = Chan::direct(addr, 1_000);
    assert!(second.0 > first.0);
    assert_eq!(second.closed(), code::NETWORK);
}

// --- Servers that must not get a channel ----------------------------------

#[test]
fn another_servers_key_is_wrong_server_and_it_hears_the_message_alone() {
    let rt = runtime();
    let (listener, addr) = rt.block_on(listen());
    let server = rt.spawn(async move {
        let mut tls = accept(&listener, noxd_tls()).await;
        let binding = binding(&tls);
        let mut message = [0u8; MESSAGE_LEN];
        tls.read_exact(&mut message).await.unwrap();
        // A real server with another key: it takes the device and answers.
        tls.write_all(&respond(key("wrong_server_seed"), &message, &binding).unwrap()).await.unwrap();
        (message, read_to_gone(&mut tls).await)
    });
    let chan = Chan::direct(addr, 5_000);
    assert_eq!(chan.write(b"token"), 5, "an app that already has bytes for it");
    assert_eq!(chan.closed(), code::WRONG_SERVER);
    let (message, after) = rt.block_on(server).unwrap();
    // The device's key and its signature over the key - the binding's
    // signature differs per connection.
    assert_eq!(message[..96], vector("app_message")[..96]);
    assert_eq!(after, b"", "the wrong server heard nothing but the message");
}

/// A relay with a TLS session to each side passes the Eidolon messages along.
/// The real server answers anyway here, so it is the app's own check that has
/// to catch him: the answer is the real server's, signed over the binding of
/// the relay's session, not the app's.
#[test]
fn a_man_in_the_middle_is_caught_by_the_app() {
    let rt = runtime();
    let (server_listener, server_addr) = rt.block_on(listen());
    let (relay_listener, relay_addr) = rt.block_on(listen());
    let server = rt.spawn(async move {
        let mut tls = accept(&server_listener, noxd_tls()).await;
        let binding = binding(&tls);
        let mut message = [0u8; MESSAGE_LEN];
        tls.read_exact(&mut message).await.unwrap();
        let verdict = respond(key("server_seed"), &message, &binding);
        tls.write_all(&message_of(key("server_seed"), &binding)).await.unwrap();
        read_to_gone(&mut tls).await;
        verdict
    });
    rt.spawn(async move {
        let mut app = accept(&relay_listener, noxd_tls()).await;
        let tcp = TcpStream::connect(server_addr).await.unwrap();
        let mut config = ClientConfig::builder_with_provider(provider())
            .with_protocol_versions(&[&rustls::version::TLS13])
            .unwrap()
            .dangerous()
            .with_custom_certificate_verifier(Arc::new(TrustAnything))
            .with_no_client_auth();
        config.alpn_protocols = vec![b"http/1.1".to_vec()];
        let name = ServerName::try_from("relay.invalid").unwrap();
        let mut server = TlsConnector::from(Arc::new(config)).connect(name, tcp).await.unwrap();
        let mut message = [0u8; MESSAGE_LEN];
        app.read_exact(&mut message).await.unwrap();
        server.write_all(&message).await.unwrap();
        let mut answer = [0u8; MESSAGE_LEN];
        server.read_exact(&mut answer).await.unwrap();
        app.write_all(&answer).await.unwrap();
        let _ = tokio::io::copy_bidirectional(&mut app, &mut server).await;
    });
    let chan = Chan::direct(relay_addr, 5_000);
    assert_eq!(chan.closed(), code::PROTOCOL);
    // And the server, for its part, refused the device's relayed message.
    assert_eq!(rt.block_on(server).unwrap(), Err("SigMismatch".to_owned()));
}

#[test]
fn an_answer_of_another_length_is_protocol() {
    for len in [100, MESSAGE_LEN - 1] {
        let rt = runtime();
        let (listener, addr) = rt.block_on(listen());
        rt.spawn(async move {
            let mut tls = accept(&listener, noxd_tls()).await;
            let binding = binding(&tls);
            let mut message = [0u8; MESSAGE_LEN];
            tls.read_exact(&mut message).await.unwrap();
            let answer = respond(key("server_seed"), &message, &binding).unwrap();
            tls.write_all(&answer[..len]).await.unwrap();
            tls.shutdown().await.unwrap();
            read_to_gone(&mut tls).await;
        });
        let chan = Chan::direct(addr, 5_000);
        assert_eq!(chan.closed(), code::PROTOCOL, "{len} bytes");
    }
}

/// The server of 036 and before: TLS, then HTTP straight away. It reads the
/// device's message as a request line and answers 400.
#[test]
fn a_server_that_answers_http_is_protocol() {
    let short = b"HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain; charset=utf-8\r\nConnection: close\r\n\r\n400 Bad Request".to_vec();
    let mut long = b"HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain; charset=utf-8\r\n".to_vec();
    long.extend(b"X-Padding: ".iter().chain([b'a'; 120].iter()));
    long.extend(b"\r\nConnection: close\r\n\r\n400 Bad Request");
    assert!(short.len() < MESSAGE_LEN && long.len() > MESSAGE_LEN);
    for response in [short, long] {
        let rt = runtime();
        let (listener, addr) = rt.block_on(listen());
        let len = response.len();
        rt.spawn(async move {
            let mut tls = accept(&listener, noxd_tls()).await;
            let mut request = [0u8; 64];
            let _ = tls.read(&mut request).await;
            tls.write_all(&response).await.unwrap();
            tls.shutdown().await.unwrap();
            read_to_gone(&mut tls).await;
        });
        let chan = Chan::direct(addr, 5_000);
        assert_eq!(chan.closed(), code::PROTOCOL, "a response of {len} bytes");
    }
}

#[test]
fn a_server_without_tls_1_3_is_refused_as_tls() {
    let rt = runtime();
    let (listener, addr) = rt.block_on(listen());
    rt.spawn(async move {
        let tls12 = server_config(&[&rustls::version::TLS12], 0);
        let (tcp, _) = listener.accept().await.unwrap();
        let _ = TlsAcceptor::from(tls12).accept(tcp).await;
    });
    assert_eq!(Chan::direct(addr, 5_000).closed(), code::TLS);

    let (listener, addr) = rt.block_on(listen());
    rt.spawn(async move {
        let (mut tcp, _) = listener.accept().await.unwrap();
        let mut hello = [0u8; 16];
        let _ = tcp.read(&mut hello).await;
        let _ = tcp.write_all(b"HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n").await;
    });
    assert_eq!(Chan::direct(addr, 5_000).closed(), code::TLS, "plain HTTP");
}

#[test]
fn a_closed_port_is_the_networks_failure() {
    let rt = runtime();
    let (listener, addr) = rt.block_on(listen());
    drop(listener);
    assert_eq!(Chan::direct(addr, 5_000).closed(), code::NETWORK);
}

#[test]
fn a_server_that_never_answers_runs_out_of_the_budget() {
    // Silent after TCP, and silent after TLS: one budget covers both.
    for after_tls in [false, true] {
        let rt = runtime();
        let (listener, addr) = rt.block_on(listen());
        rt.spawn(async move {
            if after_tls {
                let _tls = accept(&listener, noxd_tls()).await;
                std::future::pending::<()>().await;
            } else {
                let (_tcp, _) = listener.accept().await.unwrap();
                std::future::pending::<()>().await;
            }
        });
        let started = Instant::now();
        let chan = Chan::direct(addr, 300);
        assert_eq!(chan.closed(), code::TIMEOUT, "after TLS: {after_tls}");
        let took = started.elapsed();
        assert!(took >= Duration::from_millis(300) && took < Duration::from_secs(3), "{took:?}");
    }
}

#[test]
fn an_onion_channel_without_tor_is_not_ready() {
    let onion = "25njqamcweflpvkl73j4szahhihoc4xt3ktcgjnpaingr5yhkenl5sid.onion";
    let chan = Chan::open(1, onion, 443, key("server_public_key"), 5_000);
    assert_eq!(chan.closed(), code::TOR_NOT_READY);
    let chan = Chan::open(1, "not-an-onion.example", 443, key("server_public_key"), 5_000);
    assert_eq!(chan.closed(), code::TOR_ONION_INVALID);
}

// --- An isolate that went away --------------------------------------------

/// Taken by the two tests that lose an isolate, so they never run side by
/// side: a reap probes every channel of the process, and would end the other
/// test's channel - its isolate is gone too - before that test saw its own
/// event refused, or before it could write to it at all.
static LOST_ISOLATES: Mutex<()> = Mutex::new(());

/// The isolate died under an open channel: the next event is refused, and the
/// module ends the channel itself - nothing else would, with nobody left to
/// ack or to close.
#[test]
fn a_channel_whose_isolate_is_gone_ends_itself() {
    let _alone = lock(&LOST_ISOLATES);
    let rt = runtime();
    let (listener, addr) = rt.block_on(listen());
    let server = rt.spawn(async move {
        let mut tls = verified(&listener, noxd_tls()).await;
        let mut ping = [0u8; 1];
        tls.read_exact(&mut ping).await.unwrap();
        // Talks until the connection is gone; the app never acks a byte.
        let started = Instant::now();
        while tls.write_all(&[7u8; 1024]).await.is_ok() && tls.flush().await.is_ok() {
            tokio::time::sleep(Duration::from_millis(5)).await;
            if started.elapsed() > PATIENCE {
                return false;
            }
        }
        true
    });
    let chan = Chan::direct(addr, 5_000);
    chan.expect(event::OPEN);
    chan.lose_isolate();
    assert_eq!(chan.write(b"!"), 1);
    // Bounded: a channel that never ends stops reading, and the server's
    // writes then wait on a full window for good, its own deadline unchecked.
    let let_go = rt.block_on(async { tokio::time::timeout(2 * PATIENCE, server).await });
    assert!(let_go.expect("the server is still held").unwrap(), "the server was let go of");
    let gone = Instant::now();
    while nox_chan_close(chan.0) != code::RET_CLOSED {
        assert!(gone.elapsed() < PATIENCE, "the handle outlived its connection");
        std::thread::sleep(Duration::from_millis(20));
    }
}

/// A new isolate reaps what an old one left behind: a channel still opening -
/// no event of its own would ever be refused before its budget ran out - ends
/// at once, and one whose isolate is there is left alone.
#[test]
fn a_reap_ends_the_channels_of_gone_isolates_and_only_those() {
    let _alone = lock(&LOST_ISOLATES);
    let rt = runtime();
    let (listener, addr) = rt.block_on(listen());
    let (accepted, mut connections) = tokio::sync::mpsc::unbounded_channel();
    // Takes connections and says nothing; reports when each one ends.
    rt.spawn(async move {
        loop {
            let (mut tcp, _) = listener.accept().await.unwrap();
            let (ended, rx) = tokio::sync::oneshot::channel();
            accepted.send(rx).unwrap();
            tokio::spawn(async move {
                read_to_gone(&mut tcp).await;
                let _ = ended.send(());
            });
        }
    });
    let left = Chan::direct(addr, 60_000);
    let mut left_ended = rt.block_on(connections.recv()).unwrap();
    let kept = Chan::direct(addr, 60_000);
    let mut kept_ended = rt.block_on(connections.recv()).unwrap();

    left.lose_isolate();
    assert!(nox_chan_reap() >= 1, "the channel of the gone isolate was found");
    rt.block_on(async {
        tokio::time::timeout(PATIENCE, &mut left_ended).await.expect("its connection ends").unwrap();
    });
    let reaped = Instant::now();
    while nox_chan_close(left.0) != code::RET_CLOSED {
        assert!(reaped.elapsed() < PATIENCE, "the reaped handle is still there");
        std::thread::sleep(Duration::from_millis(20));
    }

    // The live one is untouched, and still the app's to close.
    rt.block_on(async {
        assert!(
            tokio::time::timeout(Duration::from_millis(300), &mut kept_ended).await.is_err(),
            "the live one was cut"
        );
    });
    assert_eq!(nox_chan_close(kept.0), code::NONE);
    assert_eq!(kept.closed(), code::NONE);
    left.assert_quiet(Duration::from_millis(100));
}
