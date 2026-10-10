//! Timing harness for the FR-034 measurement (phase 040).
//!
//!     cargo run --release --example bootstrap -- <dir> [<onion host> [port]]
//!
//! Starts the client cold in <dir> (which it empties first), then warm from
//! the same directories, and - with an onion host - times the first and a
//! repeated connection to the service: the hedged connect every onion channel
//! makes (044), by the address alone (045), up to the open Tor stream. TLS and
//! Eidolon come on top of that in a channel and need a paired device's seed, so
//! they are not timed here.

use std::time::{Duration, Instant};

use nox_tor::channel::target;
use nox_tor::engine;
use nox_tor::status::{state, NoxTorStatus};

fn wait_ready(budget: Duration) -> Result<Duration, NoxTorStatus> {
    let started = Instant::now();
    loop {
        let s = engine::status();
        match s.state {
            state::READY => return Ok(started.elapsed()),
            state::FAILED | state::OBSOLETE => return Err(s),
            _ if started.elapsed() > budget => return Err(s),
            _ => std::thread::sleep(Duration::from_millis(50)),
        }
    }
}

fn rss_kb() -> String {
    let out = std::process::Command::new("ps").args(["-o", "rss=", "-p", &std::process::id().to_string()]).output();
    out.map(|o| String::from_utf8_lossy(&o.stdout).trim().to_owned()).unwrap_or_default()
}

/// One onion connect, as a channel makes it, until the Tor stream is open.
fn through_tor(onion: &str, port: u16) -> Result<Duration, String> {
    let ctx = engine::onion_context().ok_or("the client is not ready")?;
    let hsid = target::parse_onion(onion).map_err(|code| format!("channel code {code}"))?;
    let started = Instant::now();
    let stream = ctx.runtime.block_on(target::onion(&ctx, onion.to_owned(), hsid, port));
    match stream {
        Ok(_) => Ok(started.elapsed()),
        Err(code) => Err(format!("channel code {code}; status error {}", engine::status().error)),
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let dir = args.first().expect("usage: bootstrap <dir> [<onion> [port]]");
    let state_dir = format!("{dir}/state");
    let cache_dir = format!("{dir}/cache");
    let _ = std::fs::remove_dir_all(dir);
    println!("rss before start: {} KB", rss_kb());

    assert_eq!(engine::start(&state_dir, &cache_dir), 0);
    match wait_ready(Duration::from_secs(120)) {
        Ok(t) => println!("cold bootstrap: {:.2}s, rss {} KB", t.as_secs_f64(), rss_kb()),
        Err(s) => panic!("cold bootstrap failed: {s:?}"),
    }
    engine::stop();
    assert_eq!(engine::start(&state_dir, &cache_dir), 0);
    match wait_ready(Duration::from_secs(120)) {
        Ok(t) => println!("warm bootstrap: {:.2}s, rss {} KB", t.as_secs_f64(), rss_kb()),
        Err(s) => panic!("warm bootstrap failed: {s:?}"),
    }

    if let Some(onion) = args.get(1) {
        let port: u16 = args.get(2).and_then(|p| p.parse().ok()).unwrap_or(443);
        for label in ["first connect", "repeated connect"] {
            match through_tor(onion, port) {
                Ok(t) => println!("{label}: {:.2}s, rss {} KB", t.as_secs_f64(), rss_kb()),
                Err(e) => println!("{label}: FAILED ({e})"),
            }
        }
    }
    engine::stop();
}
