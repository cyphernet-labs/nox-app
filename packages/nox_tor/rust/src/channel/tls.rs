//! TLS 1.3 under the channel: the handshake must be signed, by whoever.
//!
//! The server's certificate is a throwaway one, made from a fresh P-256 key at
//! every start, so there is nothing to check it against and nothing is: who the
//! server is, Eidolon proves over the channel binding this layer exports. What
//! this layer does check is that the server signed the handshake with the key
//! of the certificate it sent (`verify_tls13_signature`), which keeps TLS
//! sound on its own terms.
//!
//! Every connection is a full handshake: no session resumption - a resumed TLS
//! 1.3 session carries no server signature at all - and no early data. No SNI
//! goes out either: no name decides anything here, and a fixed one in the clear
//! ClientHello would mark NOX traffic for anyone watching the network.

use std::fmt;
use std::io;
use std::net::{IpAddr, Ipv4Addr};
use std::sync::{Arc, OnceLock};

use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::client::Resumption;
use rustls::crypto::{verify_tls13_signature, WebPkiSupportedAlgorithms};
use rustls::pki_types::{CertificateDer, ServerName, UnixTime};
use rustls::{ClientConfig, ClientConnection, DigitallySignedStruct, PeerIncompatible, SignatureScheme};
use tokio::io::{AsyncRead, AsyncWrite};
use tokio_rustls::client::TlsStream;
use tokio_rustls::TlsConnector;

use super::code;

/// What HTTP runs over the channel: WebSocket and the file transfers both.
pub const ALPN: &[u8] = b"http/1.1";

/// RFC 9266: the channel binding of TLS 1.3, 32 bytes with an empty context.
pub const BINDING_LABEL: &[u8] = b"EXPORTER-Channel-Binding";

/// The client configuration, the same for every channel. None only if rustls
/// refuses it, which a test below would catch first.
pub fn config() -> Option<Arc<ClientConfig>> {
    static CONFIG: OnceLock<Option<Arc<ClientConfig>>> = OnceLock::new();
    CONFIG.get_or_init(|| build().ok()).clone()
}

fn build() -> Result<Arc<ClientConfig>, rustls::Error> {
    // Named rather than taken from the process default: Arti installs ring as
    // that default, but only once Tor starts, and a direct channel needs none.
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let verifier = Arc::new(AnyCertificate { algorithms: provider.signature_verification_algorithms });
    let mut config = ClientConfig::builder_with_provider(provider)
        .with_protocol_versions(&[&rustls::version::TLS13])?
        .dangerous()
        .with_custom_certificate_verifier(verifier)
        .with_no_client_auth();
    config.alpn_protocols = vec![ALPN.to_vec()];
    config.enable_sni = false;
    config.resumption = Resumption::disabled();
    config.enable_early_data = false;
    Ok(Arc::new(config))
}

/// The name handed to rustls, which wants one. It never leaves the device: SNI
/// is off, and rustls would not send an address as SNI anyway.
fn placeholder() -> ServerName<'static> {
    ServerName::from(IpAddr::V4(Ipv4Addr::UNSPECIFIED))
}

/// The TLS handshake over `io`.
pub async fn connect<IO>(io: IO) -> Result<TlsStream<IO>, i32>
where
    IO: AsyncRead + AsyncWrite + Unpin,
{
    let config = config().ok_or(code::INTERNAL)?;
    TlsConnector::from(config).connect(placeholder(), io).await.map_err(|e| handshake_failure(&e))
}

/// tokio-rustls hands rustls's refusals over as InvalidData. A peer that hangs
/// up in the middle of the handshake did not speak TLS 1.3 to us either; a
/// transport that breaks is the network's.
fn handshake_failure(e: &io::Error) -> i32 {
    match e.kind() {
        io::ErrorKind::InvalidData | io::ErrorKind::UnexpectedEof => code::TLS,
        _ => code::NETWORK,
    }
}

/// The channel binding both ends sign in Eidolon. A man in the middle runs two
/// TLS sessions and gets two different values.
pub fn channel_binding(conn: &ClientConnection) -> Result<[u8; 32], i32> {
    conn.export_keying_material([0u8; 32], BINDING_LABEL, Some(b"")).map_err(|_| code::INTERNAL)
}

/// Takes any certificate, and checks that the handshake was signed with its
/// key. TLS 1.2 is off in the configuration and refused here as well.
struct AnyCertificate {
    algorithms: WebPkiSupportedAlgorithms,
}

impl fmt::Debug for AnyCertificate {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("AnyCertificate")
    }
}

