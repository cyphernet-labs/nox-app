package tor

import (
	"context"
	"crypto/ed25519"
	"encoding/base64"
	"errors"
	"log/slog"
	"slices"
	"strconv"
	"strings"
	"sync/atomic"
	"time"
)

// KeysFunc reads the active access keys - public x25519 keys, base64 - and the
// moment the earliest one-time key among them stops working (zero when none
// does). The store answers it; the supervisor never touches the database.
type KeysFunc func(ctx context.Context, now time.Time) (keys []string, nextExpiry time.Time, err error)

// Config is what the server hands the supervisor at startup.
type Config struct {
	// Bin is the explicit -tor-bin, or empty to search.
	Bin string
	// DataDir is tor's own state directory.
	DataDir string
	// Seed is the onion service's private seed. The only copy outside the
	// database, and it stays in this package.
	Seed []byte
	// Target is the loopback address of the server's onion entry.
	Target string
	// Keys reads the active access keys.
	Keys KeysFunc
	// OnOffered is called, from the supervisor's goroutine, whenever Offered
	// changes - the address watcher needs to know at once.
	OnOffered func()
	Logger    *slog.Logger
}

// Supervisor owns one tor process: it finds and starts it, publishes the onion
// service while there are access keys and only then, republishes when the keys
// change, and keeps a snapshot of all of it for readers.
//
// Everything mutable belongs to the Run goroutine. Other goroutines talk to it
// through KeysChanged and read it through Status, Offered and ReadyForInvite -
// atomics and an immutable snapshot, no lock.
type Supervisor struct {
	cfg      Config
	enabled  bool
	pub      ed25519.PublicKey
	address  string
	expanded []byte
	launcher launcher

	kick    chan struct{}
	status  atomic.Pointer[Status]
	offered atomic.Bool
	ready   atomic.Bool

	// Owned by Run.
	binaryOK      bool
	keyCount      int
	serviceUp     bool
	publishedKeys []string
	nextExpiry    time.Time
	// pendingCut asks serve to close the service's circuits after cutDelay:
	// a key left the set, and tor keeps letting a client in through a circuit
	// it already holds (research, decision 15).
	pendingCut bool

	// Timing, overridden by tests.
	now          func() time.Time
	coalesce     time.Duration
	cutDelay     time.Duration
	recheck      time.Duration
	verdictEvery time.Duration
	backoffMin   time.Duration
	backoffMax   time.Duration
	stableAfter  time.Duration
	// retryHook, when set, sees every pause chosen before a restart. Tests
	// only: the growth of the pause is the property, and it is gone from the
	// snapshot the moment the next start begins.
	retryHook func(time.Duration)
}

// New builds an enabled supervisor. It does nothing until Run.
func New(cfg Config) (*Supervisor, error) {
	pub, err := PublicKey(cfg.Seed)
	if err != nil {
		return nil, err
	}
	addr, err := Address(pub)
	if err != nil {
		return nil, err
	}
	expanded, err := ExpandedKey(cfg.Seed)
	if err != nil {
		return nil, err
	}
	if cfg.Logger == nil {
		cfg.Logger = slog.New(slog.DiscardHandler)
	}
	s := &Supervisor{
		cfg:          cfg,
		enabled:      true,
		pub:          pub,
		address:      addr,
		expanded:     expanded,
		launcher:     procLauncher{bin: cfg.Bin, dataDir: cfg.DataDir},
		kick:         make(chan struct{}, 1),
		now:          time.Now,
		coalesce:     time.Second,
		cutDelay:     5 * time.Second,
		recheck:      5 * time.Minute,
		verdictEvery: 10 * time.Minute,
		backoffMin:   time.Second,
		backoffMax:   5 * time.Minute,
		stableAfter:  time.Minute,
	}
	s.status.Store(&Status{Enabled: true, Phase: PhaseStarting, Verdict: VerdictUnknown, Publication: PublicationTorDown})
	return s, nil
}

// Disabled is the supervisor of a server started with -tor=false: every method
// answers "no Tor here", so callers need no nil checks, and Run returns at once.
func Disabled() *Supervisor {
	s := &Supervisor{kick: make(chan struct{}, 1)}
	s.status.Store(&Status{Phase: PhaseDisabled, Verdict: VerdictUnknown, Publication: PublicationTorDown})
	return s
}

