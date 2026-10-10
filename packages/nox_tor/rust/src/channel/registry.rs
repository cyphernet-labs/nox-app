//! Which channels exist, how their events leave the module, and how each one
//! ends.
//!
//! Three promises of the contract live here and nowhere else: a handle is
//! positive and never reused within the process; CLOSED is the last event of a
//! handle, sent exactly once, after which its port never hears of it again;
//! and a call on a handle whose CLOSED went out finds nothing (-9), because the
//! handle leaves the map before its CLOSED leaves the module.
//!
//! And one the module keeps for itself: a channel whose isolate is gone - its
//! port refused an event, or a probe (`reap`) - ends at once, with nobody to
//! tell. Nothing else would end it: no ack comes from a dead isolate, and a
//! quiet server never says anything that would fail to arrive.

use std::collections::BTreeMap;
use std::sync::atomic::{AtomicI32, AtomicI64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};

use tokio::sync::Notify;

use super::dart::Port;
use super::{code, event, Channel};
use crate::engine::lock;

static CHANNELS: Mutex<BTreeMap<i64, Arc<Channel>>> = Mutex::new(BTreeMap::new());
static NEXT_HANDLE: AtomicI64 = AtomicI64::new(1);

/// A new channel under a handle no channel of this process had before.
pub(crate) fn register(port: Port) -> Arc<Channel> {
    let handle = NEXT_HANDLE.fetch_add(1, Ordering::Relaxed);
    let channel = Arc::new(Channel::new(handle, port));
    lock(&CHANNELS).insert(handle, Arc::clone(&channel));
    channel
}

pub(crate) fn find(handle: i64) -> Option<Arc<Channel>> {
    lock(&CHANNELS).get(&handle).cloned()
}

/// Every channel whose CLOSED has not gone out yet.
pub(crate) fn all() -> Vec<Arc<Channel>> {
    lock(&CHANNELS).values().cloned().collect()
}

fn forget(handle: i64) {
    lock(&CHANNELS).remove(&handle);
}

/// The one way out of the module for the events of one channel.
///
/// Posted under a lock of their own, so they leave in the order the channel
/// made them whichever thread makes the next one, and so nothing can follow
/// CLOSED. A post only queues a message for the isolate and returns, so
/// holding the lock across it cannot deadlock.
pub(crate) struct Events {
    handle: i64,
    port: Port,
    line: Mutex<Line>,
    /// The port refused: the driver ends the channel.
    lost_signal: Notify,
}

#[derive(Default)]
struct Line {
    /// CLOSED went out.
    closed: bool,
    /// The port took nothing: its isolate is gone, and so is everyone who
    /// could ask anything of this channel.
    lost: bool,
}

impl Events {
    pub(crate) fn new(handle: i64, port: Port) -> Self {
        Events { handle, port, line: Mutex::new(Line::default()), lost_signal: Notify::new() }
    }

    /// An event after CLOSED, or after the isolate was lost, is not sent.
    fn send(&self, kind: i32, data: &[u8], code: i32) {
        let mut line = lock(&self.line);
        if line.closed || line.lost {
            return;
        }
        line.closed = kind == event::CLOSED;
        if !self.port.post(self.handle, kind, code, data) {
            self.lose(line);
        }
    }

    fn lose(&self, mut line: MutexGuard<'_, Line>) {
        line.lost = true;
        drop(line);
        // One waiter, the driver; a permit is kept if it is not waiting yet.
        self.lost_signal.notify_one();
    }

    /// Completes once the isolate that opened the channel is known to be gone.
    pub(crate) async fn lost(&self) {
        if !lock(&self.line).lost {
            self.lost_signal.notified().await;
        }
    }

    /// Whether the isolate that opened the channel is still there: a probe it
    /// drops if it is. A channel whose CLOSED went out has no isolate to ask
    /// about any more.
    pub(crate) fn probe(&self) -> bool {
        let line = lock(&self.line);
        if line.lost {
            return false;
        }
        if line.closed || self.port.post(0, event::PROBE, code::NONE, &[]) {
            return true;
        }
        self.lose(line);
        false
    }

    /// The channel is verified; `key` is the server's, which Eidolon checked.
    pub(crate) fn open(&self, key: &[u8; 32]) {
        self.send(event::OPEN, key, code::NONE);
    }

