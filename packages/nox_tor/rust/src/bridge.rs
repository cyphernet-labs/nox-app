//! The loopback bridge the app dials instead of the onion service.
//!
//! The app does TLS and checks the server's fingerprint itself, exactly as on
//! the direct path; this bridge only moves bytes between a loopback socket and
//! a Tor stream to the one target the app set. Every connection must open with
//! the 32-byte secret of this bridge: any app on the device can dial
//! 127.0.0.1, and without the secret it could ride this client - and its
//! access key - to the person's server.

use std::collections::VecDeque;
use std::future::Future;
use std::io;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use arti_client::{IsolationToken, StreamPrefs};
use subtle::ConstantTimeEq;
use tokio::io::AsyncReadExt;
use tokio::net::{TcpListener, TcpStream};
use tokio::runtime::Runtime;
use tokio::sync::oneshot;
use tokio::task::JoinHandle;

use crate::engine::{lock, Shared};
use crate::status::{classify, error};

/// How long a fresh loopback connection may take to present the secret.
const SECRET_WAIT: Duration = Duration::from_secs(5);
/// How many connections may be waiting to present the secret at once. Anyone
/// on the device can dial, and each of these holds a socket for SECRET_WAIT:
/// unbounded, a stranger could fill the process's descriptor table and starve
/// Arti, the app's own sockets and its files.
const PENDING_CAP: usize = 16;
/// The pause after an accept that failed for more than the connection it was
/// taking. A full descriptor table fails again at once, and an immediate retry
/// would spin a worker until it cleared.
const ACCEPT_BACKOFF: Duration = Duration::from_millis(100);
/// How many accepts in a row may fail over the connection each was taking
/// before the loop pauses anyway: a failure that keeps coming is about the
/// listener, not about one connection.
const GONE_IN_A_ROW: u32 = 8;
/// One Tor connection to the onion service, both attempts of the hedge
/// together. A keyed connect fetches the descriptor anew every time and
/// sometimes hangs (Arti #2166, #2482): this is the bound, and the app's
/// reconnect ladder is the retry.
const CONNECT_BUDGET: Duration = Duration::from_secs(45);
/// When a connect to the onion service that has not finished gets a second
/// one beside it. One that hangs hangs for the whole CONNECT_BUDGET, while a
/// fresh attempt usually gets through in a few seconds.
const HEDGE_AFTER: Duration = Duration::from_secs(15);

pub struct BridgeHandle {
    task: JoinHandle<()>,
    /// The socket itself. The accept loop works on a handle of its own, so the
    /// port stays bound when the loop's runtime goes away (see `move_to`).
    listener: std::net::TcpListener,
    pub port: u16,
    pub secret: Arc<Mutex<[u8; 32]>>,
}

impl BridgeHandle {
    /// Serves this bridge from another runtime: same socket, port and secret,
    /// which the app already holds. How a failed client is rebuilt on a new
    /// runtime without the app's endpoint going stale.
    pub(crate) fn move_to(&mut self, runtime: &Runtime, shared: &Arc<Shared>) -> Result<(), ()> {
        let task = spawn_serve(&self.listener, runtime, shared, &self.secret)?;
        std::mem::replace(&mut self.task, task).abort();
        Ok(())
    }
}

impl Drop for BridgeHandle {
    fn drop(&mut self) {
        self.task.abort();
    }
}

pub fn random_secret() -> Result<[u8; 32], ()> {
    let mut secret = [0u8; 32];
    getrandom::fill(&mut secret).map_err(|_| ())?;
    Ok(secret)
}

/// Opens the bridge, or gives the open one a new secret. Returns the port.
pub fn open_or_rotate(runtime: &Runtime, shared: &Arc<Shared>) -> Result<u16, ()> {
    let secret = random_secret()?;
    let mut bridge = lock(&shared.bridge);
    if let Some(open) = bridge.as_ref() {
        *lock(&open.secret) = secret;
        return Ok(open.port);
    }
    let listener = std::net::TcpListener::bind(("127.0.0.1", 0)).map_err(|_| ())?;
    let port = listener.local_addr().map_err(|_| ())?.port();
    let secret = Arc::new(Mutex::new(secret));
    let task = spawn_serve(&listener, runtime, shared, &secret)?;
    *bridge = Some(BridgeHandle { task, listener, port, secret });
    Ok(port)
}