// Status returns the current snapshot.
func (s *Supervisor) Status() Status { return *s.status.Load() }

// Offered reports whether the server offers its onion address to devices: Tor
// is on, the last check found a usable tor, and at least one access key
// exists. The network's verdict does not enter into it - an outdated tor that
// still runs is shown as such, not hidden - and neither does a passing crash,
// which is why the address list does not flap on every restart of tor.
func (s *Supervisor) Offered() bool { return s.offered.Load() }

// ReadyForInvite reports whether an invite carrying the onion address would
// work now: tor running and fully connected.
func (s *Supervisor) ReadyForInvite() bool { return s.ready.Load() }

// OnionPublicKey is the service's public key, or nil when Tor is disabled.
func (s *Supervisor) OnionPublicKey() ed25519.PublicKey { return s.pub }

// Address is the 56-character onion address without ".onion", or empty when
// Tor is disabled. Never logged and never shown on a page.
func (s *Supervisor) Address() string { return s.address }

// KeysChanged tells the supervisor the set of access keys may have changed.
// Never blocks: one pending signal stands for any number of changes.
func (s *Supervisor) KeysChanged() {
	select {
	case s.kick <- struct{}{}:
	default:
	}
}

// Run supervises tor until ctx is cancelled. It returns nothing: no failure of
// tor may take the server down with it (FR-007) - the direct path keeps
// working, and the reason is in the snapshot and the log.
func (s *Supervisor) Run(ctx context.Context) {
	if !s.enabled {
		return
	}
	backoff := s.backoffMin
	for ctx.Err() == nil {
		s.refreshKeyCount(ctx)
		path, v, err := s.launcher.locate(ctx)
		if err != nil {
			s.binaryOK = false
			s.updateOffered()
			s.ready.Store(false)
			phase, msg := PhaseBinaryMissing, "tor not found - install tor 0.4.9 or newer"
			if errors.Is(err, errTooOld) {
				phase, msg = PhaseBinaryTooOld, "tor "+v.String()+" is too old - install 0.4.9 or newer"
			} else if !errors.Is(err, ErrNotFound) {
				msg = "tor could not be checked: " + err.Error()
			}
			s.update(func(st *Status) {
				st.Phase, st.Version, st.Publication, st.Bootstrap = phase, versionOrEmpty(v), PublicationTorDown, 0
				st.LastError = Scrub(msg)
			})
			s.cfg.Logger.Warn("tor unavailable, serving the direct path only", "reason", Scrub(msg))
			if !s.wait(ctx, s.recheck) {
				return
			}
			continue
		}
		s.binaryOK = true
		s.updateOffered()
		s.update(func(st *Status) {
			st.Phase, st.Version, st.RetryIn = PhaseStarting, v.String(), 0
		})
		s.cfg.Logger.Info("starting tor", "version", v.String())

		started := s.now()
		run, err := s.launcher.start(ctx, path)
		if err == nil {
			err = s.serve(ctx, run)
			run.stop()
		}
		s.ready.Store(false)
		s.serviceUp = false
		s.publishedKeys = nil
		if ctx.Err() != nil {
			return
		}
		if s.now().Sub(started) > s.stableAfter {
			backoff = s.backoffMin
		}
		msg := "tor stopped"
		if err != nil {
			msg = "tor stopped: " + err.Error()
		}
		s.update(func(st *Status) {
			st.Phase, st.Publication, st.Bootstrap, st.RetryIn = PhaseWaitingRetry, PublicationTorDown, 0, backoff
			st.LastError = Scrub(msg)
		})
		s.cfg.Logger.Warn("tor stopped, restarting", "reason", Scrub(msg), "retry_in", backoff.String())
		if s.retryHook != nil {
			s.retryHook(backoff)
		}
		if !s.wait(ctx, backoff) {
			return
		}
		backoff = min(2*backoff, s.backoffMax)
	}
}

