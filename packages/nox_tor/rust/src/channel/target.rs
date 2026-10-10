//! Where a channel goes: TCP to an address, or a Tor stream to the onion
//! service through the client `engine` runs.
//!
//! The onion connect is the one the loopback bridge made until 044, moved
//! here whole: hedged after HEDGE_AFTER in a fresh isolation group, bounded by
//! CONNECT_BUDGET, and its outcome written into the Tor status snapshot as the
//! bridge's was - the channel's own failure goes to its CLOSED event besides.
//! Since 045 it goes by the address alone: the client holds no keys, and no
//! service is set up in it ahead of a connect.

use std::collections::HashMap;
use std::future::Future;
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use arti_client::{DataStream, ErrorKind, HsId, IsolationToken, StreamPrefs};
use futures::stream::{FuturesUnordered, StreamExt};
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::net::TcpStream;
use tokio::runtime::Handle;

use super::code;
use crate::engine::{lock, Client, Shared};
use crate::status::{classify, classify_kind, error};

/// One Tor connection to the onion service, both attempts of the hedge
/// together. A connect sometimes hangs (Arti #2166, #2482): this is the bound,
/// and the app's reconnect ladder is the retry.
pub const CONNECT_BUDGET: Duration = Duration::from_secs(45);
/// When a connect to the onion service that has not finished gets a second
/// one beside it. One that hangs hangs for the whole CONNECT_BUDGET, while a
/// fresh attempt usually gets through in a few seconds.
pub const HEDGE_AFTER: Duration = Duration::from_secs(15);

/// How long an address has before the next one is tried beside it: dart:io's
/// own delay, from the days its sockets made this connect (RFC 8305 calls it
/// the connection attempt delay). One address that swallows its SYNs must not
/// hold the whole budget while the next would answer at once.
pub const ATTEMPT_DELAY: Duration = Duration::from_millis(250);

/// A byte stream TLS can run over: a TCP connection or a Tor stream.
pub trait Transport: AsyncRead + AsyncWrite + Send + Unpin {}

impl<T: AsyncRead + AsyncWrite + Send + Unpin> Transport for T {}

/// What an onion channel needs of the running Tor client: its runtime, which
/// the channel's task runs on, the client, and the state its status lives in.
pub struct OnionContext {
    pub runtime: Handle,
    pub client: Arc<Client>,
    pub shared: Arc<Shared>,
}

/// TCP to `host` - an address or a name - and `port`. Any failure, the name's
/// included, is the network's.
pub async fn direct(host: &str, port: u16) -> Result<TcpStream, i32> {
    // An IPv6 address may come bracketed, as in a URL.
    let host = host.strip_prefix('[').and_then(|h| h.strip_suffix(']')).unwrap_or(host);
    let mut addresses: Vec<SocketAddr> =
        tokio::net::lookup_host((host, port)).await.map_err(|_| code::NETWORK)?.collect();
    // IPv4 first, the resolver's order kept within each family: dart:io's
    // order too, because in practice IPv4 is routed more reliably
    // (dartbug.com/50868).
    addresses.sort_by_key(SocketAddr::is_ipv6);
    let stream = staggered(addresses, TcpStream::connect, ATTEMPT_DELAY).await.ok_or(code::NETWORK)?;
    // The channel carries small frames both ways - commands, acks, the
    // Eidolon messages - and each would otherwise wait on the one before.
    let _ = stream.set_nodelay(true);
    Ok(stream)
}

/// Connects to the first of `addresses` that answers. Each attempt gets
/// `delay` before the next starts beside it, a failure starts the next at once,
/// and the first connection wins: the attempts still running are dropped.
/// None when every one failed.
async fn staggered<A, T, E, C, F>(addresses: Vec<A>, connect: C, delay: Duration) -> Option<T>
where
    C: Fn(A) -> F,
    F: Future<Output = Result<T, E>>,
{
    let mut waiting = addresses.into_iter();
    let mut running = FuturesUnordered::new();
    loop {
        if running.is_empty() {
            running.push(connect(waiting.next()?));
        }
        tokio::select! {
            settled = running.next() => match settled {
                Some(Ok(connected)) => return Some(connected),
                Some(Err(_)) | None => {
                    if let Some(next) = waiting.next() {
                        running.push(connect(next));
                    }
                }
            },
            () = tokio::time::sleep(delay), if waiting.len() > 0 => {
                if let Some(next) = waiting.next() {
                    running.push(connect(next));
                }
            }
        }
    }
}

