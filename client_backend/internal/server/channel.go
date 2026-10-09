package server

import (
	"context"
	"crypto/ed25519"
	"crypto/tls"
	"encoding/base64"
	"errors"
	"log/slog"
	"net"
	"sync"
	"time"

	"nox.app/client-backend/internal/eidolon"
)

const (
	// defaultChannelTimeout bounds TLS and the channel check together on the
	// main entry, counted from the moment a connection is accepted (contract
	// §1). TLS alone had 5 s there, through ReadHeaderTimeout; the check adds
	// one round trip, and 10 s covers it on the slowest home network. The onion
	// entry gets onionTimeout instead.
	defaultChannelTimeout = 10 * time.Second
	// maxPendingChannels bounds the connections that are still proving who
	// they are, per entry. A legitimate burst - every device of one person
	// reconnecting after a restart - is a small fraction of it.
	maxPendingChannels = 64
)

// channelPeer is what the channel check proved about a connection: the key of
// the device on the other end. Proved, not claimed - the device signed this
// TLS session's binding with it.
type channelPeer struct {
	key ed25519.PublicKey
}

// deviceKey is the key the way devices.device_key stores it.
func (p channelPeer) deviceKey() string {
	return base64.StdEncoding.EncodeToString(p.key)
}

// channelPeerKey marks a request with its connection's channelPeer.
type channelPeerKey struct{}

// withChannelPeer is the ConnContext of both entries: every request on a
// connection carries the key that connection proved. The mark is on the
// SOCKET, never derived from anything a request says - the same reasoning that
// put the onion mark there.
func withChannelPeer(ctx context.Context, c net.Conn) context.Context {
	if cc, ok := c.(*channelConn); ok {
		return context.WithValue(ctx, channelPeerKey{}, cc.peer)
	}
	return ctx
}

// channelPeerFrom reads the proved key of the request's connection. false
// means the connection never went through the channel listener - which Run
// never lets happen, and which every caller treats as a stranger.
func channelPeerFrom(ctx context.Context) (channelPeer, bool) {
	p, ok := ctx.Value(channelPeerKey{}).(channelPeer)
	return p, ok
}

// channelConn is a connection that passed both layers: the TLS session it
// runs in, and the device key it proved there.
type channelConn struct {
	net.Conn
	peer channelPeer
}

// channelListener is the channel's front door (contract §1, research R5). It
// takes connections off the listener it wraps and hands http.Server only the
// ones that passed both layers - TLS 1.3, then the channel check - so no
// handler, not even a 404, ever answers a connection that has not proved a
// device key. The HTTP server itself does no TLS: it is given connections
// that already have it.
//
// Each connection proves itself on a goroutine of its own, under ONE deadline
// counted from the moment it was accepted, so a silent or slow client costs
// its own goroutine and nothing else. At most maxPendingChannels prove
// themselves at once; past that the loop leaves new connections in the
// kernel's queue until a slot frees, which keeps a flood from turning into
// unbounded goroutines.
//
// Closing it ends every handshake still under way and closes its connection,
// and a connection that passed but was never taken is closed too.
type channelListener struct {
	raw    net.Listener
	tls    *tls.Config
	key    ed25519.PrivateKey
	budget time.Duration
	logger *slog.Logger
	// entry names the door in the log: "direct" or "onion".
	entry string

	ready chan *channelConn
	slots chan struct{}
	// cancel ends every handshake and delivery; closed tells Accept.
	cancel    context.CancelFunc
	closed    chan struct{}
	closeOnce sync.Once
	// wg tracks the accept loop and every handshake, so Close returns only
	// once none of them can touch a connection any more.
	wg sync.WaitGroup
}

// newChannelListener starts taking connections off raw at once; Accept hands
// out the ones that pass.
func (s *Server) newChannelListener(raw net.Listener, cfg *tls.Config, key ed25519.PrivateKey, budget time.Duration, entry string) *channelListener {
	ctx, cancel := context.WithCancel(context.Background())
	l := &channelListener{
		raw:    raw,
		tls:    cfg,
		key:    key,
		budget: budget,
		logger: s.logger.With("component", "channel"),
		entry:  entry,
		ready:  make(chan *channelConn),
		slots:  make(chan struct{}, maxPendingChannels),
		cancel: cancel,
		closed: make(chan struct{}),
	}
	l.wg.Go(func() { l.acceptLoop(ctx) })
	return l
}

// Accept returns the next connection that passed the check.
func (l *channelListener) Accept() (net.Conn, error) {
	select {
	case c := <-l.ready:
		// Both cases can be ready at once, and select picks at random. A
		// connection handed out after Close would reach a server that is
		// shutting down and be served anyway.
		select {
		case <-l.closed:
			_ = c.Close()
			return nil, net.ErrClosed
		default:
		}
		return c, nil
	case <-l.closed:
		return nil, net.ErrClosed
	}
}

