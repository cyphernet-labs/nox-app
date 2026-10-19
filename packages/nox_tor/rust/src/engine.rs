//! The one Tor client of the process and its runtime.
//!
//! Every C ABI call takes the engine lock for a moment and never waits on the
//! network: the work runs on a tokio runtime this module owns, and its results
//! land in the status snapshot the app polls. Onion channels (`channel`) run on
//! that runtime too, through `onion_context`, and reach a service by its
//! address alone: since 045 the client holds no keys, and nothing about a
//! service is set up in it ahead of a connect.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, OnceLock};
use std::time::Duration;

use arti_client::config::{BoolOrAuto, TorClientConfigBuilder};
use arti_client::{DormantMode, TorClient, TorClientConfig};
use futures::StreamExt;
use tokio::runtime::Runtime;
use tor_rtcompat::PreferredRuntime;

use crate::channel::target::{ConnectGroups, OnionContext};
use crate::status::{classify, error, state, NoxTorStatus, StatusCell};

/// First start of the client, from nothing, until it is ready for traffic.
const BOOTSTRAP_BUDGET: Duration = Duration::from_secs(90);

pub type Client = TorClient<PreferredRuntime>;

/// State shared between the C ABI and the runtime's tasks.
#[derive(Default)]
pub struct Shared {
    pub status: StatusCell,
    pub client: Mutex<Option<Arc<Client>>>,
    /// The group each onion service's connects go in. Lives as long as this
    /// client: a rebuilt one has no attempt left over to stay clear of.
    pub connect_groups: ConnectGroups,
}

struct Engine {
    runtime: Option<Runtime>,
    shared: Arc<Shared>,
}

static ENGINE: OnceLock<Mutex<Option<Engine>>> = OnceLock::new();
/// Set once the network refused this client. The process never starts Tor
/// again: a new runtime would read the same consensus and Arti would exit.
static OBSOLETE: AtomicBool = AtomicBool::new(false);

fn engine() -> MutexGuard<'static, Option<Engine>> {
    ENGINE.get_or_init(|| Mutex::new(None)).lock().unwrap_or_else(|p| p.into_inner())
}

pub fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|p| p.into_inner())
}

/// Process-wide setup that may run only once: the rustls provider (Arti panics
/// without one since 2.3) and the tracing subscriber that carries the guard
/// against Arti's exit. Nothing else is subscribed, so Arti's own log lines -
/// which name onion addresses - go nowhere.
fn install_process_hooks() {
    static ONCE: OnceLock<()> = OnceLock::new();
    ONCE.get_or_init(|| {
        let _ = rustls::crypto::ring::default_provider().install_default();
        use tracing_subscriber::prelude::*;
        let subscriber = tracing_subscriber::registry().with(crate::obsolete::ObsoleteLayer::new(on_obsolete));
        let _ = tracing::subscriber::set_global_default(subscriber);
    });
}

/// Called from inside an Arti task when it is about to exit the process. The
/// teardown runs on a plain thread: a runtime cannot be dropped from one of its
/// own workers.
fn on_obsolete() {
    OBSOLETE.store(true, Ordering::SeqCst);
    std::thread::spawn(|| {
        let mut guard = engine();
        if let Some(e) = guard.as_mut() {
            e.shared.status.force_obsolete();
            if let Some(rt) = e.runtime.take() {
                rt.shutdown_background();
            }
            lock(&e.shared.client).take();
        }
    });
}

pub fn start(state_dir: &str, cache_dir: &str) -> i32 {
    install_process_hooks();
    let mut guard = engine();
    if OBSOLETE.load(Ordering::SeqCst) {
        return -(error::SOFTWARE_DEPRECATED as i32);
    }
    // Running, or still coming up: nothing to do. A client that FAILED is
    // rebuilt instead - this call is how the app retries it, and nothing else
    // would ever bootstrap it again.
    if guard.as_ref().is_some_and(|e| e.runtime.is_some() && e.shared.status.get().state != state::FAILED) {
        return 0;
    }
    let runtime =
        match tokio::runtime::Builder::new_multi_thread().worker_threads(2).thread_name("nox-tor").enable_all().build()
        {
            Ok(rt) => rt,
            Err(_) => return -(error::INTERNAL as i32),
        };
    if let Some(mut failed) = guard.take() {
        take_down(&mut failed);
    }
    let shared = Arc::new(Shared::default());
    shared.status.update(|s| *s = NoxTorStatus { state: state::BOOTSTRAPPING, ..NoxTorStatus::default() });
    let task_shared = Arc::clone(&shared);
    let (state_dir, cache_dir) = (state_dir.to_owned(), cache_dir.to_owned());
    runtime.spawn(async move { run_client(task_shared, state_dir, cache_dir).await });
    *guard = Some(Engine { runtime: Some(runtime), shared });
    0
}

/// Ends what `engine` runs: its client, and its runtime with every task on it
/// - onion channels included - without waiting for them.
fn take_down(engine: &mut Engine) {
    lock(&engine.shared.client).take();
    if let Some(rt) = engine.runtime.take() {
        rt.shutdown_background();
    }
}

