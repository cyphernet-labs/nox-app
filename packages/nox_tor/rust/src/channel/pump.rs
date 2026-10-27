//! Moving bytes once a channel is open, under a window each way.
//!
//! Inbound, the module holds at most WINDOW bytes Dart has not acknowledged: it
//! stops reading TLS at the window and reads again on `nox_chan_ack`, so a
//! listener that pauses its stream pauses the server as well. Outbound, a write
//! is copied into a queue the writer drains into TLS; once a write left more
//! than WINDOW queued, Dart pauses its source until WRITABLE, sent as soon as
//! the queue is back within the window. Without the two, a large file would
//! pile up in the memory of whichever side cannot keep up.
//!
//! WRITABLE comes back after about one chunk drained, not after half the
//! window: what Dart writes next is what moves an upload's progress, and the
//! app ends a transfer whose progress stands still for 45 s. Held to half a
//! window, a path draining at 11 KiB/s - Tor on a bad day - would read as dead.
//!
//! Both loops run in the channel's one driver task, so a channel's events come
//! from one place at a time.

use std::collections::VecDeque;
use std::io;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::sync::Notify;

use super::{code, Channel, CHUNK, WINDOW};
use crate::engine::lock;

/// The state the C ABI and the driver share.
#[derive(Default)]
pub(crate) struct Pump {
    /// Bytes sent to Dart in DATA events and not acknowledged yet.
    unacked: Mutex<usize>,
    /// An acknowledgement made room.
    room: Notify,
    outbound: Mutex<Outbound>,
    /// Something for the writer: bytes, a flush ticket, the shutdown.
    work: Notify,
    /// The peer has closed its side.
    eof: AtomicBool,
}

#[derive(Default)]
struct Outbound {
    queue: VecDeque<Vec<u8>>,
    /// Bytes queued and not yet taken by TLS: what `nox_chan_write` returns.
    queued: usize,
    /// Running totals since the channel opened.
    enqueued: u64,
    written: u64,
    flushed: u64,
    /// Flush tickets, each with the total enqueued when it was asked for.
    tickets: VecDeque<(u64, i32)>,
    /// A write returned more than the window, and WRITABLE has not been sent.
    writable_owed: bool,
    shutdown: Shutdown,
}

#[derive(Default, Clone, Copy, PartialEq, Eq, Debug)]
enum Shutdown {
    #[default]
    Open,
    Asked,
    Done,
}

/// What `nox_chan_flush` leaves to do.
#[derive(Debug, PartialEq, Eq)]
pub(crate) enum Flush {
    /// The writer answers once it gets there.
    Queued,
    /// Answer now: the write side is shut, and all of it was flushed.
    Now,
}

/// The writer's next step, decided under the queue's lock.
#[derive(Debug, PartialEq, Eq)]
enum Job {
    Write(Vec<u8>),
    Flush,
    Drained(Vec<i32>),
    Shutdown,
    Wait,
}

impl Pump {
    /// Queues a copy of `bytes`; returns the queued size after it. A write after
    /// `nox_chan_shutdown_write` finds no write side.
    pub(crate) fn write(&self, bytes: &[u8]) -> i64 {
        let queued = {
            let mut out = lock(&self.outbound);
            if out.shutdown != Shutdown::Open {
                return i64::from(code::RET_CLOSED);
            }
            if !bytes.is_empty() {
                out.queue.push_back(bytes.to_vec());
                out.queued += bytes.len();
                out.enqueued += bytes.len() as u64;
                if out.queued > WINDOW {
                    out.writable_owed = true;
                }
            }
            out.queued
        };
        if !bytes.is_empty() {
            self.work.notify_one();
        }
        i64::try_from(queued).unwrap_or(i64::MAX)
    }

    /// Dart passed `len` more bytes on. More than were sent is a bug on its side.
    pub(crate) fn ack(&self, len: usize) -> i32 {
        {
            let mut unacked = lock(&self.unacked);
            if len > *unacked {
                return code::RET_INVALID_ARGUMENT;
            }
            *unacked -= len;
        }
        if len > 0 {
            self.room.notify_one();
        }
        code::NONE
    }

    pub(crate) fn flush(&self, ticket: i32) -> Flush {
        let mut out = lock(&self.outbound);
        if out.shutdown == Shutdown::Done {
            return Flush::Now;
        }
        let at = out.enqueued;
        out.tickets.push_back((at, ticket));
        drop(out);
        self.work.notify_one();
        Flush::Queued
    }

    /// TLS close_notify once the queue is out; reading goes on. Asking twice is
    /// asking once.
    pub(crate) fn shutdown_write(&self) -> i32 {
        let mut out = lock(&self.outbound);
        if out.shutdown == Shutdown::Open {
            out.shutdown = Shutdown::Asked;
            drop(out);
            self.work.notify_one();
        }
        code::NONE
    }

    /// How much the reader may take now, waiting for an ack while the window is
    /// full.
    async fn room(&self) -> usize {
        loop {
            let unacked = *lock(&self.unacked);
            if unacked < WINDOW {
                return (WINDOW - unacked).min(CHUNK);
            }
            self.room.notified().await;
        }
    }

