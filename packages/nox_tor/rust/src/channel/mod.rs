//! The app's channel to its server (phase 044): every connection, verified
//! before the app sees a byte of it.
//!
//! The socket for commands and every file transfer go through here and nowhere
//! else. A channel is three layers:
//!
//! 1. A transport (`target`): TCP to an address, or a Tor stream to the onion
//!    service through the client `engine` runs.
//! 2. TLS 1.3 (`tls`), which checks that the server signed the handshake and
//!    nothing about the certificate it signed with: that is a throwaway one the
//!    server makes at every start, and what a certificate would prove, the next
//!    layer proves.
//! 3. Eidolon (`eidolon`) over the TLS channel binding: the device shows its key
//!    first, the server answers with its own, and the channel opens only when
//!    that is the key the pairing link named. A man in the middle holds two TLS
//!    sessions, so two bindings, and can sign for neither side over the other.
//!
//! Then the bytes go to Dart as events, posted to a port of the isolate that
//! opened the channel (`dart`, `registry`), and are pumped both ways under a
//! window each (`pump`). The contract is
//! `specs/044-secure-channel/contracts/ffi-channel.md`.

pub mod dart;
pub mod eidolon;
pub mod pump;
pub mod registry;
pub mod target;
pub mod tls;

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tokio::runtime::{Handle, Runtime};
use tokio::sync::Notify;
use tokio_rustls::client::TlsStream;

use crate::engine::{self, lock};
use eidolon::DeviceSeed;
use pump::{Flush, Pump};
use registry::{Closer, Events};
use target::{OnionContext, Transport};

/// Bytes either way may hold for the other side: inbound, what Dart has not
/// acknowledged yet; outbound, what Dart queued and TLS has not taken.
pub const WINDOW: usize = 1 << 20;

/// The most one DATA event carries.
pub const CHUNK: usize = 64 * 1024;

/// The `code` of a CLOSED event, and the negative returns of the C ABI.
pub mod code {
    pub const NONE: i32 = 0;
    pub const NETWORK: i32 = 1;
    pub const TIMEOUT: i32 = 2;
    pub const TLS: i32 = 3;
    pub const PROTOCOL: i32 = 4;
    pub const WRONG_SERVER: i32 = 5;
    pub const TOR_NOT_READY: i32 = 6;
    pub const TOR_ONION_INVALID: i32 = 7;
    pub const TOR_ONION_NOT_FOUND: i32 = 8;
    pub const TOR_ONION_UNREACHABLE: i32 = 9;
    /// Not produced since 045: the client holds no keys, and a service that
    /// asks for one is TOR_ONION_UNREACHABLE. Keeps its number, so the codes
    /// the app binds stay where they are.
    pub const TOR_CLIENT_AUTH: i32 = 10;
    pub const INTERNAL: i32 = 11;

    pub const RET_INVALID_ARGUMENT: i32 = -7;
    pub const RET_CLOSED: i32 = -9;
}

/// The `kind` of an event.
pub mod event {
    /// Not an event: what `nox_chan_reap` posts to learn whether an isolate is
    /// still there. Handle 0; Dart drops it.
    pub const PROBE: i32 = 0;
    pub const OPEN: i32 = 1;
    pub const DATA: i32 = 2;
    pub const WRITABLE: i32 = 3;
    pub const DRAINED: i32 = 4;
    pub const EOF: i32 = 5;
    pub const CLOSED: i32 = 6;
}

/// Where a channel goes: `target_kind` 0 and 1 of `nox_chan_open`.
pub enum Target {
    /// An IP address or a name, and a port.
    Direct { host: String, port: u16 },
    /// `<56>.onion` and its port, through the Tor client.
    Onion { host: String, port: u16 },
}

/// One channel, as both sides of it see it: the C ABI, which queues, acks and
/// asks, and the task that drives it.
pub struct Channel {
    pub(crate) handle: i64,
    pub(crate) events: Events,
    pub(crate) pump: Pump,
    closing: AtomicBool,
    close_signal: Notify,
}

impl Channel {
    fn new(handle: i64, port: dart::Port) -> Self {
        Channel {
            handle,
            events: Events::new(handle, port),
            pump: Pump::default(),
            closing: AtomicBool::new(false),
            close_signal: Notify::new(),
        }
    }

    fn request_close(&self) {
        self.closing.store(true, Ordering::SeqCst);
        // One waiter, the driver; a permit is kept if it is not waiting yet.
        self.close_signal.notify_one();
    }

    pub(crate) fn closing(&self) -> bool {
        self.closing.load(Ordering::SeqCst)
    }

    async fn close_requested(&self) {
        if !self.closing() {
            self.close_signal.notified().await;
        }
    }
}

/// Opens a channel: returns its handle at once, and the rest comes as events
/// posted to `port`. Negative only when there is nowhere to run it.
pub fn open(target: Target, seed: DeviceSeed, server_key: [u8; 32], budget: Duration, port: dart::Port) -> i64 {
    // An onion channel runs on the Tor client's own runtime, as the client's
    // streams do; one the client cannot take yet still needs a runtime to say so.
    let onion = match &target {
        Target::Onion { .. } => engine::onion_context(),
        Target::Direct { .. } => None,
    };
    let runtime = match onion.as_ref() {
        Some(ctx) => ctx.runtime.clone(),
        None => match runtime() {
            Some(handle) => handle,
            None => return -i64::from(code::INTERNAL),
        },
    };
    let channel = registry::register(port);
    let handle = channel.handle;
    // A task dropped before it ever ran means its runtime is gone: for an onion
    // channel, the Tor client stopped in between.
    let closer = Closer::new(channel, if onion.is_some() { code::TOR_NOT_READY } else { code::INTERNAL });
    runtime.spawn(drive(closer, target, onion, seed, server_key, budget));
    handle
}