// serve runs one tor process until it ends or ctx is cancelled.
func (s *Supervisor) serve(ctx context.Context, run running) error {
	c := run.ctl()
	if _, err := s.command(ctx, c, "SETEVENTS STATUS_CLIENT STATUS_GENERAL HS_DESC"); err != nil {
		return err
	}
	s.update(func(st *Status) { st.Phase = PhaseConnecting })
	s.refreshBootstrap(ctx, c)
	s.refreshVerdict(ctx, c)
	if err := s.republish(ctx, c); err != nil {
		return err
	}

	verdictTick := time.NewTicker(s.verdictEvery)
	defer verdictTick.Stop()
	var coalesce, cut, expiry <-chan time.Time
	var expiryTimer *time.Timer
	resetExpiry := func() {
		if expiryTimer != nil {
			expiryTimer.Stop()
			expiryTimer, expiry = nil, nil
		}
		if next := s.nextExpiry; !next.IsZero() {
			expiryTimer = time.NewTimer(max(next.Sub(s.now()), 0))
			expiry = expiryTimer.C
		}
	}
	resetExpiry()
	defer func() {
		if expiryTimer != nil {
			expiryTimer.Stop()
		}
	}()

	for {
		if s.pendingCut {
			s.pendingCut = false
			cut = time.After(s.cutDelay)
		}
		select {
		case <-ctx.Done():
			return nil
		case <-run.exited():
			return errors.New("tor exited")
		case <-c.Done():
			return ErrClosed
		case line, ok := <-run.lines():
			if ok {
				s.onLogLine(line)
			}
		case ev, ok := <-c.Events():
			if ok {
				s.onEvent(ctx, c, ev)
			}
		case <-s.kick:
			if coalesce == nil {
				coalesce = time.After(s.coalesce)
			}
		case <-coalesce:
			coalesce = nil
			if err := s.republish(ctx, c); err != nil {
				return err
			}
			resetExpiry()
		case <-expiry:
			expiry, expiryTimer = nil, nil
			if err := s.republish(ctx, c); err != nil {
				return err
			}
			resetExpiry()
		case <-cut:
			cut = nil
			if err := s.closeCircuits(ctx, c); err != nil {
				return err
			}
		case <-verdictTick.C:
			s.refreshVerdict(ctx, c)
		}
	}
}

// republish brings the onion service in line with the current set of access
// keys.
//
// Never published with an empty set: ADD_ONION without a single ClientAuthV3
// creates a PUBLIC service, so "no keys" and "no service" have to be the same
// thing by construction (FR-009). An unchanged set publishes nothing - a
// re-registered key must not cut every onion connection for no reason. A set
// that lost any key - a set difference, so a swap counts - schedules the
// circuit cut.
func (s *Supervisor) republish(ctx context.Context, c controller) error {
	keys, next, err := s.cfg.Keys(ctx, s.now())
	if err != nil {
		s.cfg.Logger.Error("read the onion access keys", "err", err)
		s.setError("the access keys could not be read")
		return nil
	}
	s.nextExpiry = next
	clientKeys := make([]string, 0, len(keys))
	for _, k := range keys {
		raw, err := ParseAccessKey(k)
		if err != nil {
			continue
		}
		ck, err := ClientAuthKey(raw)
		if err != nil {
			continue
		}
		clientKeys = append(clientKeys, ck)
	}
	slices.Sort(clientKeys)
	clientKeys = slices.Compact(clientKeys)
	s.keyCount = len(clientKeys)
	s.updateOffered()

	if s.serviceUp && slices.Equal(clientKeys, s.publishedKeys) {
		return nil
	}
	removed := false
	for _, k := range s.publishedKeys {
		if !slices.Contains(clientKeys, k) {
			removed = true
			break
		}
	}
	if s.serviceUp {
		if _, err := s.command(ctx, c, "DEL_ONION "+s.address); err != nil {
			var refused *CommandError
			if !errors.As(err, &refused) {
				return err
			}
			// 552: tor does not know the service any more. The goal - no
			// service - holds either way.
		}
		s.serviceUp = false
	}
	if len(clientKeys) == 0 {
		s.publishedKeys = nil
		s.update(func(st *Status) { st.Publication = PublicationNoKeys })
		s.pendingCut = s.pendingCut || removed
		return nil
	}

	var line strings.Builder
	line.WriteString("ADD_ONION ED25519-V3:")
	line.WriteString(base64.StdEncoding.EncodeToString(s.expanded))
	line.WriteString(" Flags=V3Auth Port=")
	line.WriteString(strconv.Itoa(OnionPort))
	line.WriteString(",")
	line.WriteString(s.cfg.Target)
	for _, k := range clientKeys {
		line.WriteString(" ClientAuthV3=")
		line.WriteString(k)
	}
	if _, err := s.command(ctx, c, line.String()); err != nil {
		var refused *CommandError
		if errors.As(err, &refused) {
			// The error names the verb only (control.go), so it is safe to
			// keep; the command line itself is never repeated anywhere.
			s.setError(err.Error())
			s.update(func(st *Status) { st.Publication = PublicationTorDown })
			s.cfg.Logger.Error("tor refused to publish the onion service", "err", err)
			return nil
		}
		return err
	}
	s.serviceUp = true
	s.publishedKeys = clientKeys
	s.update(func(st *Status) { st.Publication = PublicationPublishing })
	s.pendingCut = s.pendingCut || removed
	return nil
}