pub fn parse_onion(host: &str) -> Result<HsId, i32> {
    host.parse().map_err(|_| code::TOR_ONION_INVALID)
}

/// A Tor stream to `host:port`, the onion service `hsid` names.
pub async fn onion(ctx: &OnionContext, host: String, hsid: HsId, port: u16) -> Result<DataStream, i32> {
    let (client, shared) = (Arc::clone(&ctx.client), Arc::clone(&ctx.shared));
    // A task of its own, so the outcome lands in the status snapshot even when
    // the channel gives up first - as the bridge's did: its connect ran on
    // whatever the app did with the socket.
    let connect = ctx.runtime.spawn(async move { connect_and_record(&client, &shared, &host, hsid, port).await });
    match connect.await {
        Ok(outcome) => outcome,
        Err(e) if e.is_panic() => Err(code::INTERNAL),
        // The runtime went away under it: the Tor client stopped.
        Err(_) => Err(code::NETWORK),
    }
}

async fn connect_and_record(
    client: &Client,
    shared: &Shared,
    host: &str,
    hsid: HsId,
    port: u16,
) -> Result<DataStream, i32> {
    let target = (host, port);
    let connect = connect_in_groups(
        &shared.connect_groups,
        hsid,
        move |group| async move {
            let prefs = prefs_in(group);
            client.connect_with_prefs(target, &prefs).await
        },
        HEDGE_AFTER,
    );
    match tokio::time::timeout(CONNECT_BUDGET, connect).await {
        Ok(Ok(stream)) => {
            // Through: whatever failed before is not broken any more.
            shared.status.update(|s| s.error = error::NONE);
            Ok(stream)
        }
        Ok(Err(e)) => {
            let status = classify(&e);
            shared.status.update(|s| s.error = status);
            Err(onion_failure(&e))
        }
        Err(_) => {
            shared.status.update(|s| s.error = error::TIMEOUT);
            Err(code::TIMEOUT)
        }
    }
}

/// The channel's failure kind for an Arti error: the onion-service kinds by
/// name, the rest through the status snapshot's `classify`. Kinds only - the
/// message may carry an onion address and must not travel.
fn onion_failure(e: &arti_client::Error) -> i32 {
    use arti_client::HasKind;
    onion_failure_kind(e.kind())
}

/// `onion_failure`, by the kind.
fn onion_failure_kind(kind: ErrorKind) -> i32 {
    match kind {
        ErrorKind::OnionServiceAddressInvalid => code::TOR_ONION_INVALID,
        ErrorKind::OnionServiceNotFound => code::TOR_ONION_NOT_FOUND,
        // A service that asks for a key is one this client cannot reach: since
        // 045 it holds none, and TOR_CLIENT_AUTH is no longer produced.
        ErrorKind::OnionServiceNotRunning
        | ErrorKind::OnionServiceConnectionFailed
        | ErrorKind::OnionServiceProtocolViolation
        | ErrorKind::OnionServiceMissingClientAuth
        | ErrorKind::OnionServiceWrongClientAuth => code::TOR_ONION_UNREACHABLE,
        ErrorKind::BootstrapRequired => code::TOR_NOT_READY,
        _ => match classify_kind(kind) {
            // The network no longer takes this client: Tor is not coming up.
            error::SOFTWARE_DEPRECATED => code::TOR_NOT_READY,
            error::INTERNAL => code::INTERNAL,
            // The Tor network itself: circuits, directories, its timeouts.
            _ => code::NETWORK,
        },
    }
}

/// The isolation group connects to each onion service go in: Arti's default
/// until a hedge to that service is won in a fresh group, and that group from
/// then on. Kept for every service apart - a group won for one says nothing
/// about another - and for as long as the client lives (see engine).
///
/// Arti lets connects to an onion service share an attempt only when their
/// isolation is compatible, and an attempt that hangs runs on in a task of its
/// own after its connect gives up on it. A later connect in the same group would
/// join it and wait for the hedge all over again. Isolation decides only which
/// circuits to this one service are shared, so a new group costs nothing in
/// privacy.
#[derive(Default)]
pub struct ConnectGroups(Mutex<HashMap<HsId, IsolationToken>>);