    pub(crate) fn data(&self, bytes: &[u8]) {
        self.send(event::DATA, bytes, code::NONE);
    }

    pub(crate) fn writable(&self) {
        self.send(event::WRITABLE, &[], code::NONE);
    }

    pub(crate) fn drained(&self, ticket: i32) {
        self.send(event::DRAINED, &[], ticket);
    }

    pub(crate) fn eof(&self) {
        self.send(event::EOF, &[], code::NONE);
    }

    fn closed(&self, code: i32) {
        self.send(event::CLOSED, &[], code);
    }
}

/// How a channel ends: its handle leaves the map, then CLOSED leaves the
/// module - once, whatever ends it.
///
/// The driver task owns it. A task that returns says why with `finish`; one
/// that never returns is dropped - its runtime went away (the Tor client
/// stopped under an onion channel), or it panicked - and the drop sends CLOSED
/// instead, so Dart is never left waiting on a handle nobody drives.
pub(crate) struct Closer {
    channel: Arc<Channel>,
    on_drop: AtomicI32,
    done: bool,
}

impl Closer {
    /// `on_drop` is what a drop reports until `on_drop` says otherwise.
    pub(crate) fn new(channel: Arc<Channel>, on_drop: i32) -> Self {
        Closer { channel, on_drop: AtomicI32::new(on_drop), done: false }
    }

    pub(crate) fn channel(&self) -> &Arc<Channel> {
        &self.channel
    }

    pub(crate) fn on_drop(&self, code: i32) {
        self.on_drop.store(code, Ordering::Relaxed);
    }

    pub(crate) fn finish(mut self, code: i32) {
        self.end(code);
    }

    fn end(&mut self, code: i32) {
        self.done = true;
        forget(self.channel.handle);
        self.channel.events.closed(code);
    }
}

impl Drop for Closer {
    fn drop(&mut self) {
        if self.done {
            return;
        }
        let code = if std::thread::panicking() {
            code::INTERNAL
        } else if self.channel.closing() {
            // The app asked for the end, and got it.
            code::NONE
        } else {
            self.on_drop.load(Ordering::Relaxed)
        };
        self.end(code);
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use std::sync::atomic::{AtomicBool, AtomicUsize};

    use super::super::dart::{decode, DartCObject};
    use super::*;

    type Seen = (i32, Vec<u8>, i32);

    static SEEN: Mutex<Vec<(i64, Seen)>> = Mutex::new(Vec::new());

    /// The port of an isolate that is there, and of one that is gone.
    pub(crate) const LIVE: i64 = 1;
    pub(crate) const GONE: i64 = 2;

    /// Takes every event the way Dart's port does - or, for the port of an
    /// isolate that is gone, refuses it.
    pub(crate) unsafe extern "C" fn record(port: i64, message: *mut DartCObject) -> i8 {
        if port == GONE {
            return 0;
        }
        let (handle, kind, code, bytes) = decode(message).expect("an event message");
        lock(&SEEN).push((handle, (kind, bytes, code)));
        1
    }

    pub(crate) fn live() -> Port {
        Port::new(record, LIVE)
    }

    fn gone() -> Port {
        Port::new(record, GONE)
    }

    pub(crate) fn seen(handle: i64) -> Vec<Seen> {
        lock(&SEEN).iter().filter(|(h, _)| *h == handle).map(|(_, e)| e.clone()).collect()
    }

    #[test]
    fn handles_are_positive_and_never_come_back() {
        let first = register(live());
        let second = register(live());
        assert!(first.handle > 0 && second.handle > first.handle);
        Closer::new(Arc::clone(&first), code::NONE).finish(code::NONE);
        let third = register(live());
        assert!(third.handle > second.handle, "{} came back", first.handle);
        for channel in [second, third] {
            Closer::new(channel, code::NONE).finish(code::NONE);
        }
    }

    #[test]
    fn nothing_follows_closed_and_closed_goes_once() {
        let channel = register(live());
        let handle = channel.handle;
        channel.events.open(&[7u8; 32]);
        channel.events.data(b"hello");
        Closer::new(Arc::clone(&channel), code::NETWORK).finish(code::TLS);
        channel.events.data(b"late");
        channel.events.eof();
        channel.events.closed(code::NONE);
        assert_eq!(
            seen(handle),
            [
                (event::OPEN, vec![7u8; 32], code::NONE),
                (event::DATA, b"hello".to_vec(), code::NONE),
                (event::CLOSED, Vec::new(), code::TLS),
            ]
        );
    }

    #[test]
    fn the_handle_is_gone_before_its_closed_goes_out() {
        let channel = register(live());
        let handle = channel.handle;
        assert!(find(handle).is_some());
        Closer::new(channel, code::NONE).finish(code::NONE);
        assert!(find(handle).is_none());
    }

    #[test]
    fn a_closer_dropped_unfinished_still_closes() {
        let channel = register(live());
        let handle = channel.handle;
        let closer = Closer::new(channel, code::TOR_NOT_READY);
        drop(closer);
        assert_eq!(seen(handle), [(event::CLOSED, Vec::new(), code::TOR_NOT_READY)]);
        assert!(find(handle).is_none());

        // Once the app asked for the end, the end is a normal one.
        let channel = register(live());
        let handle = channel.handle;
        let closer = Closer::new(Arc::clone(&channel), code::NETWORK);
        channel.request_close();
        drop(closer);
        assert_eq!(seen(handle), [(event::CLOSED, Vec::new(), code::NONE)]);
    }

    #[test]
    fn a_panic_in_the_driver_closes_as_internal() {
        let channel = register(live());
        let handle = channel.handle;
        let closer = Closer::new(channel, code::NETWORK);
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(move || {
            let _owned = closer;
            panic!("a bug in the driver");
        }));
        assert_eq!(seen(handle), [(event::CLOSED, Vec::new(), code::INTERNAL)]);
    }