// closeCircuits closes every rendezvous circuit of this onion service. A key
// taken out of the list does not, by itself, stop a client that already holds
// a circuit: tor reuses it for new streams (measured - research, decision 15).
// Every onion connection drops and the devices that still hold a key
// reconnect; rendezvous circuits are anonymous, so there is no picking the
// right one.
func (s *Supervisor) closeCircuits(ctx context.Context, c controller) error {
	status, err := s.getInfo(ctx, c, "circuit-status")
	if err != nil {
		var refused *CommandError
		if errors.As(err, &refused) {
			return nil
		}
		return err
	}
	closed := 0
	for _, line := range strings.Split(status, "\n") {
		f := strings.Fields(line)
		if len(f) == 0 || !slices.Contains(f, "PURPOSE=HS_SERVICE_REND") || !slices.Contains(f, "REND_QUERY="+s.address) {
			continue
		}
		if _, err := s.command(ctx, c, "CLOSECIRCUIT "+f[0]); err != nil {
			var refused *CommandError
			if errors.As(err, &refused) {
				continue // closed on its own meanwhile
			}
			return err
		}
		closed++
	}
	if closed > 0 {
		s.cfg.Logger.Info("closed onion circuits after an access key was removed", "circuits", closed)
	}
	return nil
}

// onEvent handles one asynchronous event.
func (s *Supervisor) onEvent(ctx context.Context, c controller, ev string) {
	f := strings.Fields(ev)
	if len(f) < 2 {
		return
	}
	switch f[0] {
	case "STATUS_CLIENT":
		if len(f) < 3 {
			return
		}
		switch f[2] {
		case "BOOTSTRAP":
			if p, err := strconv.Atoi(eventValue(ev, "PROGRESS")); err == nil {
				s.setBootstrap(p)
			}
			if f[1] == "WARN" {
				s.setError("connecting to the Tor network: " + eventValue(ev, "WARNING") + " (" + eventValue(ev, "REASON") + ")")
			}
		case "CLOCK_SKEW":
			s.setError("this machine's clock is off - tor cannot connect until it is set right")
		}
	case "STATUS_GENERAL":
		s.refreshVerdict(ctx, c)
	case "HS_DESC":
		// HS_DESC UPLOADED <address> <auth> <hsdir> ...
		if len(f) >= 3 && f[1] == "UPLOADED" && f[2] == s.address && s.serviceUp {
			s.update(func(st *Status) { st.Publication = PublicationPublished })
		}
	}
}

// onLogLine forwards tor's own log, scrubbed, at the level it deserves.
func (s *Supervisor) onLogLine(raw string) {
	l := ParseLogLine(raw)
	switch l.Level {
	case "warn", "err":
		s.cfg.Logger.Warn("tor", "msg", l.Message)
		if strings.Contains(strings.ToLower(l.Message), "required protocol") {
			s.update(func(st *Status) {
				st.Verdict = VerdictObsolete
				st.LastError = l.Message
			})
		}
	case "notice":
		if strings.HasPrefix(l.Message, "Bootstrapped") {
			s.cfg.Logger.Info("tor", "msg", l.Message)
		}
	}
}