impl ServerCertVerifier for AnyCertificate {
    fn verify_server_cert(
        &self,
        _end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        Ok(ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        Err(PeerIncompatible::ServerTlsVersionIsDisabledByOurConfig.into())
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        verify_tls13_signature(message, cert, dss, &self.algorithms)
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.algorithms.supported_schemes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rustls::crypto::CryptoProvider;
    use rustls::pki_types::PrivateKeyDer;
    use rustls::server::{ClientHello, ResolvesServerCert};
    use rustls::sign::CertifiedKey;
    use rustls::ServerConfig;
    use tokio::io::{duplex, AsyncReadExt, AsyncWriteExt};
    use tokio_rustls::TlsAcceptor;

    fn provider() -> Arc<CryptoProvider> {
        Arc::new(rustls::crypto::ring::default_provider())
    }

    /// A throwaway P-256 certificate and its key, as the server makes them.
    fn certificate() -> (CertificateDer<'static>, PrivateKeyDer<'static>) {
        let key = rcgen::KeyPair::generate().unwrap();
        let cert = rcgen::CertificateParams::new(Vec::<String>::new()).unwrap().self_signed(&key).unwrap();
        (cert.der().clone(), PrivateKeyDer::from(key))
    }

    fn server(versions: &[&'static rustls::SupportedProtocolVersion]) -> ServerConfig {
        let (cert, key) = certificate();
        let mut config = ServerConfig::builder_with_provider(provider())
            .with_protocol_versions(versions)
            .unwrap()
            .with_no_client_auth()
            .with_single_cert(vec![cert], key)
            .unwrap();
        config.alpn_protocols = vec![ALPN.to_vec()];
        config
    }

    /// Presents one certificate and signs with another key: a handshake whose
    /// signature does not belong to the certificate sent with it.
    #[derive(Debug)]
    struct Mismatched(Arc<CertifiedKey>);

    impl ResolvesServerCert for Mismatched {
        fn resolve(&self, _hello: ClientHello<'_>) -> Option<Arc<CertifiedKey>> {
            Some(Arc::clone(&self.0))
        }
    }

    fn mismatched_server() -> ServerConfig {
        let (shown, _) = certificate();
        let (_, signing) = certificate();
        let signing = provider().key_provider.load_private_key(signing).unwrap();
        ServerConfig::builder_with_provider(provider())
            .with_protocol_versions(&[&rustls::version::TLS13])
            .unwrap()
            .with_no_client_auth()
            .with_cert_resolver(Arc::new(Mismatched(Arc::new(CertifiedKey::new(vec![shown], signing)))))
    }

    #[test]
    fn the_configuration_is_tls13_without_sni_resumption_or_early_data() {
        let config = config().expect("rustls takes the configuration");
        assert_eq!(config.alpn_protocols, [ALPN.to_vec()]);
        assert!(!config.enable_sni);
        assert!(!config.enable_early_data);
        // Resumption keeps its store private; its Debug names it.
        assert!(format!("{:?}", config.resumption).contains("NoClientSessionStorage"), "{:?}", config.resumption);
        assert!(!config.crypto_provider().fips(), "ring, not aws-lc");
    }

    #[tokio::test]
    async fn any_certificate_does_and_both_ends_export_the_same_binding() {
        let (client_io, server_io) = duplex(64 * 1024);
        let acceptor = TlsAcceptor::from(Arc::new(server(&[&rustls::version::TLS13])));
        let accepting = tokio::spawn(async move { acceptor.accept(server_io).await.unwrap() });
        let mut client = connect(client_io).await.expect("a self-signed certificate is accepted");
        let mut server = accepting.await.unwrap();

        let (_, conn) = client.get_ref();
        assert_eq!(conn.alpn_protocol(), Some(ALPN));
        assert_eq!(conn.protocol_version(), Some(rustls::ProtocolVersion::TLSv1_3));
        assert_eq!(server.get_ref().1.server_name(), None, "no SNI went out");

        let ours = channel_binding(client.get_ref().1).unwrap();
        let theirs = server.get_ref().1.export_keying_material([0u8; 32], BINDING_LABEL, None).unwrap();
        assert_eq!(ours, theirs, "an empty context and none are one value in TLS 1.3");

        client.write_all(b"ping").await.unwrap();
        client.flush().await.unwrap();
        let mut got = [0u8; 4];
        server.read_exact(&mut got).await.unwrap();
        assert_eq!(&got, b"ping");
    }

    #[tokio::test]
    async fn two_connections_have_two_bindings() {
        let mut bindings = Vec::new();
        for _ in 0..2 {
            let (client_io, server_io) = duplex(64 * 1024);
            let acceptor = TlsAcceptor::from(Arc::new(server(&[&rustls::version::TLS13])));
            let accepting = tokio::spawn(async move { acceptor.accept(server_io).await });
            let client = connect(client_io).await.unwrap();
            accepting.await.unwrap().unwrap();
            bindings.push(channel_binding(client.get_ref().1).unwrap());
        }
        assert_ne!(bindings[0], bindings[1]);
    }

    #[tokio::test]
    async fn a_tls12_server_is_refused() {
        let (client_io, server_io) = duplex(64 * 1024);
        let acceptor = TlsAcceptor::from(Arc::new(server(&[&rustls::version::TLS12])));
        tokio::spawn(async move { acceptor.accept(server_io).await });
        assert_eq!(connect(client_io).await.err(), Some(code::TLS));
    }

    #[tokio::test]
    async fn a_handshake_signed_by_another_key_is_refused() {
        let (client_io, server_io) = duplex(64 * 1024);
        let acceptor = TlsAcceptor::from(Arc::new(mismatched_server()));
        tokio::spawn(async move { acceptor.accept(server_io).await });
        assert_eq!(connect(client_io).await.err(), Some(code::TLS));
    }

    #[tokio::test]
    async fn a_peer_that_does_not_speak_tls_is_refused() {
        let (client_io, mut server_io) = duplex(64 * 1024);
        tokio::spawn(async move {
            let mut hello = [0u8; 5];
            let _ = server_io.read_exact(&mut hello).await;
            let _ = server_io.write_all(b"HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n").await;
        });
        assert_eq!(connect(client_io).await.err(), Some(code::TLS));

        // And one that hangs up on the ClientHello.
        let (client_io, server_io) = duplex(64 * 1024);
        drop(server_io);
        assert!(matches!(connect(client_io).await.err(), Some(code::TLS) | Some(code::NETWORK)));
    }
}