/// Arti's defaults under the app's own directories, with the keystore off:
/// since 045 the client holds no keys, so nothing is looked up for a service
/// and nothing is kept for one, in memory or on disk. Left to Arti, it would
/// keep one under the state directory.
fn client_config(state_dir: &str, cache_dir: &str) -> Result<TorClientConfig, u8> {
    let mut builder = TorClientConfigBuilder::from_directories(state_dir, cache_dir);
    builder.storage().keystore().enabled(BoolOrAuto::Explicit(false));
    builder.build().map_err(|_| error::INTERNAL)
}

fn build_client(state_dir: &str, cache_dir: &str) -> Result<Arc<Client>, u8> {
    let config = client_config(state_dir, cache_dir)?;
    TorClient::builder().config(config).create_unbootstrapped().map_err(|e| classify(&e))
}

async fn run_client(shared: Arc<Shared>, state_dir: String, cache_dir: String) {
    let client = match build_client(&state_dir, &cache_dir) {
        Ok(c) => c,
        Err(code) => return fail(&shared, code),
    };
    *lock(&shared.client) = Some(Arc::clone(&client));

    let mut events = client.bootstrap_events();
    let progress = Arc::clone(&shared);
    tokio::spawn(async move {
        while let Some(status) = events.next().await {
            let percent = (status.as_frac() * 100.0).round().clamp(0.0, 100.0) as u8;
            progress.status.update(|s| {
                if s.state == state::BOOTSTRAPPING {
                    s.bootstrap_percent = percent;
                }
            });
            if status.ready_for_traffic() {
                break;
            }
        }
    });

    match tokio::time::timeout(BOOTSTRAP_BUDGET, client.bootstrap()).await {
        Ok(Ok(())) => shared.status.update(|s| {
            s.state = state::READY;
            s.bootstrap_percent = 100;
            s.error = error::NONE;
        }),
        Ok(Err(e)) => fail(&shared, classify(&e)),
        Err(_) => fail(&shared, error::TIMEOUT),
    }
}

fn fail(shared: &Shared, code: u8) {
    if code == error::SOFTWARE_DEPRECATED {
        OBSOLETE.store(true, Ordering::SeqCst);
        shared.status.force_obsolete();
        return;
    }
    shared.status.update(|s| {
        s.state = state::FAILED;
        s.error = code;
    });
}

pub fn set_dormant(dormant: bool) {
    let guard = engine();
    let Some(engine) = guard.as_ref() else { return };
    if let Some(client) = lock(&engine.shared.client).clone() {
        client.set_dormant(if dormant { DormantMode::Soft } else { DormantMode::Normal });
    }
    engine.shared.status.update(|s| match (dormant, s.state) {
        (true, state::READY) => s.state = state::DORMANT,
        (false, state::DORMANT) => s.state = state::READY,
        _ => {}
    });
}

pub fn stop() {
    let mut guard = engine();
    if let Some(mut engine) = guard.take() {
        take_down(&mut engine);
        if OBSOLETE.load(Ordering::SeqCst) {
            // Keep reporting OBSOLETE after a stop: the app must keep knowing.
            engine.shared.status.force_obsolete();
            *guard = Some(engine);
        }
    }
}

pub fn status() -> NoxTorStatus {
    let guard = engine();
    match guard.as_ref() {
        Some(e) => e.shared.status.get(),
        None if OBSOLETE.load(Ordering::SeqCst) => {
            NoxTorStatus { state: state::OBSOLETE, error: error::SOFTWARE_DEPRECATED, ..NoxTorStatus::default() }
        }
        None => NoxTorStatus::default(),
    }
}

/// What an onion channel runs on: the client's runtime and the client itself,
/// once it is ready for traffic. Dormant counts: a soft-dormant client still
/// takes the streams asked of it, and the app is in the background then.
pub fn onion_context() -> Option<OnionContext> {
    let guard = engine();
    let engine = guard.as_ref()?;
    let runtime = engine.runtime.as_ref()?.handle().clone();
    if !matches!(engine.shared.status.get().state, state::READY | state::DORMANT) {
        return None;
    }
    let client = lock(&engine.shared.client).clone()?;
    Some(OnionContext { runtime, client, shared: Arc::clone(&engine.shared) })
}

#[cfg(test)]
pub(crate) fn simulate_obsolete_for_test() {
    on_obsolete();
}

#[cfg(test)]
pub(crate) fn set_state_for_test(to: u8) {
    if let Some(e) = engine().as_ref() {
        e.shared.status.update(|s| s.state = to);
    }
}

#[cfg(test)]
pub(crate) fn reset_for_test() {
    stop();
    OBSOLETE.store(false, Ordering::SeqCst);
    engine().take();
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The key manager is in the build whatever this crate asks for
    /// (tor-chanmgr brings it), so only the configuration keeps the keystore
    /// off - and with it, the directory Arti would make for one.
    #[tokio::test(flavor = "multi_thread")]
    async fn the_client_keeps_no_keystore() {
        let dir = std::env::temp_dir().join(format!("nox_tor_keystore_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let (state, cache) = (dir.join("state"), dir.join("cache"));
        let (state, cache) = (state.to_str().unwrap(), cache.to_str().unwrap());
        assert!(client_config(state, cache).expect("the configuration builds").keystore().primary_kind().is_none());
        let client = build_client(state, cache).expect("the client builds");
        assert!(dir.join("state").is_dir(), "the client was built where the test looks");
        assert!(!dir.join("state").join("keystore").exists());
        drop(client);
        let _ = std::fs::remove_dir_all(dir);
    }
}
