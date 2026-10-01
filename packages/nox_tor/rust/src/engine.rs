//! The one Tor client of the process, its runtime and its target.
//!
//! Every C ABI call takes the engine lock for a moment and never waits on the
//! network: the work runs on a tokio runtime this module owns, and its results
//! land in the status snapshot the app polls.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, OnceLock};
use std::time::Duration;

use arti_client::config::TorClientConfigBuilder;
use arti_client::{DormantMode, HsId, KeystoreSelector, TorClient};
use futures::StreamExt;
use subtle::ConstantTimeEq;
use tokio::runtime::Runtime;
use tor_config::ExplicitOrAuto;
use tor_hscrypto::pk::HsClientDescEncSecretKey;
use tor_keymgr::config::ArtiKeystoreKind;
use tor_llcrypto::pk::curve25519;
use tor_rtcompat::PreferredRuntime;
use zeroize::Zeroizing;

use crate::bridge::{self, BridgeHandle, ConnectGroup};
use crate::status::{classify, error, state, NoxTorStatus, StatusCell};

/// First start of the client, from nothing, until it is ready for traffic.
const BOOTSTRAP_BUDGET: Duration = Duration::from_secs(90);

pub type Client = TorClient<PreferredRuntime>;

/// The client key of a target. Wiped when dropped, and boxed so that moving a
/// `Target` moves a pointer rather than leaving copies of the key behind.
pub type ClientKey = Box<Zeroizing<[u8; 32]>>;

/// What the bridge connects to: one onion service and the client key that
/// opens it. Nothing else is reachable through this module. Not `Clone`: the
/// key has one home, the target slot.
pub struct Target {
    pub host: String,
    pub hsid: HsId,
    pub port: u16,
    pub key: ClientKey,
}

impl Target {
    /// The same service and the same key: what Arti keeps a connection record
    /// by, and so what a connect group stays good for.
    fn same_service_and_key(&self, other: &Target) -> bool {
        self.hsid == other.hsid && bool::from(self.key[..].ct_eq(&other.key[..]))
    }
}

/// State shared between the C ABI and the runtime's tasks.
#[derive(Default)]
pub struct Shared {
    pub status: StatusCell,
    pub client: Mutex<Option<Arc<Client>>>,
    pub target: Mutex<Option<Target>>,
    pub bridge: Mutex<Option<BridgeHandle>>,
    pub connect_group: ConnectGroup,
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
            lock(&e.shared.bridge).take();
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
    let shared = Arc::new(Shared::default());
    let port = guard.take().map_or(0, |failed| carry_over(failed, &runtime, &shared));
    shared.status.update(|s| *s = NoxTorStatus { state: state::BOOTSTRAPPING, port, ..NoxTorStatus::default() });
    let task_shared = Arc::clone(&shared);
    let (state_dir, cache_dir) = (state_dir.to_owned(), cache_dir.to_owned());
    runtime.spawn(async move { run_client(task_shared, state_dir, cache_dir).await });
    *guard = Some(Engine { runtime: Some(runtime), shared });
    0
}

/// Takes a failed engine down the way `stop` does, except for what the app
/// still holds: the target, and the bridge's port and secret. Those move to
/// `shared` and are served from `runtime`, so the app's endpoint stays good
/// across the retry. Returns the bridge's port, 0 without one.
fn carry_over(mut failed: Engine, runtime: &Runtime, shared: &Arc<Shared>) -> u16 {
    let target = lock(&failed.shared.target).take();
    *lock(&shared.target) = target;
    let bridge = lock(&failed.shared.bridge).take();
    lock(&failed.shared.client).take();
    if let Some(rt) = failed.runtime.take() {
        rt.shutdown_background();
    }
    let Some(mut bridge) = bridge else { return 0 };
    if bridge.move_to(runtime, shared).is_err() {
        return 0;
    }
    let port = bridge.port;
    *lock(&shared.bridge) = Some(bridge);
    port
}

fn build_client(state_dir: &str, cache_dir: &str) -> Result<Arc<Client>, u8> {
    let mut builder = TorClientConfigBuilder::from_directories(state_dir, cache_dir);
    // The key that opens the onion service lives in the app's secure storage
    // and is handed in on every start. Arti's default on-disk store would write
    // it out unencrypted.
    builder.storage().keystore().primary().kind(ExplicitOrAuto::Explicit(ArtiKeystoreKind::Ephemeral));
    let config = builder.build().map_err(|_| error::INTERNAL)?;
    TorClient::builder().config(config).create_unbootstrapped().map_err(|e| classify(&e))
}

