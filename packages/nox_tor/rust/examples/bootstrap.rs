//! Timing harness for the FR-034 measurement (phase 040).
//!
//!     cargo run --release --example bootstrap -- <dir> [<onion host> <client key, base64> [port]]
//!
//! Starts the client cold in <dir> (which it empties first), then warm from
//! the same directories, and - with a target - times the first and a repeated
//! keyed connection through the bridge. A connection counts as up when the
//! server's first byte comes back: plain HTTP sent to a TLS port makes the Go
//! server answer at once, so no TLS stack is needed here.

use std::io::{Read, Write};
use std::net::TcpStream;
use std::time::{Duration, Instant};

use data_encoding::BASE64;
use nox_tor::engine;
use nox_tor::status::{state, NoxTorStatus};
use zeroize::Zeroizing;

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

fn through_bridge() -> Result<Duration, String> {
    let status = engine::status();
    let secret = engine::bridge_secret().ok_or("no bridge")?;
    let started = Instant::now();
    let mut socket = TcpStream::connect(("127.0.0.1", status.port)).map_err(|e| e.to_string())?;
    socket.set_read_timeout(Some(Duration::from_secs(60))).ok();
    socket.write_all(&secret).map_err(|e| e.to_string())?;
    socket.write_all(b"GET /health HTTP/1.0\r\n\r\n").map_err(|e| e.to_string())?;
    let mut first = [0u8; 1];
    match socket.read(&mut first) {
        Ok(1) => Ok(started.elapsed()),
        Ok(_) => Err(format!("closed without a byte; bridge error {}", engine::status().error)),
        Err(e) => Err(format!("{e}; bridge error {}", engine::status().error)),
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let dir = args.first().expect("usage: bootstrap <dir> [<onion> <key-b64> [port]]");
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

    if let (Some(onion), Some(key)) = (args.get(1), args.get(2)) {
        let port: u16 = args.get(3).and_then(|p| p.parse().ok()).unwrap_or(443);
        let key: [u8; 32] = BASE64.decode(key.as_bytes()).expect("key is base64").try_into().expect("32 bytes");
        assert_eq!(engine::set_target(onion, port, Box::new(Zeroizing::new(key))), 0);
        for label in ["first keyed connect", "repeated keyed connect"] {
            match through_bridge() {
                Ok(t) => println!("{label}: {:.2}s, rss {} KB", t.as_secs_f64(), rss_kb()),
                Err(e) => println!("{label}: FAILED ({e})"),
            }
        }
    }
    engine::stop();
}