func (s *Supervisor) refreshBootstrap(ctx context.Context, c controller) {
	v, err := s.getInfo(ctx, c, "status/bootstrap-phase")
	if err != nil {
		return
	}
	if p, err := strconv.Atoi(eventValue(v, "PROGRESS")); err == nil {
		s.setBootstrap(p)
	}
}

func (s *Supervisor) refreshVerdict(ctx context.Context, c controller) {
	v, err := s.getInfo(ctx, c, "status/version/current")
	if err != nil {
		return
	}
	verdict := verdictOf(strings.TrimSpace(v))
	prev := s.Status().Verdict
	s.update(func(st *Status) { st.Verdict = verdict })
	if verdict != prev && (verdict == VerdictOutdated || verdict == VerdictObsolete) {
		s.cfg.Logger.Warn("the Tor network says this tor needs updating", "verdict", string(verdict))
	}
}

func (s *Supervisor) setBootstrap(p int) {
	ready := p >= 100
	s.ready.Store(ready)
	s.update(func(st *Status) {
		st.Bootstrap = min(max(p, 0), 100)
		if ready {
			st.Phase = PhaseRunning
		} else {
			st.Phase = PhaseConnecting
		}
	})
}

// refreshKeyCount reads how many keys exist, so Offered stays true across a
// restart of tor and becomes true while tor is still starting.
func (s *Supervisor) refreshKeyCount(ctx context.Context) {
	keys, next, err := s.cfg.Keys(ctx, s.now())
	if err != nil {
		return
	}
	s.keyCount = len(keys)
	s.nextExpiry = next
	s.updateOffered()
}

func (s *Supervisor) updateOffered() {
	o := s.enabled && s.binaryOK && s.keyCount > 0
	if s.offered.Swap(o) != o && s.cfg.OnOffered != nil {
		s.cfg.OnOffered()
	}
}

// wait sleeps for d, still answering KeysChanged so Offered follows the keys
// while tor is down.
func (s *Supervisor) wait(ctx context.Context, d time.Duration) bool {
	t := time.NewTimer(d)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return false
		case <-t.C:
			return true
		case <-s.kick:
			s.refreshKeyCount(ctx)
		}
	}
}

func (s *Supervisor) update(fn func(*Status)) {
	cur := *s.status.Load()
	fn(&cur)
	s.status.Store(&cur)
}

func (s *Supervisor) setError(msg string) {
	s.update(func(st *Status) { st.LastError = Scrub(msg) })
}

func (s *Supervisor) command(ctx context.Context, c controller, line string) ([]string, error) {
	cctx, cancel := context.WithTimeout(ctx, commandTimeout)
	defer cancel()
	return c.Command(cctx, line)
}

func (s *Supervisor) getInfo(ctx context.Context, c controller, key string) (string, error) {
	cctx, cancel := context.WithTimeout(ctx, commandTimeout)
	defer cancel()
	return c.GetInfo(cctx, key)
}

// eventValue reads KEY=value out of an event or GETINFO line; a quoted value
// comes back without its quotes.
func eventValue(line, key string) string {
	i := strings.Index(line, key+"=")
	for i > 0 && line[i-1] != ' ' {
		next := strings.Index(line[i+1:], key+"=")
		if next < 0 {
			return ""
		}
		i += next + 1
	}
	if i < 0 {
		return ""
	}
	rest := line[i+len(key)+1:]
	if strings.HasPrefix(rest, "\"") {
		var b strings.Builder
		for j := 1; j < len(rest); j++ {
			switch rest[j] {
			case '\\':
				if j+1 < len(rest) {
					j++
					b.WriteByte(rest[j])
				}
			case '"':
				return b.String()
			default:
				b.WriteByte(rest[j])
			}
		}
		return b.String()
	}
	if sp := strings.IndexByte(rest, ' '); sp >= 0 {
		return rest[:sp]
	}
	return rest
}

func versionOrEmpty(v Version) string {
	if v == (Version{}) {
		return ""
	}
	return v.String()
}