/// Starts the accept loop on `runtime`, on a handle of its own to `listener`.
fn spawn_serve(
    listener: &std::net::TcpListener,
    runtime: &Runtime,
    shared: &Arc<Shared>,
    secret: &Arc<Mutex<[u8; 32]>>,
) -> Result<JoinHandle<()>, ()> {
    let handle = listener.try_clone().map_err(|_| ())?;
    // tokio needs it; set on the handle it gets rather than trusted to carry
    // over from the original on every platform.
    handle.set_nonblocking(true).map_err(|_| ())?;
    Ok(runtime.spawn(serve(handle, Arc::clone(shared), Arc::clone(secret))))
}

async fn serve(listener: std::net::TcpListener, shared: Arc<Shared>, secret: Arc<Mutex<[u8; 32]>>) {
    let listener = match TcpListener::from_std(listener) {
        Ok(l) => l,
        Err(_) => {
            shared.status.update(|s| s.error = error::INTERNAL);
            return;
        }
    };
    // The connections still waiting to present the secret, oldest first.
    // Dropping a sender lets that connection go (see relay).
    let mut waiting: VecDeque<oneshot::Sender<()>> = VecDeque::new();
    let mut gone_in_a_row = 0;
    loop {
        let socket = match listener.accept().await {
            Ok((socket, _)) => {
                gone_in_a_row = 0;
                socket
            }
            Err(e) => {
                if pause_after(&e, &mut gone_in_a_row) {
                    tokio::time::sleep(ACCEPT_BACKOFF).await;
                }
                continue;
            }
        };
        waiting.retain(|w| !w.is_closed());
        if waiting.len() >= PENDING_CAP {
            // The oldest goes, not the newcomer: the app writes the secret the
            // moment it connects, so places merely held do not keep it out. A
            // sustained flood of fresh connections still can - see the bridge
            // in contracts/ffi.md.
            waiting.pop_front();
        }
        let (evict, evicted) = oneshot::channel();
        waiting.push_back(evict);
        let expected = *lock(&secret);
        let shared = Arc::clone(&shared);
        tokio::spawn(async move {
            let _ = relay(socket, shared, expected, evicted).await;
        });
    }
}

/// An accept that failed over the one connection it was taking - gone before
/// it was taken - says nothing about the next one.
fn gone_before_taken(e: &io::Error) -> bool {
    matches!(
        e.kind(),
        io::ErrorKind::ConnectionAborted | io::ErrorKind::ConnectionReset | io::ErrorKind::ConnectionRefused
    )
}

/// Whether the accept loop pauses after this failure. Any failure beyond one
/// connection does at once; one over a single connection only when it keeps
/// coming, GONE_IN_A_ROW times in a row, and then the count starts again.
fn pause_after(e: &io::Error, gone_in_a_row: &mut u32) -> bool {
    if !gone_before_taken(e) {
        return true;
    }
    *gone_in_a_row += 1;
    if *gone_in_a_row < GONE_IN_A_ROW {
        return false;
    }
    *gone_in_a_row = 0;
    true
}

/// Reads and checks the secret. Constant-time, so a stranger learns nothing
/// from how fast a wrong guess is turned away.
pub async fn read_secret(socket: &mut TcpStream, expected: &[u8; 32]) -> Result<(), ()> {
    let mut presented = [0u8; 32];
    match tokio::time::timeout(SECRET_WAIT, socket.read_exact(&mut presented)).await {
        Ok(Ok(_)) if bool::from(presented.ct_eq(expected)) => Ok(()),
        _ => Err(()),
    }
}

async fn relay(
    mut socket: TcpStream,
    shared: Arc<Shared>,
    expected: [u8; 32],
    evicted: oneshot::Receiver<()>,
) -> Result<(), ()> {
    tokio::select! {
        presented = read_secret(&mut socket, &expected) => presented?,
        // Pushed out by newer connections while still waiting.
        _ = evicted => return Err(()),
    }
    // Where to go, and nothing more: the key stays with the client.
    let (host, port) = {
        let slot = lock(&shared.target);
        let target = slot.as_ref().ok_or(())?;
        (target.host.clone(), target.port)
    };
    let tor = lock(&shared.client).clone().ok_or(())?;
    let (client, target) = (&*tor, (host.as_str(), port));
    let connect = connect_in_groups(
        &shared.connect_group,
        move |group| async move {
            let prefs = prefs_in(group);
            client.connect_with_prefs(target, &prefs).await
        },
        HEDGE_AFTER,
    );
    let mut stream = match tokio::time::timeout(CONNECT_BUDGET, connect).await {
        Ok(Ok(stream)) => stream,
        Ok(Err(e)) => {
            let code = classify(&e);
            shared.status.update(|s| s.error = code);
            return Err(());
        }
        Err(_) => {
            shared.status.update(|s| s.error = error::TIMEOUT);
            return Err(());
        }
    };
    shared.status.update(|s| s.error = error::NONE);
    let _ = tokio::io::copy_bidirectional(&mut socket, &mut stream).await;
    Ok(())
}

