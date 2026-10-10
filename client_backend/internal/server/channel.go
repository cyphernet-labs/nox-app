package server

import (
	"container/list"
	"context"
	"crypto/ed25519"
	"crypto/tls"
	"encoding/base64"
	"errors"
	"log/slog"
	"net"
	"net/netip"
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
	// they are, per entry. One costs a goroutine and a TLS state, so 256 of
	// them are a few megabytes at most, and a legitimate burst - every device
	// of one person reconnecting after a restart - is a small fraction of it.
	// Reaching it never closes the door: the connection that has waited
	// longest is cut to make room for the new one.
	maxPendingChannels = 256
	// maxPendingPerSource bounds the handshakes one source has under way at
	// once, so that no single host fills the entry by itself. A source is an
	// IPv4 address or an IPv6 /64 (sourceOf). The devices behind one home
	// router share an address, and each of their handshakes is over in well
	// under a second: eight at once leaves them room to spare. Reaching it
	// never closes the door to the source either: its next connection cuts
	// the oldest of the eight, and a device of the house, through in well
	// under a second, is almost never the one that has waited longest.
	maxPendingPerSource = 8
	// firstByteTimeout is how long a connection from anywhere but loopback may
	// say nothing at all. TLS opens with the client's hello, sent right behind
	// the TCP handshake, so a device's first byte is there at once; a peer
	// still silent after this is only holding a place. Loopback - tor - has
	// the whole budget: a Tor client's hello crosses its circuit only after
	// tor has connected here.
	firstByteTimeout = 5 * time.Second
	// shedLogInterval spaces the warnings about the handshakes an entry cut: a
	// flood must not flood the log as well.
	shedLogInterval = time.Minute
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

// channelConnKey marks a request with the connection it arrived on.
type channelConnKey struct{}

// withChannelPeer is the ConnContext of both entries: every request on a
// connection carries that connection, and with it the key the connection
// proved. The mark is on the SOCKET, never derived from anything a request
// says - the same reasoning that put the onion mark there.
func withChannelPeer(ctx context.Context, c net.Conn) context.Context {
	if cc, ok := c.(*channelConn); ok {
		return context.WithValue(ctx, channelConnKey{}, cc)
	}
	return ctx
}

// channelPeerFrom reads the proved key of the request's connection. false
// means the connection never went through the channel listener - which Run
// never lets happen, and which every caller treats as a stranger.
func channelPeerFrom(ctx context.Context) (channelPeer, bool) {
	cc, ok := channelConnFrom(ctx)
	if !ok {
		return channelPeer{}, false
	}
	return cc.peer, true
}

// channelConnFrom reads the connection the request arrived on, for the one
// thing a handler does to it besides HTTP: a file transfer registers it, so
// that revoking its device can cut it (files.go). false means what it means
// for channelPeerFrom.
func channelConnFrom(ctx context.Context) (*channelConn, bool) {
	cc, ok := ctx.Value(channelConnKey{}).(*channelConn)
	return cc, ok
}

// channelConn is a connection that passed both layers: the TLS session it
// runs in, and the device key it proved there.
type channelConn struct {
	net.Conn
	// raw is the connection under TLS: the TCP socket, or tor's stream on the
	// onion entry. cut closes it.
	raw  net.Conn
	peer channelPeer
}

// cut ends the connection at once, from any goroutine: a handler reading or
// writing it - in the middle of a body - fails there and then. It closes the
// connection under TLS rather than TLS itself, because closing TLS first
// writes a goodbye, and with a peer that stopped reading that write can wait
// for seconds - for a revoked device, which is owed no goodbye at all.
func (c *channelConn) cut() {
	_ = c.raw.Close()
}

// channelListener is the channel's front door (contract §1, research R5). It
// takes connections off the listener it wraps and hands http.Server only the
// ones that passed both layers - TLS 1.3, then the channel check - so no
// handler, not even a 404, ever answers a connection that has not proved a
// device key. The HTTP server itself does no TLS: it is given connections
// that already have it.
//
// Each connection proves itself on a goroutine of its own, under ONE deadline
// counted from the moment it was accepted. The loop that accepts never waits,
// neither for a handshake nor for room for one, and never turns a newcomer
// away: a door that stops opening while strangers lean on it is exactly the
// outage a flood is after. What strangers can hold is bounded instead, and
// room is made by cutting whoever has waited longest:
//
//   - a source has at most maxPendingPerSource handshakes under way, and its
//     next connection cuts the oldest of them. A device is through in well
//     under a second, so the one cut is nearly always a peer that is saying
//     nothing - and a flood from one source competes only with itself, never
//     pushing another source's handshake out of the entry;
//   - a connection from anywhere but loopback that sends nothing within
//     firstByteTimeout is cut, long before its budget would cut it;
//   - past maxPendingChannels in all, the connection that has waited longest
//     is cut to make room, for the same reason as within a source.
//
// A source's share cuts its own oldest rather than refusing its newcomer
// because a source is often a household: the devices behind one router, or on
// one IPv6 /64. A refusal would hand the source to whoever holds its places -
// a peer there opening a connection a second and sending one byte on each
// holds all eight - and every device of the house would stay out for as long
// as it kept at it.
//
// Loopback is held to neither of the first two. tor runs on this machine and
// every connection that comes through it - every device away from home -
// arrives from there, so a share for loopback would be one share for all of
// them, and a first-byte limit would cut hellos still crossing a circuit.
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
	// cancel ends every handshake and delivery; closed tells Accept.
	cancel    context.CancelFunc
	closed    chan struct{}
	closeOnce sync.Once
	// wg tracks the accept loop and every handshake, so Close returns only
	// once none of them can touch a connection any more.
	wg sync.WaitGroup

	// mu guards the handshakes under way, the limits they are held to and the
	// count of what was shed. Infrastructure, the same class as the
	// connection registry: it orders the accept loop against handshakes
	// leaving, and nothing the wire can see lives under it (CLAUDE.md
	// invariant 7 names it). The limits are set from the constants above and
	// sit under it too, so a test can shrink them while the loop runs.
	mu           sync.Mutex
	maxPending   int
	maxPerSource int
	firstByte    time.Duration
	shedEvery    time.Duration
	// pending holds the handshakes under way, oldest first; bySource counts
	// them per source, loopback left out, and is what says a source is at its
	// share - pending then says which of its handshakes is the oldest.
	pending  *list.List
	bySource map[string]int
	// shed is what was cut since the last warning, which went out at
	// shedLogged; shedFlush, while set, is the timer that sends the next one.
	shed       shedCounts
	shedLogged time.Time
	shedFlush  *time.Timer
}

