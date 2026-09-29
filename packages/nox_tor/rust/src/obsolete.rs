//! Keeping Arti from killing the app.
//!
//! When the consensus lists a protocol this Arti lacks as REQUIRED, Arti logs an
//! ERROR from `arti_client::protostatus`, prints to stderr, sleeps five seconds
//! on the client's runtime and calls `std::process::exit(1)` (arti-client
//! 0.47.0, `client.rs`; #1932 is open and the opt-out was removed in 2.4.0). In
//! an app that exit is the whole app, not a daemon.
//!
//! The runtime is ours, so the defence is to tear it down inside those five
//! seconds: the exiting task is parked on its async sleep and is dropped with
//! the runtime before it ever reaches the exit. This layer sees the ERROR
//! event and hands the teardown to a plain thread - dropping a runtime from one
//! of its own workers would panic.
//!
//! Only ERROR counts. The module also logs a WARN ("Bug: Got
//! DirEvent::NewProtocolRecommendation ...") and carries on; treating that as
//! fatal would switch Tor off for nothing.

use tracing::{Event, Level, Subscriber};
use tracing_subscriber::layer::{Context, Layer};

pub const TARGET: &str = "arti_client::protostatus";

/// Calls `on_fatal` for an ERROR from the protocol-status module.
pub struct ObsoleteLayer<F: Fn() + Send + Sync + 'static> {
    on_fatal: F,
}

impl<F: Fn() + Send + Sync + 'static> ObsoleteLayer<F> {
    pub fn new(on_fatal: F) -> Self {
        Self { on_fatal }
    }
}

impl<S: Subscriber, F: Fn() + Send + Sync + 'static> Layer<S> for ObsoleteLayer<F> {
    fn on_event(&self, event: &Event<'_>, _ctx: Context<'_, S>) {
        let meta = event.metadata();
        if *meta.level() == Level::ERROR && meta.target().starts_with(TARGET) {
            (self.on_fatal)();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;
    use tracing_subscriber::prelude::*;

    #[test]
    fn an_error_from_protostatus_fires_and_nothing_else_does() {
        let fired = Arc::new(AtomicUsize::new(0));
        let counter = Arc::clone(&fired);
        let subscriber =
            tracing_subscriber::registry().with(ObsoleteLayer::new(move || {
                counter.fetch_add(1, Ordering::SeqCst);
            }));
        tracing::subscriber::with_default(subscriber, || {
            tracing::warn!(target: "arti_client::protostatus", "Bug: Got DirEvent::NewProtocolRecommendation");
            tracing::info!(target: "arti_client::protostatus", "listed as recommended");
            tracing::error!(target: "tor_dirmgr", "an unrelated error");
            assert_eq!(fired.load(Ordering::SeqCst), 0);
            tracing::error!(target: "arti_client::protostatus", "listed as required for clients");
        });
        assert_eq!(fired.load(Ordering::SeqCst), 1);
    }
}