impl ConnectGroups {
    /// The group a first attempt to `service` goes in: the one its last hedge
    /// was won in.
    pub(crate) fn current(&self, service: HsId) -> Option<IsolationToken> {
        lock(&self.0).get(&service).copied()
    }

    /// A hedge to `service` won in `group`: later connects to it go there.
    pub(crate) fn won(&self, service: HsId, group: IsolationToken) {
        lock(&self.0).insert(service, group);
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

/// One connect to `service`, hedged: the first attempt in its current group,
/// the hedge in a fresh one - it starts afresh, descriptor, introduction and
/// rendezvous, instead of waiting on the attempt that hangs - and once that one
/// wins, its group is the service's current one.
async fn connect_in_groups<T, E, C, F>(
    groups: &ConnectGroups,
    service: HsId,
    connect: C,
    after: Duration,
) -> Result<T, E>
where
    C: Fn(Option<IsolationToken>) -> F,
    F: Future<Output = Result<T, E>>,
{
    let connect = &connect;
    let current = groups.current(service);
    let first = async move { connect(current).await.map(|won| (won, None)) };
    let second = move || async move {
        let fresh = IsolationToken::new();
        connect(Some(fresh)).await.map(|won| (won, Some(fresh)))
    };
    let (won, fresh) = hedged(first, second, after).await?;
    if let Some(fresh) = fresh {
        groups.won(service, fresh);
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
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::net::TcpListener;

    #[tokio::test]
    async fn a_direct_connect_reaches_a_listener_by_address_and_by_name() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        for host in ["127.0.0.1", "localhost"] {
            let mut client = direct(host, port).await.unwrap_or_else(|code| panic!("{host}: {code}"));
            assert!(client.nodelay().unwrap());
            let (mut server, _) = listener.accept().await.unwrap();
            client.write_all(b"x").await.unwrap();
            assert_eq!(server.read_u8().await.unwrap(), b'x');
        }
    }

    #[tokio::test]
    async fn a_bracketed_ipv6_address_is_an_address() {
        let Ok(listener) = TcpListener::bind("[::1]:0").await else {
            return; // No IPv6 loopback on this machine.
        };
        let port = listener.local_addr().unwrap().port();
        assert!(direct("[::1]", port).await.is_ok());
        assert!(direct("::1", port).await.is_ok());
    }

    #[tokio::test]
    async fn a_refused_connect_is_the_networks_failure() {
        let port = {
            let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
            listener.local_addr().unwrap().port()
        };
        assert_eq!(direct("127.0.0.1", port).await.err(), Some(code::NETWORK));
    }

    #[test]
    fn an_onion_address_parses_only_when_it_is_one() {
        assert!(parse_onion("25njqamcweflpvkl73j4szahhihoc4xt3ktcgjnpaingr5yhkenl5sid.onion").is_ok());
        for broken in [
            "example.com",
            "nope.onion",
            // One character off: the checksum catches it.
            "25njqamcweflpvkl73j4szahhihoc4xt3ktcgjnpaingr5yhkenl5sie.onion",
        ] {
            assert_eq!(parse_onion(broken).err(), Some(code::TOR_ONION_INVALID), "{broken}");
        }
    }

    /// A service that asks for a key is out of reach: since 045 the client
    /// holds none, and TOR_CLIENT_AUTH is never the answer.
    #[test]
    fn an_arti_failure_is_the_channels_by_its_kind() {
        for (kind, expected) in [
            (ErrorKind::OnionServiceMissingClientAuth, code::TOR_ONION_UNREACHABLE),
            (ErrorKind::OnionServiceWrongClientAuth, code::TOR_ONION_UNREACHABLE),
            (ErrorKind::OnionServiceNotRunning, code::TOR_ONION_UNREACHABLE),
            (ErrorKind::OnionServiceConnectionFailed, code::TOR_ONION_UNREACHABLE),
            (ErrorKind::OnionServiceProtocolViolation, code::TOR_ONION_UNREACHABLE),
            (ErrorKind::OnionServiceNotFound, code::TOR_ONION_NOT_FOUND),
            (ErrorKind::OnionServiceAddressInvalid, code::TOR_ONION_INVALID),
            (ErrorKind::BootstrapRequired, code::TOR_NOT_READY),
            (ErrorKind::SoftwareDeprecated, code::TOR_NOT_READY),
            (ErrorKind::Internal, code::INTERNAL),
            (ErrorKind::TorNetworkTimeout, code::NETWORK),
        ] {
            assert_eq!(onion_failure_kind(kind), expected, "{kind:?}");
        }
    }

    mod stagger {
        use super::super::{staggered, ATTEMPT_DELAY};
        use std::cell::RefCell;
        use std::time::Duration;
        use tokio::time::Instant;

        /// What an address does when dialled: connect or fail after a while,
        /// or swallow the SYN and never answer.
        #[derive(Clone, Copy, Debug)]
        enum Peer {
            Answers(u64),
            Refuses(u64),
            BlackHole,
        }

        async fn dial(peer: (&'static str, Peer)) -> Result<&'static str, &'static str> {
            match peer.1 {
                Peer::Answers(ms) => {
                    tokio::time::sleep(Duration::from_millis(ms)).await;
                    Ok(peer.0)
                }
                Peer::Refuses(ms) => {
                    tokio::time::sleep(Duration::from_millis(ms)).await;
                    Err(peer.0)
                }
                Peer::BlackHole => std::future::pending().await,
            }
        }

        fn at(start: Instant, ms: u64) {
            let elapsed = start.elapsed();
            let expected = Duration::from_millis(ms);
            assert!(elapsed >= expected && elapsed < expected + Duration::from_millis(5), "settled at {elapsed:?}");
        }

        #[tokio::test(start_paused = true)]
        async fn a_black_hole_costs_one_delay_not_the_budget() {
            let start = Instant::now();
            let peers = vec![("v4", Peer::BlackHole), ("v6", Peer::Answers(10))];
            assert_eq!(staggered(peers, dial, ATTEMPT_DELAY).await, Some("v6"));
            at(start, 250 + 10);
        }

        #[tokio::test(start_paused = true)]
        async fn a_refusal_starts_the_next_at_once() {
            let start = Instant::now();
            let peers = vec![("a", Peer::Refuses(50)), ("b", Peer::Answers(10))];
            assert_eq!(staggered(peers, dial, ATTEMPT_DELAY).await, Some("b"));
            at(start, 50 + 10);
        }

        #[tokio::test(start_paused = true)]
        async fn a_slow_first_still_wins_when_it_answers_first() {
            let start = Instant::now();
            let peers = vec![("slow", Peer::Answers(300)), ("hole", Peer::BlackHole)];
            assert_eq!(staggered(peers, dial, ATTEMPT_DELAY).await, Some("slow"));
            at(start, 300);
        }

        #[tokio::test(start_paused = true)]
        async fn none_when_every_address_fails() {
            let start = Instant::now();
            let dialled = RefCell::new(Vec::new());
            let peers = vec![("a", Peer::Refuses(400)), ("b", Peer::Refuses(10)), ("c", Peer::Refuses(10))];
            let got = staggered(
                peers,
                |peer| {
                    dialled.borrow_mut().push(peer.0);
                    dial(peer)
                },
                ATTEMPT_DELAY,
            )
            .await;
            assert_eq!(got, None);
            // b at 250, refused at 260, c at once; a is the last to give up.
            assert_eq!(*dialled.borrow(), ["a", "b", "c"]);
            at(start, 400);
            assert_eq!(staggered(Vec::<(&str, Peer)>::new(), dial, ATTEMPT_DELAY).await, None, "no address at all");
        }
    }

    mod hedge {
        use super::super::{connect_in_groups, hedged, parse_onion, prefs_in, ConnectGroups, HEDGE_AFTER};
        use crate::onion::onion_from_pubkey;
        use arti_client::{HsId, IsolationToken, StreamPrefs};
        use std::cell::{Cell, RefCell};
        use std::time::Duration;
        use tokio::time::Instant;

        type Outcome = Result<&'static str, &'static str>;

        /// The onion service these connects go to, and another one.
        fn service() -> HsId {
            parse_onion("25njqamcweflpvkl73j4szahhihoc4xt3ktcgjnpaingr5yhkenl5sid.onion").unwrap()
        }

        fn another_service() -> HsId {
            parse_onion(&onion_from_pubkey(&[7u8; 32])).unwrap()
        }

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
            let (groups, made) = (ConnectGroups::default(), RefCell::new(Vec::new()));
            let connect = |g| {
                made.borrow_mut().push(g);
                one_hangs(g, None)
            };
            let start = Instant::now();
            assert_eq!(connect_in_groups(&groups, service(), connect, HEDGE_AFTER).await, Ok("connected"));
            at(start, HEDGE_AFTER + secs(2));
            let won = groups.current(service()).expect("the group the hedge won in is current");
            assert_eq!(*made.borrow(), [None, Some(won)]);

            // The next connect goes straight to the group that works.
            let start = Instant::now();
            assert_eq!(connect_in_groups(&groups, service(), connect, HEDGE_AFTER).await, Ok("connected"));
            at(start, secs(2));
            assert_eq!(*made.borrow(), [None, Some(won), Some(won)]);
            assert_eq!(groups.current(service()), Some(won));
        }

        #[tokio::test(start_paused = true)]
        async fn a_current_group_that_hangs_gives_way_to_the_next_winner() {
            let groups = ConnectGroups::default();
            let hung = IsolationToken::new();
            groups.won(service(), hung);
            let got = connect_in_groups(&groups, service(), |g| one_hangs(g, Some(hung)), HEDGE_AFTER).await;
            assert_eq!(got, Ok("connected"));
            let now = groups.current(service());
            assert!(now.is_some_and(|now| now != hung), "still {now:?}");
        }

        #[tokio::test(start_paused = true)]
        async fn a_first_attempt_that_wins_leaves_the_group_as_it_was() {
            let (groups, made) = (ConnectGroups::default(), RefCell::new(Vec::new()));
            let quick = |g| {
                made.borrow_mut().push(g);
                settles(secs(1), Ok("connected"))
            };
            assert_eq!(connect_in_groups(&groups, service(), quick, HEDGE_AFTER).await, Ok("connected"));
            assert_eq!(groups.current(service()), None);
            let stored = IsolationToken::new();
            groups.won(service(), stored);
            assert_eq!(connect_in_groups(&groups, service(), quick, HEDGE_AFTER).await, Ok("connected"));
            assert_eq!(groups.current(service()), Some(stored));
            assert_eq!(*made.borrow(), [None, Some(stored)], "no fresh group without a hedge");

            // Won by the first after the hedge was made: still the first's group.
            let slow_first = |g| settles(if g == Some(stored) { secs(20) } else { secs(30) }, Ok("connected"));
            assert_eq!(connect_in_groups(&groups, service(), slow_first, HEDGE_AFTER).await, Ok("connected"));
            assert_eq!(groups.current(service()), Some(stored));
        }

        #[tokio::test(start_paused = true)]
        async fn when_both_fail_the_group_stays() {
            let groups = ConnectGroups::default();
            let stored = IsolationToken::new();
            groups.won(service(), stored);
            let refused = |g| settles(if g == Some(stored) { secs(20) } else { secs(1) }, Err("refused"));
            assert_eq!(connect_in_groups(&groups, service(), refused, HEDGE_AFTER).await, Err("refused"));
            assert_eq!(groups.current(service()), Some(stored));
        }

        /// A group won for one service is no place for another's first
        /// attempt, and a hedge won for the other leaves the first's alone.
        #[tokio::test(start_paused = true)]
        async fn two_services_never_share_a_group() {
            let (groups, made) = (ConnectGroups::default(), RefCell::new(Vec::new()));
            let connect = |g| {
                made.borrow_mut().push(g);
                one_hangs(g, None)
            };
            assert_eq!(connect_in_groups(&groups, service(), connect, HEDGE_AFTER).await, Ok("connected"));
            let first = groups.current(service()).expect("the hedge to the first service won");
            assert_eq!(groups.current(another_service()), None, "nothing is won for the other yet");

            made.borrow_mut().clear();
            let start = Instant::now();
            assert_eq!(connect_in_groups(&groups, another_service(), connect, HEDGE_AFTER).await, Ok("connected"));
            at(start, HEDGE_AFTER + secs(2));
            let other = groups.current(another_service()).expect("the hedge to the other service won");
            assert_eq!(*made.borrow(), [None, Some(other)], "the other's first attempt is in Arti's default");
            assert_ne!(other, first);
            assert_eq!(groups.current(service()), Some(first));
        }
    }
}