/// The life of one channel, from the first connect to its CLOSED event.
async fn drive(
    closer: Closer,
    target: Target,
    onion: Option<OnionContext>,
    seed: DeviceSeed,
    server_key: [u8; 32],
    budget: Duration,
) {
    // From here on a drop means the runtime went away under a live channel.
    closer.on_drop(code::NETWORK);
    let channel = Arc::clone(closer.channel());
    let code = tokio::select! {
        biased;
        () = channel.close_requested() => code::NONE,
        // Nobody is left to hear of it, or to ask for anything more.
        () = channel.events.lost() => code::NONE,
        code = run(&channel, target, onion, seed, &server_key, budget) => code,
    };
    closer.finish(code);
}

async fn run(
    channel: &Channel,
    target: Target,
    onion: Option<OnionContext>,
    seed: DeviceSeed,
    server_key: &[u8; 32],
    budget: Duration,
) -> i32 {
    // One budget for the transport, TLS and Eidolon together: what the app
    // waits for is a channel it can use, not any one of the steps.
    let (stream, key) = match tokio::time::timeout(budget, establish(target, onion, seed, server_key)).await {
        Ok(Ok(opened)) => opened,
        Ok(Err(code)) => return code,
        Err(_) => return code::TIMEOUT,
    };
    channel.events.open(&key);
    let (reader, writer) = tokio::io::split(stream);
    match tokio::try_join!(pump::read(channel, reader), pump::write(channel, writer)) {
        Ok(_) => code::NONE,
        Err(code) => code,
    }
}

/// The three layers. Nothing reaches the stream before the device's Eidolon
/// message, and the stream reaches nobody before the server's answer checked.
async fn establish(
    target: Target,
    onion: Option<OnionContext>,
    seed: DeviceSeed,
    server_key: &[u8; 32],
) -> Result<(TlsStream<Box<dyn Transport>>, [u8; 32]), i32> {
    let transport: Box<dyn Transport> = match target {
        Target::Direct { host, port } => Box::new(target::direct(&host, port).await?),
        Target::Onion { host, port } => {
            // A broken address is broken whether or not Tor is up.
            let hsid = target::parse_onion(&host)?;
            let ctx = onion.ok_or(code::TOR_NOT_READY)?;
            Box::new(target::onion(&ctx, host, hsid, port).await?)
        }
    };
    let mut stream = tls::connect(transport).await?;
    let binding = tls::channel_binding(stream.get_ref().1)?;
    let key = eidolon::handshake(&mut stream, seed, server_key, &binding).await?;
    Ok((stream, key))
}

/// A channel the app may still use: registered, and not being closed.
fn usable(handle: i64) -> Option<Arc<Channel>> {
    registry::find(handle).filter(|channel| !channel.closing())
}

/// `nox_chan_write`: the queued size after the write.
pub fn write(handle: i64, bytes: &[u8]) -> i64 {
    usable(handle).map_or(i64::from(code::RET_CLOSED), |channel| channel.pump.write(bytes))
}

/// `nox_chan_ack`.
pub fn ack(handle: i64, len: usize) -> i32 {
    usable(handle).map_or(code::RET_CLOSED, |channel| channel.pump.ack(len))
}

/// `nox_chan_flush`. Answered here, at once, only when the write side is
/// already shut: every byte was flushed, and no writer is left to answer.
pub fn flush(handle: i64, ticket: i32) -> i32 {
    let Some(channel) = usable(handle) else {
        return code::RET_CLOSED;
    };
    if let Flush::Now = channel.pump.flush(ticket) {
        channel.events.drained(ticket);
    }
    0
}

/// `nox_chan_shutdown_write`.
pub fn shutdown_write(handle: i64) -> i32 {
    usable(handle).map_or(code::RET_CLOSED, |channel| channel.pump.shutdown_write())
}

/// `nox_chan_close`: the driver tears the channel down and sends CLOSED. A
/// second close before that is no error.
pub fn close(handle: i64) -> i32 {
    match registry::find(handle) {
        Some(channel) => {
            channel.request_close();
            0
        }
        None => code::RET_CLOSED,
    }
}

/// `nox_chan_reap`: ends every channel whose isolate is gone, and says how
/// many there were. An isolate that died - a hot restart, an engine Android
/// tore down - leaves its channels running in the process, connected to the
/// server, until an event to one of them is refused; a new isolate calls this
/// before it opens any, so they end at once instead.
pub fn reap() -> i32 {
    let gone = registry::all().iter().filter(|channel| !channel.events.probe()).count();
    i32::try_from(gone).unwrap_or(i32::MAX)
}

/// `nox_chan_buf_free`: frees a buffer the module handed out as a result.
///
/// # Safety
/// `data` and `len` are what one call handed out, freed once; or `data` is
/// null.
pub unsafe fn free_buffer(data: *mut u8, len: usize) {
    if !data.is_null() {
        drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(data, len)));
    }
}

/// The runtime of every channel that does not go through Tor. Built with the
/// first one and kept for the process: the direct path needs no Tor client,
/// and must not stop with one.
fn runtime() -> Option<Handle> {
    static RUNTIME: Mutex<Option<Runtime>> = Mutex::new(None);
    let mut slot = lock(&RUNTIME);
    if slot.is_none() {
        *slot = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .thread_name("nox-chan")
            .enable_all()
            .build()
            .ok();
    }
    slot.as_ref().map(|rt| rt.handle().clone())
}