// pendingChannel is one connection in TLS or the check.
type pendingChannel struct {
	conn     net.Conn
	accepted time.Time
	source   string
	// loopback is tor's: held to no share and to no first-byte limit.
	loopback bool
	// firstByteBy is when a connection that has sent nothing is cut; zero
	// for loopback.
	firstByteBy time.Time
	// elem is its place among the handshakes under way, nil once it has
	// left - or was cut to make room.
	elem *list.Element
}

// shedCounts is what an entry cut between two warnings: inSource handshakes
// cut for a newer connection from their own source, which was at its share,
// and evicted ones cut because every place in the entry was taken.
type shedCounts struct {
	inSource int
	evicted  int
}

// newChannelListener starts taking connections off raw at once; Accept hands
// out the ones that pass.
func (s *Server) newChannelListener(raw net.Listener, cfg *tls.Config, key ed25519.PrivateKey, budget time.Duration, entry string) *channelListener {
	ctx, cancel := context.WithCancel(context.Background())
	l := &channelListener{
		raw:          raw,
		tls:          cfg,
		key:          key,
		budget:       budget,
		logger:       s.logger.With("component", "channel"),
		entry:        entry,
		ready:        make(chan *channelConn),
		cancel:       cancel,
		closed:       make(chan struct{}),
		maxPending:   maxPendingChannels,
		maxPerSource: maxPendingPerSource,
		firstByte:    firstByteTimeout,
		shedEvery:    shedLogInterval,
		pending:      list.New(),
		bySource:     make(map[string]int),
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
// until none of them can touch a connection. A warning still waiting for its
// minute goes out now rather than never.
func (l *channelListener) Close() error {
	l.cancel()
	err := l.raw.Close()
	l.markClosed()
	l.wg.Wait()
	l.mu.Lock()
	waiting := l.shedFlush != nil && l.shedFlush.Stop()
	l.mu.Unlock()
	if waiting {
		l.warnShed()
	}
	return err
}

// Addr is the address of the listener it wraps.
func (l *channelListener) Addr() net.Addr {
	return l.raw.Addr()
}

func (l *channelListener) markClosed() {
	l.closeOnce.Do(func() { close(l.closed) })
}

// acceptLoop takes connections off raw for as long as the listener lives. It
// waits on nothing but Accept: admit gives every connection a handshake at
// once and decides which ones make room for it, and the connections it cuts
// are closed right here - a cut one's handshake then ends on its closed
// socket.
//
// A failed Accept other than a closed listener is retried with a growing
// pause, the way net/http's own loop does: running out of file descriptors is
// a passing condition, and giving up on it would take the server down with it.
// If raw itself goes away, Accept says so and the HTTP server stops.
func (l *channelListener) acceptLoop(ctx context.Context) {
	defer l.markClosed()
	var pause time.Duration
	for {
		raw, err := l.raw.Accept()
		if err != nil {
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
		p, cut := l.admit(raw, time.Now())
		for _, c := range cut {
			_ = c.Close()
		}
		l.wg.Go(func() { l.handshake(ctx, p) })
	}
}

// admit registers a connection the moment it is accepted. Every connection is
// taken: room for it is made first within its source, then within the entry.
// A source at its share gives up the oldest of its own handshakes; with every
// place in the entry taken, the oldest of all leave. The ones that leave come
// back for the caller to close, which ends their handshakes: nothing is
// closed under mu.
//
// Within the source first, so that one source's flood never reaches the
// entry-wide cut, which would push out other sources' handshakes; a source
// that made room for itself has freed the place it takes.
func (l *channelListener) admit(conn net.Conn, accepted time.Time) (*pendingChannel, []net.Conn) {
	source, loopback := sourceOf(conn.RemoteAddr())
	l.mu.Lock()
	defer l.mu.Unlock()
	var cut []net.Conn
	var shed shedCounts
	// A loop rather than one cut, like the entry-wide one below: a limit
	// shrunk while handshakes were held (see mu) still comes out at the limit.
	for !loopback && l.bySource[source] > 0 && l.bySource[source] >= l.maxPerSource {
		oldest := l.oldestFromLocked(source)
		if oldest == nil {
			// Unreachable while the count matches pending; never loop on it.
			break
		}
		l.forgetLocked(oldest)
		cut = append(cut, oldest.conn)
		shed.inSource++
	}
	for l.pending.Len() > 0 && l.pending.Len() >= l.maxPending {
		oldest := l.pending.Front().Value.(*pendingChannel)
		l.forgetLocked(oldest)
		cut = append(cut, oldest.conn)
		shed.evicted++
	}
	if shed != (shedCounts{}) {
		l.shedLocked(shed)
	}
	p := &pendingChannel{conn: conn, accepted: accepted, source: source, loopback: loopback}
	if !loopback {
		p.firstByteBy = accepted.Add(min(l.firstByte, l.budget))
		l.bySource[source]++
	}
	p.elem = l.pending.PushBack(p)
	return p, cut
}

// oldestFromLocked is the handshake from source that has waited longest: the
// first of that source's in pending, which is kept oldest first. A walk of at
// most maxPendingChannels, made only for a source already at its share. mu
// must be held.
func (l *channelListener) oldestFromLocked(source string) *pendingChannel {
	for e := l.pending.Front(); e != nil; e = e.Next() {
		if p := e.Value.(*pendingChannel); !p.loopback && p.source == source {
			return p
		}
	}
	return nil
}

// leave takes p out of the handshakes under way once its own is over, and
// reports whether it was still there. false means it was cut to make room: its
// connection is closed, or about to be, whatever the handshake made of it.
func (l *channelListener) leave(p *pendingChannel) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	if p.elem == nil {
		return false
	}
	l.forgetLocked(p)
	return true
}

// forgetLocked takes p out of the handshakes under way. A source left with
// none drops out of the count altogether, so the map does not grow with every
// address that ever knocked. mu must be held.
func (l *channelListener) forgetLocked(p *pendingChannel) {
	l.pending.Remove(p.elem)
	p.elem = nil
	if p.loopback {
		return
	}
	l.bySource[p.source]--
	if l.bySource[p.source] <= 0 {
		delete(l.bySource, p.source)
	}
}

// sourceOf names the source a connection counts against, and reports whether
// it came from loopback, which counts against none.
//
// An IPv4 address is a source of its own, in its IPv4-mapped IPv6 form too,
// which is how a dual-stack socket reports it. IPv6 counts by its /64: one
// host is routinely handed a whole /64 and may speak from any address in it.
// An address that is not IP at all is one source shared by all of its kind,
// and held to a share like any other: only loopback is known to be tor.
func sourceOf(addr net.Addr) (source string, loopback bool) {
	var ip netip.Addr
	switch a := addr.(type) {
	case nil:
	case *net.TCPAddr:
		ip = a.AddrPort().Addr()
	default:
		if ap, err := netip.ParseAddrPort(a.String()); err == nil {
			ip = ap.Addr()
		}
	}
	ip = ip.Unmap().WithZone("")
	switch {
	case !ip.IsValid():
		return "", false
	case ip.IsLoopback():
		return ip.String(), true
	case ip.Is4():
		return ip.String(), false
	default:
		return netip.PrefixFrom(ip, 64).Masked().String(), false
	}
}

// handshake takes one connection through both layers and, if it passes,
// waits for Accept to take it. Any failure closes the connection without a
// word: a peer that did not prove a key gets nothing, not even the server's.
func (l *channelListener) handshake(ctx context.Context, p *pendingChannel) {
	budget := p.accepted.Add(l.budget)
	hctx, cancel := context.WithDeadline(ctx, budget)
	defer cancel()
	conn := p.conn
	if !p.loopback {
		// Off loopback the first byte has a shorter deadline of its own, and
		// TLS runs over the wrapper that lifts it once that byte is in.
		_ = conn.SetReadDeadline(p.firstByteBy)
		conn = &firstByteConn{Conn: conn, budget: budget}
	}
	tc, peer, err := l.verify(hctx, conn)
	// Passed or not, it is no longer a handshake under way. One cut to make
	// room meanwhile is not handed out even if it passed: the socket under it
	// is closed.
	if !l.leave(p) {
		_ = p.conn.Close()
		return
	}
	if err != nil {
		_ = p.conn.Close()
		l.refused(err)
		return
	}
	select {
	case l.ready <- &channelConn{Conn: tc, raw: p.conn, peer: channelPeer{key: peer}}:
	case <-ctx.Done():
		_ = p.conn.Close()
	}
}

// firstByteConn is a connection from anywhere but loopback that has not said
// anything yet. handshake holds its reads to the first-byte deadline, and the
// first byte to arrive moves that out to the whole budget; from then on it is
// the socket and nothing more. Deadlines set from above - the check binding
// its own, the channel clearing them once passed, the HTTP server after it -
// go straight through.
//
// started needs no lock: tls.Conn never reads from two goroutines at once,
// and everything above it reads through it.
type firstByteConn struct {
	net.Conn
	budget  time.Time
	started bool
}

func (c *firstByteConn) Read(b []byte) (int, error) {
	n, err := c.Conn.Read(b)
	if n > 0 && !c.started {
		c.started = true
		_ = c.Conn.SetReadDeadline(c.budget)
	}
	return n, err
}

// verify runs TLS and then the check under ctx, and returns the TLS
// connection - cleared of the deadline, which from here on is the HTTP
// server's to set - with the device key it proved.
func (l *channelListener) verify(ctx context.Context, conn net.Conn) (*tls.Conn, ed25519.PublicKey, error) {
	tc := tls.Server(conn, l.tls)
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

// shedLocked counts handshakes cut, and sees to it that a warning carries
// them: at once if the last one is a minute old, else when its minute is up.
// So there is one line a minute at most, each with everything counted since
// the one before. mu must be held.
func (l *channelListener) shedLocked(c shedCounts) {
	l.shed.inSource += c.inSource
	l.shed.evicted += c.evicted
	if l.shedFlush == nil {
		l.shedFlush = time.AfterFunc(time.Until(l.shedLogged.Add(l.shedEvery)), l.warnShed)
	}
}

// warnShed writes the warning shedLocked asked for. Like every other line
// here it carries no address: the counts say how hard the door is pushed, and
// that is what an operator can act on.
func (l *channelListener) warnShed() {
	l.mu.Lock()
	c := l.shed
	l.shed = shedCounts{}
	l.shedLogged = time.Now()
	l.shedFlush = nil
	l.mu.Unlock()
	if c == (shedCounts{}) {
		return
	}
	l.logger.Warn("channel entry shedding connections", "entry", l.entry,
		"evicted_in_source", c.inSource, "evicted", c.evicted)
}