// Close stops taking connections, ends the handshakes under way and waits
// until none of them can touch a connection.
func (l *channelListener) Close() error {
	l.cancel()
	err := l.raw.Close()
	l.markClosed()
	l.wg.Wait()
	return err
}

// Addr is the address of the listener it wraps.
func (l *channelListener) Addr() net.Addr {
	return l.raw.Addr()
}

func (l *channelListener) markClosed() {
	l.closeOnce.Do(func() { close(l.closed) })
}

// acceptLoop takes connections off raw for as long as the listener lives.
//
// A failed Accept other than a closed listener is retried with a growing
// pause, the way net/http's own loop does: running out of file descriptors is
// a passing condition, and giving up on it would take the server down with it.
// If raw itself goes away, Accept says so and the HTTP server stops.
func (l *channelListener) acceptLoop(ctx context.Context) {
	defer l.markClosed()
	var pause time.Duration
	for {
		select {
		case l.slots <- struct{}{}:
		case <-ctx.Done():
			return
		}
		raw, err := l.raw.Accept()
		if err != nil {
			<-l.slots
			if ctx.Err() != nil || errors.Is(err, net.ErrClosed) {
				return
			}
			pause = min(max(2*pause, 5*time.Millisecond), time.Second)
			l.logger.Warn("accept failed, retrying", "entry", l.entry, "err", err, "in", pause)
			select {
			case <-time.After(pause):
			case <-ctx.Done():
				return
			}
			continue
		}
		pause = 0
		accepted := time.Now()
		l.wg.Go(func() {
			defer func() { <-l.slots }()
			l.handshake(ctx, raw, accepted)
		})
	}
}

// handshake takes one connection through both layers and, if it passes,
// waits for Accept to take it. Any failure closes the connection without a
// word: a peer that did not prove a key gets nothing, not even the server's.
func (l *channelListener) handshake(ctx context.Context, raw net.Conn, accepted time.Time) {
	hctx, cancel := context.WithDeadline(ctx, accepted.Add(l.budget))
	defer cancel()
	conn, peer, err := l.verify(hctx, raw)
	if err != nil {
		_ = raw.Close()
		l.refused(err)
		return
	}
	select {
	case l.ready <- &channelConn{Conn: conn, peer: channelPeer{key: peer}}:
	case <-ctx.Done():
		_ = raw.Close()
	}
}

// verify runs TLS and then the check under ctx, and returns the TLS
// connection - cleared of the deadline, which from here on is the HTTP
// server's to set - with the device key it proved.
func (l *channelListener) verify(ctx context.Context, raw net.Conn) (*tls.Conn, ed25519.PublicKey, error) {
	tc := tls.Server(raw, l.tls)
	if err := tc.HandshakeContext(ctx); err != nil {
		return nil, nil, &tlsStageError{err}
	}
	state := tc.ConnectionState()
	binding, err := state.ExportKeyingMaterial(eidolon.ExporterLabel, nil, eidolon.BindingSize)
	if err != nil {
		return nil, nil, &tlsStageError{err}
	}
	peer, err := eidolon.Respond(ctx, tc, binding, l.key)
	if err != nil {
		return nil, nil, err
	}
	if err := tc.SetDeadline(time.Time{}); err != nil {
		return nil, nil, err
	}
	return tc, peer, nil
}

// tlsStageError marks a failure before the check began.
type tlsStageError struct{ err error }

func (e *tlsStageError) Error() string { return "tls: " + e.err.Error() }
func (e *tlsStageError) Unwrap() error { return e.err }

// refused logs a connection that did not pass, by how loud it deserves to be.
//
// A refused CHECK is somebody who completed TLS and then failed to prove a key
// - a client of another protocol, a bug on the device, or a relay - and is
// worth a line. A connection that never finished TLS, or went quiet, is what
// every port on a network collects; it stays out of the log unless asked for.
// Neither line carries a key or an address: the error names the reason only.
func (l *channelListener) refused(err error) {
	var stage *tlsStageError
	switch {
	case errors.Is(err, eidolon.ErrInvalidLen), errors.Is(err, eidolon.ErrInvalidCert), errors.Is(err, eidolon.ErrSigMismatch):
		l.logger.Info("channel check refused", "entry", l.entry, "reason", err.Error())
	case errors.As(err, &stage):
		l.logger.Debug("channel not established", "entry", l.entry, "stage", "tls", "err", err)
	default:
		l.logger.Debug("channel not established", "entry", l.entry, "stage", "check", "err", err)
	}
}