    /// Counted before the DATA event goes, so an ack can never come first.
    fn delivered(&self, len: usize) {
        *lock(&self.unacked) += len;
    }

    fn next_job(&self) -> Job {
        let mut out = lock(&self.outbound);
        if let Some(bytes) = out.queue.pop_front() {
            return Job::Write(bytes);
        }
        // Idle: whatever TLS or the Tor stream still buffers goes out now, or a
        // last partial record or cell would wait for the next write.
        if out.written > out.flushed {
            return Job::Flush;
        }
        if !out.tickets.is_empty() {
            // Nothing is left unwritten or unflushed: every ticket is answered.
            return Job::Drained(out.tickets.drain(..).map(|(_, ticket)| ticket).collect());
        }
        if out.shutdown == Shutdown::Asked {
            return Job::Shutdown;
        }
        Job::Wait
    }

    /// TLS took `len` more bytes. True when that owes Dart its WRITABLE.
    fn wrote(&self, len: usize) -> bool {
        let mut out = lock(&self.outbound);
        out.queued -= len;
        out.written += len as u64;
        if out.writable_owed && out.queued <= WINDOW {
            out.writable_owed = false;
            return true;
        }
        false
    }

    /// A ticket waits for bytes the writer has now written: flush before the
    /// next write rather than when the queue happens to run dry.
    fn flush_due(&self) -> bool {
        let out = lock(&self.outbound);
        out.tickets.front().is_some_and(|&(at, _)| at <= out.written)
    }

    /// Everything written is flushed; the tickets this answers, in order.
    fn flushed(&self) -> Vec<i32> {
        let mut out = lock(&self.outbound);
        out.flushed = out.written;
        let flushed = out.flushed;
        let mut answered = Vec::new();
        while let Some(&(at, ticket)) = out.tickets.front() {
            if at > flushed {
                break;
            }
            out.tickets.pop_front();
            answered.push(ticket);
        }
        answered
    }

    /// close_notify is out. Any ticket asked meanwhile is answered with it: no
    /// write was taken after the shutdown was.
    fn shut(&self) -> Vec<i32> {
        let mut out = lock(&self.outbound);
        out.shutdown = Shutdown::Done;
        out.flushed = out.written;
        out.tickets.drain(..).map(|(_, ticket)| ticket).collect()
    }
}

/// From TLS to Dart until the peer closes its side.
pub(crate) async fn read<R: AsyncRead + Unpin>(channel: &Channel, mut reader: R) -> Result<(), i32> {
    let pump = &channel.pump;
    let mut buf = vec![0u8; CHUNK];
    loop {
        let room = pump.room().await;
        match reader.read(&mut buf[..room]).await {
            Ok(0) => break,
            Ok(n) => {
                pump.delivered(n);
                channel.events.data(&buf[..n]);
            }
            // The peer's FIN without its close_notify. The contract counts it as
            // the end of the stream too: what runs over the channel - HTTP and
            // WebSocket - frames its own messages and sees a cut one.
            Err(e) if e.kind() == io::ErrorKind::UnexpectedEof => break,
            Err(_) => return Err(code::NETWORK),
        }
    }
    pump.eof.store(true, Ordering::SeqCst);
    channel.events.eof();
    Ok(())
}

/// From the queue to TLS until the write side is shut.
pub(crate) async fn write<W: AsyncWrite + Unpin>(channel: &Channel, mut writer: W) -> Result<(), i32> {
    let pump = &channel.pump;
    loop {
        match pump.next_job() {
            Job::Write(bytes) => {
                // A chunk at a time, so the queued size - and WRITABLE - follow
                // the network rather than one large write.
                for chunk in bytes.chunks(CHUNK) {
                    let mut at = 0;
                    while at < chunk.len() {
                        let n = writer.write(&chunk[at..]).await.map_err(|_| code::NETWORK)?;
                        if n == 0 {
                            return Err(code::NETWORK);
                        }
                        at += n;
                        if pump.wrote(n) {
                            channel.events.writable();
                        }
                    }
                }
                if pump.flush_due() {
                    flush(channel, &mut writer).await?;
                }
            }
            Job::Flush => flush(channel, &mut writer).await?,
            Job::Drained(tickets) => {
                for ticket in tickets {
                    channel.events.drained(ticket);
                }
            }
            Job::Shutdown => {
                match writer.shutdown().await {
                    Ok(()) => {}
                    // The peer had closed its side and then the connection: the
                    // conversation is over from both ends, and only the
                    // close_notify found no one.
                    Err(_) if pump.eof.load(Ordering::SeqCst) => {}
                    Err(_) => return Err(code::NETWORK),
                }
                for ticket in pump.shut() {
                    channel.events.drained(ticket);
                }
                return Ok(());
            }
            Job::Wait => pump.work.notified().await,
        }
    }
}

