//! Which channels exist, how their events leave the module, and how each one
//! ends.
//!
//! Three promises of the contract live here and nowhere else: a handle is
//! positive and never reused within the process; CLOSED is the last event of a
//! handle, sent exactly once, after which the callback never hears of it again;
//! and a call on a handle whose CLOSED went out finds nothing (-9), because the
//! handle leaves the map before its CLOSED leaves the module.

use std::collections::BTreeMap;
use std::sync::atomic::{AtomicI32, AtomicI64, Ordering};
use std::sync::{Arc, Mutex};

use super::{code, event, Channel, EventFn};
use crate::engine::lock;

static CHANNELS: Mutex<BTreeMap<i64, Arc<Channel>>> = Mutex::new(BTreeMap::new());
static NEXT_HANDLE: AtomicI64 = AtomicI64::new(1);

/// A new channel under a handle no channel of this process had before.
pub(crate) fn register(on_event: EventFn) -> Arc<Channel> {
    let handle = NEXT_HANDLE.fetch_add(1, Ordering::Relaxed);
    let channel = Arc::new(Channel::new(handle, on_event));
    lock(&CHANNELS).insert(handle, Arc::clone(&channel));
    channel
}

pub(crate) fn find(handle: i64) -> Option<Arc<Channel>> {
    lock(&CHANNELS).get(&handle).cloned()
}

fn forget(handle: i64) {
    lock(&CHANNELS).remove(&handle);
}

/// The one way out of the module for the events of one channel.
///
/// Sent under a lock of their own, so they leave in the order the channel made
/// them whichever thread makes the next one, and so nothing can follow CLOSED.
/// The callback only posts to the isolate (`NativeCallable.listener`) and
/// never calls back in before it returns, so holding the lock across it cannot
/// deadlock.
pub(crate) struct Events {
    handle: i64,
    callback: EventFn,
    closed: Mutex<bool>,
}

impl Events {
    pub(crate) fn new(handle: i64, callback: EventFn) -> Self {
        Events { handle, callback, closed: Mutex::new(false) }
    }

    /// `data` leaves as a heap buffer Dart frees with `nox_chan_buf_free`. An
    /// event after CLOSED is not sent, and its buffer is freed here instead.
    fn send(&self, kind: i32, data: Option<Box<[u8]>>, code: i32) {
        let mut closed = lock(&self.closed);
        if *closed {
            return;
        }
        *closed = kind == event::CLOSED;
        let (ptr, len) = match data {
            Some(bytes) => {
                let len = bytes.len();
                (Box::into_raw(bytes) as *const u8, len)
            }
            None => (std::ptr::null(), 0),
        };
        (self.callback)(self.handle, kind, ptr, len, code);
    }

    /// The channel is verified; `key` is the server's, which Eidolon checked.
    pub(crate) fn open(&self, key: &[u8; 32]) {
        self.send(event::OPEN, Some(Box::new(*key)), code::NONE);
    }

    pub(crate) fn data(&self, bytes: &[u8]) {
        self.send(event::DATA, Some(bytes.into()), code::NONE);
    }

    pub(crate) fn writable(&self) {
        self.send(event::WRITABLE, None, code::NONE);
    }

    pub(crate) fn drained(&self, ticket: i32) {
        self.send(event::DRAINED, None, ticket);
    }

    pub(crate) fn eof(&self) {
        self.send(event::EOF, None, code::NONE);
    }

    fn closed(&self, code: i32) {
        self.send(event::CLOSED, None, code);
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
    use super::*;

    type Seen = (i32, Vec<u8>, i32);

    static SEEN: Mutex<Vec<(i64, Seen)>> = Mutex::new(Vec::new());

    /// Records every event the way Dart takes it: copies the buffer, frees it.
    pub(crate) extern "C" fn record(handle: i64, kind: i32, data: *const u8, len: usize, code: i32) {
        let bytes = if data.is_null() { Vec::new() } else { unsafe { std::slice::from_raw_parts(data, len) }.to_vec() };
        unsafe { super::super::free_buffer(data as *mut u8, len) };
        lock(&SEEN).push((handle, (kind, bytes, code)));
    }

    pub(crate) fn seen(handle: i64) -> Vec<Seen> {
        lock(&SEEN).iter().filter(|(h, _)| *h == handle).map(|(_, e)| e.clone()).collect()
    }

    #[test]
    fn handles_are_positive_and_never_come_back() {
        let first = register(record);
        let second = register(record);
        assert!(first.handle > 0 && second.handle > first.handle);
        Closer::new(Arc::clone(&first), code::NONE).finish(code::NONE);
        let third = register(record);
        assert!(third.handle > second.handle, "{} came back", first.handle);
        for channel in [second, third] {
            Closer::new(channel, code::NONE).finish(code::NONE);
        }
    }

    #[test]
    fn nothing_follows_closed_and_closed_goes_once() {
        let channel = register(record);
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
        let channel = register(record);
        let handle = channel.handle;
        assert!(find(handle).is_some());
        Closer::new(channel, code::NONE).finish(code::NONE);
        assert!(find(handle).is_none());
    }

    #[test]
    fn a_closer_dropped_unfinished_still_closes() {
        let channel = register(record);
        let handle = channel.handle;
        let closer = Closer::new(channel, code::TOR_NOT_READY);
        drop(closer);
        assert_eq!(seen(handle), [(event::CLOSED, Vec::new(), code::TOR_NOT_READY)]);
        assert!(find(handle).is_none());

        // Once the app asked for the end, the end is a normal one.
        let channel = register(record);
        let handle = channel.handle;
        let closer = Closer::new(Arc::clone(&channel), code::NETWORK);
        channel.request_close();
        drop(closer);
        assert_eq!(seen(handle), [(event::CLOSED, Vec::new(), code::NONE)]);
    }

    #[test]
    fn a_panic_in_the_driver_closes_as_internal() {
        let channel = register(record);
        let handle = channel.handle;
        let closer = Closer::new(channel, code::NETWORK);
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(move || {
            let _owned = closer;
            panic!("a bug in the driver");
        }));
        assert_eq!(seen(handle), [(event::CLOSED, Vec::new(), code::INTERNAL)]);
    }
}