/// The isolation group connects to the onion service go in: Arti's default
/// until a hedge is won in a fresh group, and that group from then on.
///
/// Arti lets connects to an onion service share an attempt only when their
/// isolation is compatible, and an attempt that hangs runs on in a task of its
/// own after its connect gives up on it. A later connect in the same group would
/// join it and wait for the hedge all over again. Isolation decides only which
/// circuits to this one service are shared, so a new group costs nothing in
/// privacy. Forgotten when the target changes (see engine).
#[derive(Default)]
pub struct ConnectGroup(Mutex<Option<IsolationToken>>);

impl ConnectGroup {
    /// The group a first attempt goes in: the one the last hedge was won in.
    pub(crate) fn current(&self) -> Option<IsolationToken> {
        *lock(&self.0)
    }

    /// A hedge won in `group`: later connects go there.
    pub(crate) fn won(&self, group: IsolationToken) {
        *lock(&self.0) = Some(group);
    }

    /// Back to Arti's default.
    pub(crate) fn forget(&self) {
        *lock(&self.0) = None;
    }
}

/// The preferences of a connect in `group`, Arti's default without one.
fn prefs_in(group: Option<IsolationToken>) -> StreamPrefs {
    let mut prefs = StreamPrefs::new();
    if let Some(group) = group {
        prefs.set_isolation(group);
    }
    prefs
}

/// One connect, hedged: the first attempt in the current group, the hedge in a
/// fresh one - it starts afresh, descriptor, introduction and rendezvous,
/// instead of waiting on the attempt that hangs - and once that one wins, its
/// group is current.
async fn connect_in_groups<T, E, C, F>(group: &ConnectGroup, connect: C, after: Duration) -> Result<T, E>
where
    C: Fn(Option<IsolationToken>) -> F,
    F: Future<Output = Result<T, E>>,
{
    let connect = &connect;
    let current = group.current();
    let first = async move { connect(current).await.map(|won| (won, None)) };
    let second = move || async move {
        let fresh = IsolationToken::new();
        connect(Some(fresh)).await.map(|won| (won, Some(fresh)))
    };
    let (won, fresh) = hedged(first, second, after).await?;
    if let Some(fresh) = fresh {
        group.won(fresh);
    }
    Ok(won)
}