async fn flush<W: AsyncWrite + Unpin>(channel: &Channel, writer: &mut W) -> Result<(), i32> {
    writer.flush().await.map_err(|_| code::NETWORK)?;
    for ticket in channel.pump.flushed() {
        channel.events.drained(ticket);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_write_returns_what_is_queued_and_owes_writable_past_the_window() {
        let pump = Pump::default();
        assert_eq!(pump.write(&[1u8; 1000]), 1000);
        assert_eq!(pump.write(&[]), 1000, "an empty write changes nothing");
        assert!(!lock(&pump.outbound).writable_owed);
        assert_eq!(pump.write(&vec![2u8; WINDOW]), (WINDOW + 1000) as i64);
        assert!(lock(&pump.outbound).writable_owed);

        // Down to just above the window: not yet.
        assert!(!pump.wrote(999));
        // Back within it: once, and only once - a chunk later, not half a
        // window later.
        assert!(pump.wrote(1));
        assert!(!pump.wrote(1));
        assert!(!pump.wrote(WINDOW / 2));

        // Past the window again: owed again.
        assert!(pump.write(&vec![3u8; WINDOW]) > WINDOW as i64);
        assert!(lock(&pump.outbound).writable_owed);
    }

    #[test]
    fn writable_is_owed_only_after_a_write_past_the_window() {
        let pump = Pump::default();
        assert_eq!(pump.write(&vec![0u8; WINDOW]), WINDOW as i64, "at the window, not past it");
        assert!(!pump.wrote(WINDOW));
    }

    #[test]
    fn an_ack_frees_room_and_more_than_was_sent_is_refused() {
        let pump = Pump::default();
        pump.delivered(WINDOW);
        assert_eq!(pump.ack(WINDOW + 1), code::RET_INVALID_ARGUMENT);
        assert_eq!(*lock(&pump.unacked), WINDOW, "a refused ack takes nothing");
        assert_eq!(pump.ack(10), code::NONE);
        assert_eq!(*lock(&pump.unacked), WINDOW - 10);
        assert_eq!(pump.ack(0), code::NONE);
    }

    #[tokio::test(start_paused = true)]
    async fn the_reader_waits_for_room_and_never_takes_more_than_the_window() {
        let pump = Pump::default();
        assert_eq!(pump.room().await, CHUNK);
        pump.delivered(WINDOW - 100);
        assert_eq!(pump.room().await, 100, "the last bytes of the window, no more");
        pump.delivered(100);
        let waiting = tokio::time::timeout(std::time::Duration::from_secs(1), pump.room()).await;
        assert!(waiting.is_err(), "read with the window full");
        assert_eq!(pump.ack(5), code::NONE);
        assert_eq!(pump.room().await, 5);
    }

    #[test]
    fn the_writer_writes_then_flushes_then_answers_then_shuts() {
        let pump = Pump::default();
        assert_eq!(pump.next_job(), Job::Wait);
        pump.write(b"one");
        pump.write(b"two");
        assert_eq!(pump.flush(1), Flush::Queued);
        assert_eq!(pump.shutdown_write(), code::NONE);
        assert_eq!(pump.write(b"late"), i64::from(code::RET_CLOSED), "no write side after the shutdown");

        assert_eq!(pump.next_job(), Job::Write(b"one".to_vec()));
        pump.wrote(3);
        assert!(!pump.flush_due(), "the ticket waits for both writes");
        assert_eq!(pump.next_job(), Job::Write(b"two".to_vec()));
        pump.wrote(3);
        assert!(pump.flush_due());
        assert_eq!(pump.flushed(), [1]);
        assert_eq!(pump.next_job(), Job::Shutdown);
        assert_eq!(pump.shut(), Vec::<i32>::new());
        assert_eq!(pump.flush(2), Flush::Now, "after the shutdown there is nothing left to flush");
    }

    #[test]
    fn an_idle_writer_flushes_what_it_wrote_and_answers_every_ticket() {
        let pump = Pump::default();
        pump.write(b"abc");
        assert_eq!(pump.next_job(), Job::Write(b"abc".to_vec()));
        pump.wrote(3);
        assert_eq!(pump.next_job(), Job::Flush, "written but not flushed");
        assert_eq!(pump.flushed(), Vec::<i32>::new());
        pump.flush(5);
        pump.flush(6);
        assert_eq!(pump.next_job(), Job::Drained(vec![5, 6]), "nothing pending: both at once, in order");
        assert_eq!(pump.next_job(), Job::Wait);
    }

    #[test]
    fn a_ticket_covers_only_what_was_queued_before_it() {
        let pump = Pump::default();
        pump.write(b"first");
        pump.flush(1);
        pump.write(b"second");
        pump.flush(2);
        assert_eq!(pump.next_job(), Job::Write(b"first".to_vec()));
        pump.wrote(5);
        assert!(pump.flush_due());
        assert_eq!(pump.flushed(), [1], "the second ticket waits for its bytes");
        assert_eq!(pump.next_job(), Job::Write(b"second".to_vec()));
        pump.wrote(6);
        assert_eq!(pump.flushed(), [2]);
    }

    #[test]
    fn tickets_asked_while_the_shutdown_runs_are_answered_by_it() {
        let pump = Pump::default();
        pump.shutdown_write();
        assert_eq!(pump.next_job(), Job::Shutdown);
        pump.flush(9);
        assert_eq!(pump.shut(), [9]);
    }
}