async fn run_client(shared: Arc<Shared>, state_dir: String, cache_dir: String) {
    let client = match build_client(&state_dir, &cache_dir) {
        Ok(c) => c,
        Err(code) => return fail(&shared, code),
    };
    *lock(&shared.client) = Some(Arc::clone(&client));
    // A target set while the client was still being built. Applied under the
    // target's lock, as every key change is: a set_target or clear_target
    // landing meanwhile either finds this client or waits for this apply,
    // never slips between the read and the insert.
    {
        let target = lock(&shared.target);
        if let Some(target) = target.as_ref() {
            if apply_key(&client, target).is_err() {
                shared.status.update(|s| s.error = error::INTERNAL);
            }
        }
    }

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

/// Puts the target's key in the client. Insert never overwrites, so whatever
/// key this service had goes first: switching from an invite's one-time key to
/// the device's own is remove-then-insert.
fn apply_key(client: &Client, target: &Target) -> Result<(), ()> {
    let _ = client.remove_service_discovery_key(KeystoreSelector::Primary, target.hsid);
    let key = HsClientDescEncSecretKey::from(curve25519::StaticSecret::from(**target.key));
    client.insert_service_discovery_key(KeystoreSelector::Primary, target.hsid, key).map(|_| ()).map_err(|_| ())
}

pub fn set_target(host: &str, port: u16, key: ClientKey) -> i32 {
    let hsid: HsId = match host.parse() {
        Ok(h) => h,
        Err(_) => return error::RET_INVALID_ARGUMENT,
    };
    if port == 0 {
        return error::RET_INVALID_ARGUMENT;
    }
    let guard = engine();
    let Some(engine) = guard.as_ref() else {
        return error::RET_NOT_STARTED;
    };
    let Some(runtime) = engine.runtime.as_ref() else {
        return error::RET_NOT_STARTED;
    };
    let shared = &engine.shared;
    {
        // The slot and the keystore change together, under the target's lock
        // (see run_client).
        let mut slot = lock(&shared.target);
        let previous = slot.replace(Target { host: host.to_owned(), hsid, port, key });
        if !previous.as_ref().zip(slot.as_ref()).is_some_and(|(prev, now)| prev.same_service_and_key(now)) {
            // The group a hedge was won in belongs to the target it won for.
            shared.connect_group.forget();
        }
        let client = lock(&shared.client).clone();
        if let (Some(client), Some(target)) = (client, slot.as_ref()) {
            if let Some(prev) = previous.filter(|prev| prev.hsid != target.hsid) {
                let _ = client.remove_service_discovery_key(KeystoreSelector::Primary, prev.hsid);
            }
            if apply_key(&client, target).is_err() {
                return -(error::INTERNAL as i32);
            }
        }
    }
    match bridge::open_or_rotate(runtime, shared) {
        Ok(port) => {
            shared.status.update(|s| {
                s.port = port;
                // A refusal of the key so far was about the previous key.
                s.forget_key_refusal();
            });
            0
        }
        Err(()) => -(error::INTERNAL as i32),
    }
}

pub fn clear_target() -> i32 {
    let guard = engine();
    let Some(engine) = guard.as_ref() else {
        return error::RET_NOT_STARTED;
    };
    let shared = &engine.shared;
    {
        // Under the target's lock, like every key change (see run_client).
        let mut slot = lock(&shared.target);
        if let (Some(prev), Some(client)) = (slot.take(), lock(&shared.client).clone()) {
            let _ = client.remove_service_discovery_key(KeystoreSelector::Primary, prev.hsid);
        }
        shared.connect_group.forget();
    }
    lock(&shared.bridge).take();
    shared.status.update(|s| s.port = 0);
    0
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
        lock(&engine.shared.bridge).take();
        lock(&engine.shared.client).take();
        lock(&engine.shared.target).take();
        if let Some(rt) = engine.runtime.take() {
            rt.shutdown_background();
        }
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

pub fn bridge_secret() -> Option<[u8; 32]> {
    let guard = engine();
    let engine = guard.as_ref()?;
    let bridge = lock(&engine.shared.bridge);
    bridge.as_ref().map(|b| *lock(&b.secret))
}

#[cfg(test)]
pub(crate) fn simulate_obsolete_for_test() {
    on_obsolete();
}

#[cfg(test)]
pub(crate) fn set_error_for_test(code: u8) {
    if let Some(e) = engine().as_ref() {
        e.shared.status.update(|s| s.error = code);
    }
}

#[cfg(test)]
pub(crate) fn connect_group_won_for_test(group: arti_client::IsolationToken) {
    if let Some(e) = engine().as_ref() {
        e.shared.connect_group.won(group);
    }
}

#[cfg(test)]
pub(crate) fn connect_group_for_test() -> Option<arti_client::IsolationToken> {
    engine().as_ref()?.shared.connect_group.current()
}

#[cfg(test)]
pub(crate) fn target_host_for_test() -> Option<String> {
    let guard = engine();
    let target = lock(&guard.as_ref()?.shared.target);
    target.as_ref().map(|t| t.host.clone())
}

#[cfg(test)]
pub(crate) fn reset_for_test() {
    stop();
    OBSOLETE.store(false, Ordering::SeqCst);
    engine().take();
}