/// Runs `first`, and if it has not settled after `after`, `second()` beside it.
///
/// The first success wins. A failure of one waits for the other, and when both
/// fail the later failure is the answer. Whatever `first` settles to before
/// `after` is the answer at once, and `second` is never made: a failure that
/// early is not a hang, and the app's reconnect ladder is the retry.
async fn hedged<T, E, F1, F2>(first: F1, second: impl FnOnce() -> F2, after: Duration) -> Result<T, E>
where
    F1: Future<Output = Result<T, E>>,
    F2: Future<Output = Result<T, E>>,
{
    tokio::pin!(first);
    if let Ok(settled) = tokio::time::timeout(after, &mut first).await {
        return settled;
    }
    let second = second();
    tokio::pin!(second);
    tokio::select! {
        settled = &mut first => match settled {
            Ok(won) => Ok(won),
            Err(_) => second.await,
        },
        settled = &mut second => match settled {
            Ok(won) => Ok(won),
            Err(_) => first.await,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::AsyncWriteExt;

    async fn pair() -> (TcpStream, TcpStream) {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let client = TcpStream::connect(addr).await.unwrap();
        let (server, _) = listener.accept().await.unwrap();
        (client, server)
    }

    #[tokio::test]
    async fn the_right_secret_passes() {
        let secret = [7u8; 32];
        let (mut client, mut server) = pair().await;
        client.write_all(&secret).await.unwrap();
        assert!(read_secret(&mut server, &secret).await.is_ok());
    }

    #[tokio::test]
    async fn a_wrong_secret_is_refused() {
        let secret = [7u8; 32];
        let (mut client, mut server) = pair().await;
        let mut wrong = secret;
        wrong[31] ^= 1;
        client.write_all(&wrong).await.unwrap();
        assert!(read_secret(&mut server, &secret).await.is_err());
    }

    #[tokio::test]
    async fn a_short_secret_is_refused() {
        let secret = [7u8; 32];
        let (mut client, mut server) = pair().await;
        client.write_all(&secret[..16]).await.unwrap();
        drop(client);
        assert!(read_secret(&mut server, &secret).await.is_err());
    }

    #[test]
    fn secrets_are_random() {
        assert_ne!(random_secret().unwrap(), random_secret().unwrap());
    }

    #[tokio::test]
    async fn over_the_cap_the_oldest_waiting_connection_goes() {
        let listener = std::net::TcpListener::bind(("127.0.0.1", 0)).unwrap();
        listener.set_nonblocking(true).unwrap();
        let addr = listener.local_addr().unwrap();
        let serving = tokio::spawn(serve(listener, Arc::new(Shared::default()), Arc::new(Mutex::new([7u8; 32]))));
        // One more than the cap, and none of them presents the secret.
        let mut waiting = Vec::new();
        for _ in 0..=PENDING_CAP {
            waiting.push(TcpStream::connect(addr).await.unwrap());
        }
        let mut byte = [0u8; 1];
        let oldest = tokio::time::timeout(Duration::from_secs(2), waiting[0].read(&mut byte)).await;
        assert!(matches!(oldest, Ok(Ok(0)) | Ok(Err(_))), "the oldest is still waiting: {oldest:?}");
        for kept in [1, PENDING_CAP] {
            let read = tokio::time::timeout(Duration::from_millis(200), waiting[kept].read(&mut byte)).await;
            assert!(read.is_err(), "connection {kept} was let go: {read:?}");
        }
        serving.abort();
    }

    mod hedge {
        use super::super::{connect_in_groups, hedged, prefs_in, ConnectGroup, HEDGE_AFTER};
        use arti_client::{IsolationToken, StreamPrefs};
        use std::cell::{Cell, RefCell};
        use std::time::Duration;
        use tokio::time::Instant;

        type Outcome = Result<&'static str, &'static str>;

        fn secs(n: u64) -> Duration {
            Duration::from_secs(n)
        }

        /// A connect that settles `after` from when it is made.
        async fn settles(after: Duration, outcome: Outcome) -> Outcome {
            tokio::time::sleep(after).await;
            outcome
        }

        /// The clock is paused and moves only to the next timer, so a time
        /// read is exact up to the timer's millisecond.
        fn at(start: Instant, expected: Duration) {
            let elapsed = start.elapsed();
            assert!(elapsed >= expected && elapsed < expected + Duration::from_millis(10), "settled at {elapsed:?}");
        }

        #[tokio::test(start_paused = true)]
        async fn a_first_in_time_wins_and_no_second_is_made() {
            let (start, made) = (Instant::now(), Cell::new(false));
            let got = hedged(
                settles(secs(3), Ok("first")),
                || {
                    made.set(true);
                    settles(secs(1), Ok("second"))
                },
                HEDGE_AFTER,
            )
            .await;
            assert_eq!(got, Ok("first"));
            assert!(!made.get());
            at(start, secs(3));
        }

        #[tokio::test(start_paused = true)]
        async fn a_first_that_hangs_is_overtaken_by_the_second() {
            let start = Instant::now();
            let hedge = hedged(std::future::pending::<Outcome>(), || settles(secs(4), Ok("second")), HEDGE_AFTER);
            // Bounded, so a hedge that never comes fails here instead of hanging.
            let got = tokio::time::timeout(secs(60), hedge).await.expect("the hang was never overtaken");
            assert_eq!(got, Ok("second"));
            at(start, HEDGE_AFTER + secs(4));
        }

        #[tokio::test(start_paused = true)]
        async fn a_first_that_fails_early_is_the_answer_and_no_second_is_made() {
            let (start, made) = (Instant::now(), Cell::new(false));
            let got = hedged(
                settles(secs(2), Err("first")),
                || {
                    made.set(true);
                    settles(secs(1), Ok("second"))
                },
                HEDGE_AFTER,
            )
            .await;
            assert_eq!(got, Err("first"));
            assert!(!made.get());
            at(start, secs(2));
        }

        #[tokio::test(start_paused = true)]
        async fn a_second_that_fails_waits_for_the_first() {
            let start = Instant::now();
            let got = hedged(settles(secs(20), Ok("first")), || settles(secs(1), Err("second")), HEDGE_AFTER).await;
            assert_eq!(got, Ok("first"));
            at(start, secs(20));
        }

        #[tokio::test(start_paused = true)]
        async fn when_both_fail_the_later_failure_is_the_answer() {
            let start = Instant::now();
            let got = hedged(settles(secs(20), Err("first")), || settles(secs(10), Err("second")), HEDGE_AFTER).await;
            assert_eq!(got, Err("second"), "the second failed at 25 s, after the first at 20 s");
            at(start, HEDGE_AFTER + secs(10));

            let start = Instant::now();
            let got = hedged(settles(secs(30), Err("first")), || settles(secs(1), Err("second")), HEDGE_AFTER).await;
            assert_eq!(got, Err("first"), "the first failed at 30 s, after the second at 16 s");
            at(start, secs(30));
        }

        #[test]
        fn a_group_goes_into_the_prefs_and_none_leaves_the_default() {
            let group = IsolationToken::new();
            // The isolation of StreamPrefs is private; its Debug shows it.
            assert_eq!(format!("{:?}", prefs_in(None)), format!("{:?}", StreamPrefs::new()));
            assert!(format!("{:?}", prefs_in(Some(group))).contains(&format!("{group:?}")));
        }

        /// A connect in `group`, recorded: one group hangs, the others connect
        /// in two seconds.
        async fn one_hangs(group: Option<IsolationToken>, hung: Option<IsolationToken>) -> Outcome {
            if group == hung {
                std::future::pending::<()>().await;
            }
            settles(secs(2), Ok("connected")).await
        }

        #[tokio::test(start_paused = true)]
        async fn a_won_hedge_takes_the_next_connect_past_the_hung_attempt() {
            let (group, made) = (ConnectGroup::default(), RefCell::new(Vec::new()));
            let connect = |g| {
                made.borrow_mut().push(g);
                one_hangs(g, None)
            };
            let start = Instant::now();
            assert_eq!(connect_in_groups(&group, connect, HEDGE_AFTER).await, Ok("connected"));
            at(start, HEDGE_AFTER + secs(2));
            let won = group.current().expect("the group the hedge won in is current");
            assert_eq!(*made.borrow(), [None, Some(won)]);

            // The next connect goes straight to the group that works.
            let start = Instant::now();
            assert_eq!(connect_in_groups(&group, connect, HEDGE_AFTER).await, Ok("connected"));
            at(start, secs(2));
            assert_eq!(*made.borrow(), [None, Some(won), Some(won)]);
            assert_eq!(group.current(), Some(won));
        }

        #[tokio::test(start_paused = true)]
        async fn a_current_group_that_hangs_gives_way_to_the_next_winner() {
            let group = ConnectGroup::default();
            let hung = IsolationToken::new();
            group.won(hung);
            let got = connect_in_groups(&group, |g| one_hangs(g, Some(hung)), HEDGE_AFTER).await;
            assert_eq!(got, Ok("connected"));
            assert!(group.current().is_some_and(|now| now != hung), "still {:?}", group.current());
        }

        #[tokio::test(start_paused = true)]
        async fn a_first_attempt_that_wins_leaves_the_group_as_it_was() {
            let (group, made) = (ConnectGroup::default(), RefCell::new(Vec::new()));
            let quick = |g| {
                made.borrow_mut().push(g);
                settles(secs(1), Ok("connected"))
            };
            assert_eq!(connect_in_groups(&group, quick, HEDGE_AFTER).await, Ok("connected"));
            assert_eq!(group.current(), None);
            let stored = IsolationToken::new();
            group.won(stored);
            assert_eq!(connect_in_groups(&group, quick, HEDGE_AFTER).await, Ok("connected"));
            assert_eq!(group.current(), Some(stored));
            assert_eq!(*made.borrow(), [None, Some(stored)], "no fresh group without a hedge");

            // Won by the first after the hedge was made: still the first's group.
            let slow_first = |g| settles(if g == Some(stored) { secs(20) } else { secs(30) }, Ok("connected"));
            assert_eq!(connect_in_groups(&group, slow_first, HEDGE_AFTER).await, Ok("connected"));
            assert_eq!(group.current(), Some(stored));
        }

        #[tokio::test(start_paused = true)]
        async fn when_both_fail_the_group_stays() {
            let group = ConnectGroup::default();
            let stored = IsolationToken::new();
            group.won(stored);
            let refused = |g| settles(if g == Some(stored) { secs(20) } else { secs(1) }, Err("refused"));
            assert_eq!(connect_in_groups(&group, refused, HEDGE_AFTER).await, Err("refused"));
            assert_eq!(group.current(), Some(stored));
        }
    }

    #[test]
    fn an_accept_failure_that_keeps_coming_pauses_the_loop() {
        let gone = io::Error::from(io::ErrorKind::ConnectionAborted);
        let mut in_a_row = 0;
        for _ in 1..GONE_IN_A_ROW {
            assert!(!pause_after(&gone, &mut in_a_row), "one connection gone says nothing about the next");
        }
        assert!(pause_after(&gone, &mut in_a_row), "this many in a row is about the listener");
        assert!(!pause_after(&gone, &mut in_a_row), "and the count starts again after the pause");
        let other = io::Error::other("too many open files");
        assert!(pause_after(&other, &mut 0), "a failure beyond one connection pauses at once");
    }
}