    #[tokio::test]
    async fn a_refused_event_loses_the_line_and_wakes_the_driver() {
        let channel = register(gone());
        {
            // The driver is already waiting when the refusal comes: polled
            // once, the wait is past its look at the line and parked, so only
            // the notification can end it. A waiter that ran only after the
            // refusal would find the line lost and never wait at all.
            let mut lost = std::pin::pin!(channel.events.lost());
            assert!(futures::poll!(lost.as_mut()).is_pending(), "the driver waits while the isolate is there");
            channel.events.data(b"nobody");
            tokio::time::timeout(std::time::Duration::from_secs(5), lost).await.expect("the driver is told");
        }
        // Lost for good: nothing is posted again, and a probe says so.
        assert!(!channel.events.probe());
        channel.events.lost().await;
        Closer::new(channel, code::NONE).finish(code::NONE);
    }

    #[test]
    fn a_probe_tells_a_live_isolate_from_a_gone_one() {
        let here = register(live());
        let away = register(gone());
        assert!(here.events.probe());
        assert!(!away.events.probe());
        assert!(seen(here.handle).is_empty(), "a probe is no event of the channel");
        for channel in [here, away] {
            Closer::new(channel, code::NONE).finish(code::NONE);
        }

        // An isolate that took the channel's CLOSED and went away after it:
        // its port refuses whatever comes next, and counts what is posted.
        const LEAVING: i64 = 3;
        static LEFT: AtomicBool = AtomicBool::new(false);
        static POSTS: AtomicUsize = AtomicUsize::new(0);
        unsafe extern "C" fn until_left(port: i64, message: *mut DartCObject) -> i8 {
            POSTS.fetch_add(1, Ordering::SeqCst);
            if LEFT.load(Ordering::SeqCst) {
                0
            } else {
                record(port, message)
            }
        }

        // Its CLOSED went out: there is nobody left to ask about, so the probe
        // answers without asking - a post would be refused here, and would
        // call a channel that ended normally lost.
        let ended = register(Port::new(until_left, LEAVING));
        Closer::new(Arc::clone(&ended), code::NONE).finish(code::NONE);
        assert_eq!(seen(ended.handle), [(event::CLOSED, Vec::new(), code::NONE)]);
        LEFT.store(true, Ordering::SeqCst);
        let posts = POSTS.load(Ordering::SeqCst);
        assert!(ended.events.probe());
        assert_eq!(POSTS.load(Ordering::SeqCst), posts, "a probe was posted after CLOSED");
    }
}
