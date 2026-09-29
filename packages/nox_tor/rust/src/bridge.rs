//! The loopback bridge the app dials instead of the onion service.
//!
//! The app does TLS and checks the server's fingerprint itself, exactly as on
//! the direct path; this bridge only moves bytes between a loopback socket and
//! a Tor stream to the one target the app set. Every connection must open with
//! the 32-byte secret of this bridge: any app on the device can dial
//! 127.0.0.1, and without the secret it could ride this client - and its
//! access key - to the person's server.

use std::sync::{Arc, Mutex};
use std::time::Duration;

use subtle::ConstantTimeEq;
use tokio::io::AsyncReadExt;
use tokio::net::{TcpListener, TcpStream};
use tokio::runtime::Runtime;
use tokio::task::JoinHandle;

use crate::engine::{lock, Shared};
use crate::status::{classify, error};

/// How long a fresh loopback connection may take to present the secret.
const SECRET_WAIT: Duration = Duration::from_secs(5);
/// One Tor connection to the onion service. A keyed connect fetches the
/// descriptor anew every time and sometimes hangs (Arti #2166, #2482): this is
/// the bound, and the app's reconnect ladder is the retry.
const CONNECT_BUDGET: Duration = Duration::from_secs(45);

pub struct BridgeHandle {
    task: JoinHandle<()>,
    pub port: u16,
    pub secret: Arc<Mutex<[u8; 32]>>,
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
    listener.set_nonblocking(true).map_err(|_| ())?;
    let port = listener.local_addr().map_err(|_| ())?.port();
    let secret = Arc::new(Mutex::new(secret));
    let task = runtime.spawn(serve(listener, Arc::clone(shared), Arc::clone(&secret)));
    *bridge = Some(BridgeHandle { task, port, secret });
    Ok(port)
}

async fn serve(listener: std::net::TcpListener, shared: Arc<Shared>, secret: Arc<Mutex<[u8; 32]>>) {
    let listener = match TcpListener::from_std(listener) {
        Ok(l) => l,
        Err(_) => {
            shared.status.update(|s| s.error = error::INTERNAL);
            return;
        }
    };
    loop {
        let Ok((socket, _)) = listener.accept().await else { continue };
        let expected = *lock(&secret);
        let shared = Arc::clone(&shared);
        tokio::spawn(async move {
            let _ = relay(socket, shared, expected).await;
        });
    }
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

async fn relay(mut socket: TcpStream, shared: Arc<Shared>, expected: [u8; 32]) -> Result<(), ()> {
    read_secret(&mut socket, &expected).await?;
    let target = lock(&shared.target).clone().ok_or(())?;
    let client = lock(&shared.client).clone().ok_or(())?;
    let mut stream = match tokio::time::timeout(CONNECT_BUDGET, client.connect((target.host.as_str(), target.port))).await
    {
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
}
