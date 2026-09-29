package tor

import (
	"bytes"
	"context"
	"encoding/base64"
	"errors"
	"log/slog"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"
)

// fakeCtl is a scripted control connection: it records every command and
// answers from a table the test can change.
type fakeCtl struct {
	mu       sync.Mutex
	commands []string
	answers  map[string][]string // GETINFO key -> reply lines
	refuse   map[string]int      // verb -> status code to refuse with
	events   chan string
	done     chan struct{}
	closed   bool
}

func newFakeCtl() *fakeCtl {
	return &fakeCtl{
		answers: map[string][]string{
			"version":                {"version=0.4.9.13 (git-3c575400909efe65)", "OK"},
			"status/bootstrap-phase": {`status/bootstrap-phase=NOTICE BOOTSTRAP PROGRESS=100 TAG=done SUMMARY="Done"`, "OK"},
			"status/version/current": {"status/version/current=recommended", "OK"},
			"circuit-status":         {"circuit-status=", "OK"},
		},
		refuse: map[string]int{},
		events: make(chan string, 64),
		done:   make(chan struct{}),
	}
}

func (f *fakeCtl) Command(_ context.Context, line string) ([]string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.commands = append(f.commands, line)
	verb, rest, _ := strings.Cut(line, " ")
	if code, ok := f.refuse[verb]; ok {
		return nil, &CommandError{Verb: verb, Code: code}
	}
	if verb == "GETINFO" {
		if lines, ok := f.answers[rest]; ok {
			return lines, nil
		}
		return nil, &CommandError{Verb: verb, Code: 552}
	}
	return []string{"OK"}, nil
}

func (f *fakeCtl) GetInfo(ctx context.Context, key string) (string, error) {
	lines, err := f.Command(ctx, "GETINFO "+key)
	if err != nil {
		return "", err
	}
	for _, l := range lines {
		if v, ok := strings.CutPrefix(l, key+"="); ok {
			return strings.TrimPrefix(v, "\n"), nil
		}
	}
	return "", errors.New("no value")
}

func (f *fakeCtl) Events() <-chan string { return f.events }
func (f *fakeCtl) Done() <-chan struct{} { return f.done }
func (f *fakeCtl) Close() error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if !f.closed {
		f.closed = true
		close(f.done)
	}
	return nil
}

func (f *fakeCtl) sent() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return slices.Clone(f.commands)
}

func (f *fakeCtl) setAnswer(key string, lines ...string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.answers[key] = lines
}

func (f *fakeCtl) setRefuse(verb string, code int) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.refuse[verb] = code
}

// fakeRun is one fake tor process.
type fakeRun struct {
	c        *fakeCtl
	exit     chan struct{}
	out      chan string
	stopOnce sync.Once
}

func (r *fakeRun) ctl() controller         { return r.c }
func (r *fakeRun) exited() <-chan struct{} { return r.exit }
func (r *fakeRun) lines() <-chan string    { return r.out }
func (r *fakeRun) stop() {
	r.stopOnce.Do(func() {
		_ = r.c.Close()
		select {
		case <-r.exit:
		default:
			close(r.exit)
		}
	})
}

// fakeLauncher hands out fake processes and records how often it started one.
type fakeLauncher struct {
	mu        sync.Mutex
	locateErr error
	version   Version
	startErr  error
	// startLines is what a failing start printed, handed back the way the
	// real launcher hands it back.
	startLines []string
	starts     int
	runs       []*fakeRun
	next       func() *fakeCtl
	// started, when set, sees each run before the supervisor does.
	started func(*fakeRun)
}

func (l *fakeLauncher) locate(context.Context) (string, Version, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return "/fake/tor", l.version, l.locateErr
}

func (l *fakeLauncher) start(context.Context, string) (running, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.starts++
	if l.startErr != nil {
		return nil, &startFailure{err: l.startErr, lines: slices.Clone(l.startLines)}
	}
	c := newFakeCtl()
	if l.next != nil {
		c = l.next()
	}
	r := &fakeRun{c: c, exit: make(chan struct{}), out: make(chan string, 16)}
	l.runs = append(l.runs, r)
	if l.started != nil {
		l.started(r)
	}
	return r, nil
}

func (l *fakeLauncher) run(i int) *fakeRun {
	l.mu.Lock()
	defer l.mu.Unlock()
	if i >= len(l.runs) {
		return nil
	}
	return l.runs[i]
}

func (l *fakeLauncher) startCount() int {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.starts
}

// keySource is a mutable set of active keys standing in for the store.
type keySource struct {
	mu     sync.Mutex
	keys   []string
	expiry time.Time
	reads  int
	// fail is how many of the next reads fail; negative fails every one.
	fail int
}

func (k *keySource) set(keys []string, expiry time.Time) {
	k.mu.Lock()
	defer k.mu.Unlock()
	k.keys, k.expiry = slices.Clone(keys), expiry
}

func (k *keySource) failReads(n int) {
	k.mu.Lock()
	defer k.mu.Unlock()
	k.fail = n
}

func (k *keySource) readCount() int {
	k.mu.Lock()
	defer k.mu.Unlock()
	return k.reads
}

func (k *keySource) read(context.Context, time.Time) ([]string, time.Time, error) {
	k.mu.Lock()
	defer k.mu.Unlock()
	k.reads++
	if k.fail != 0 {
		if k.fail > 0 {
			k.fail--
		}
		return nil, time.Time{}, errors.New("disk I/O error")
	}
	return slices.Clone(k.keys), k.expiry, nil
}

func b64key(b byte) string {
	return base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{b}, 32))
}

func clientKey(t *testing.T, b byte) string {
	t.Helper()
	ck, err := ClientAuthKey(bytes.Repeat([]byte{b}, 32))
	if err != nil {
		t.Fatalf("ClientAuthKey: %v", err)
	}
	return ck
}

// harness is a supervisor running against fakes, with fast timings.
type harness struct {
	t      *testing.T
	s      *Supervisor
	l      *fakeLauncher
	keys   *keySource
	log    *bytes.Buffer
	logMu  *sync.Mutex
	cancel context.CancelFunc
	done   chan struct{}
	offers chan struct{}
}

type lockedWriter struct {
	mu  *sync.Mutex
	buf *bytes.Buffer
}

func (w lockedWriter) Write(p []byte) (int, error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.buf.Write(p)
}

func newHarness(t *testing.T, l *fakeLauncher, keys *keySource, tweak ...func(*Supervisor)) *harness {
	t.Helper()
	logBuf, logMu := &bytes.Buffer{}, &sync.Mutex{}
	offers := make(chan struct{}, 64)
	seed := bytes.Repeat([]byte{7}, 32)
	s, err := New(Config{
		Seed:      seed,
		Target:    "127.0.0.1:4242",
		Keys:      keys.read,
		Logger:    slog.New(slog.NewTextHandler(lockedWriter{logMu, logBuf}, nil)),
		OnOffered: func() { offers <- struct{}{} },
	})
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	s.launcher = l
	s.coalesce = 10 * time.Millisecond
	s.cutDelay = 20 * time.Millisecond
	s.recheck = 50 * time.Millisecond
	s.backoffMin = 10 * time.Millisecond
	s.backoffMax = 40 * time.Millisecond
	s.stableAfter = time.Hour
	for _, fn := range tweak {
		fn(s)
	}
	ctx, cancel := context.WithCancel(context.Background())
	h := &harness{t: t, s: s, l: l, keys: keys, log: logBuf, logMu: logMu, cancel: cancel, done: make(chan struct{}), offers: offers}
	go func() {
		defer close(h.done)
		s.Run(ctx)
	}()
	t.Cleanup(h.stop)
	return h
}

func (h *harness) stop() {
	h.cancel()
	select {
	case <-h.done:
	case <-time.After(5 * time.Second):
		h.t.Fatal("Run did not return after cancellation")
	}
}

func (h *harness) logged() string {
	h.logMu.Lock()
	defer h.logMu.Unlock()
	return h.log.String()
}

func eventually(t *testing.T, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for: %s", what)
}

func countPrefix(cmds []string, prefix string) int {
	n := 0
	for _, c := range cmds {
		if strings.HasPrefix(c, prefix) {
			n++
		}
	}
	return n
}

func TestNoKeysMeansNoServiceAtAll(t *testing.T) {
	l := &fakeLauncher{version: Version{0, 4, 9, 13}}
	h := newHarness(t, l, &keySource{})

	eventually(t, "tor started and asked for its state", func() bool {
		r := l.run(0)
		return r != nil && countPrefix(r.c.sent(), "GETINFO status/version/current") > 0
	})
	eventually(t, "publication says no keys", func() bool {
		return h.s.Status().Publication == PublicationNoKeys
	})
	if n := countPrefix(l.run(0).c.sent(), "ADD_ONION"); n != 0 {
		t.Fatalf("ADD_ONION sent %d times with no keys: that would publish a PUBLIC service", n)
	}
	if h.s.Offered() {
		t.Fatal("Offered with no keys")
	}
}

func TestKeysPublishAnAuthorisedServiceOnPort443(t *testing.T) {
	keys := &keySource{keys: []string{b64key(2), b64key(1)}}
	l := &fakeLauncher{version: Version{0, 4, 9, 13}}
	h := newHarness(t, l, keys)

	var add string
	eventually(t, "ADD_ONION", func() bool {
		r := l.run(0)
		if r == nil {
			return false
		}
		for _, c := range r.c.sent() {
			if strings.HasPrefix(c, "ADD_ONION") {
				add = c
				return true
			}
		}
		return false
	})
	if !strings.HasPrefix(add, "ADD_ONION ED25519-V3:") {
		t.Fatalf("not an ED25519-V3 key: %.30s...", add)
	}
	for _, want := range []string{" Flags=V3Auth ", " Port=443,127.0.0.1:4242", " ClientAuthV3=" + clientKey(t, 1), " ClientAuthV3=" + clientKey(t, 2)} {
		if !strings.Contains(add, want) {
			t.Errorf("ADD_ONION lacks %q", want)
		}
	}
	if strings.Contains(add, "NonAnonymous") || strings.Contains(add, "Detach") {
		t.Errorf("ADD_ONION carries a flag it must not: %s", add)
	}
	eventually(t, "offered", h.s.Offered)
	if got := h.s.Status().Publication; got != PublicationPublishing {
		t.Fatalf("publication = %s before the upload, want publishing", got)
	}

	l.run(0).c.events <- "HS_DESC UPLOADED " + h.s.Address() + " UNKNOWN $AAAA~relay xyz"
	eventually(t, "published after the upload", func() bool {
		return h.s.Status().Publication == PublicationPublished
	})
}

func TestReadinessFollowsTheBootstrap(t *testing.T) {
	l := &fakeLauncher{version: Version{0, 4, 9, 13}, next: func() *fakeCtl {
		c := newFakeCtl()
		c.answers["status/bootstrap-phase"] = []string{"status/bootstrap-phase=NOTICE BOOTSTRAP PROGRESS=45 TAG=loading_descriptors", "OK"}
		return c
	}}
	h := newHarness(t, l, &keySource{})
	eventually(t, "connecting at 45%", func() bool {
		st := h.s.Status()
		return st.Phase == PhaseConnecting && st.Bootstrap == 45
	})
	if h.s.ReadyForInvite() {
		t.Fatal("ready before the bootstrap finished")
	}
	l.run(0).c.events <- `STATUS_CLIENT NOTICE BOOTSTRAP PROGRESS=100 TAG=done SUMMARY="Done"`
	eventually(t, "running", func() bool {
		return h.s.Status().Phase == PhaseRunning && h.s.ReadyForInvite()
	})
}

func TestTheNetworksVerdictIsMappedNotComputed(t *testing.T) {
	for current, want := range map[string]Verdict{
		"recommended":   VerdictRecommended,
		"new":           VerdictRecommended,
		"new in series": VerdictRecommended,
		"old":           VerdictOutdated,
		"unrecommended": VerdictOutdated,
		"obsolete":      VerdictObsolete,
		"unknown":       VerdictUnknown,
		"":              VerdictUnknown,
	} {
		if got := verdictOf(current); got != want {
			t.Errorf("verdictOf(%q) = %s, want %s", current, got, want)
		}
	}

	l := &fakeLauncher{version: Version{0, 4, 9, 13}, next: func() *fakeCtl {
		c := newFakeCtl()
		c.answers["status/version/current"] = []string{"status/version/current=obsolete", "OK"}
		return c
	}}
	h := newHarness(t, l, &keySource{})
	eventually(t, "obsolete verdict", func() bool { return h.s.Status().Verdict == VerdictObsolete })

	// A fresh consensus is a STATUS_CLIENT event, and the only one a tor the
	// network recommends ever gets: after a cold start it is the first moment
	// a verdict exists.
	c := l.run(0).c
	c.setAnswer("status/version/current", "status/version/current=recommended", "OK")
	c.events <- "STATUS_CLIENT NOTICE CONSENSUS_ARRIVED"
	eventually(t, "verdict re-read on CONSENSUS_ARRIVED", func() bool { return h.s.Status().Verdict == VerdictRecommended })

	// A version the network turns against is a STATUS_GENERAL event.
	c.setAnswer("status/version/current", "status/version/current=unrecommended", "OK")
	c.events <- `STATUS_GENERAL WARN DANGEROUS_VERSION CURRENT=0.4.9.13 REASON=UNRECOMMENDED RECOMMENDED="0.4.9.14"`
	eventually(t, "verdict re-read on DANGEROUS_VERSION", func() bool { return h.s.Status().Verdict == VerdictOutdated })
}

func TestConnectionWarningsBecomeTheLastErrorScrubbed(t *testing.T) {
	l := &fakeLauncher{version: Version{0, 4, 9, 13}}
	h := newHarness(t, l, &keySource{})
	eventually(t, "running", func() bool { return h.s.Status().Phase == PhaseRunning })

	l.run(0).c.events <- `STATUS_CLIENT WARN BOOTSTRAP PROGRESS=10 TAG=conn WARNING="Connection refused" REASON=CONNECTREFUSED COUNT=3`
	eventually(t, "warning recorded", func() bool {
		return strings.Contains(h.s.Status().LastError, "Connection refused") &&
			strings.Contains(h.s.Status().LastError, "CONNECTREFUSED")
	})
	// tor reports a skewed clock as a STATUS_GENERAL event, never a client one.
	l.run(0).c.events <- "STATUS_GENERAL WARN CLOCK_SKEW SKEW=-7200 SOURCE=CONSENSUS"
	eventually(t, "clock skew named", func() bool { return strings.Contains(h.s.Status().LastError, "clock") })
}

// A refused ADD_ONION must not carry a single byte of key material anywhere a
// person can read: not the status snapshot, not the log.
func TestAFailedPublicationLeavesNoKeyOrAddressBehind(t *testing.T) {
	keys := &keySource{keys: []string{b64key(3)}}
	l := &fakeLauncher{version: Version{0, 4, 9, 13}, next: func() *fakeCtl {
		c := newFakeCtl()
		c.refuse["ADD_ONION"] = 512
		return c
	}}
	h := newHarness(t, l, keys)
	eventually(t, "the refusal recorded", func() bool {
		return strings.Contains(h.s.Status().LastError, "ADD_ONION")
	})
	expanded := base64.StdEncoding.EncodeToString(h.s.expanded)
	secrets := []string{expanded, expanded[:40], clientKey(t, 3), b64key(3), h.s.Address()}
	for where, text := range map[string]string{"status": h.s.Status().LastError, "log": h.logged()} {
		for _, secret := range secrets {
			if strings.Contains(text, secret) {
				t.Fatalf("%s carries key or address material: %q", where, text)
			}
		}
	}
	if h.s.Status().Publication != PublicationTorDown {
		t.Fatalf("publication = %s after a refusal", h.s.Status().Publication)
	}
}

func TestStartArgumentsOpenNoOtherDoors(t *testing.T) {
	args := startArgs("/data/nox.db-tor", 4242)
	joined := " " + strings.Join(args, " ") + " "
	for _, want := range []string{
		" --SocksPort 0 ",
		" --ClientOnly 1 ",
		" --ControlPort auto ",
		" --CookieAuthentication 1 ",
		" --__OwningControllerProcess 4242 ",
		" --SafeLogging 1 ",
	} {
		if !strings.Contains(joined, want) {
			t.Errorf("start arguments lack %q: %v", want, args)
		}
	}
	for _, banned := range []string{"NonAnonymous", "SingleHop", "ORPort", "ExitRelay"} {
		if strings.Contains(joined, banned) {
			t.Errorf("start arguments carry %q", banned)
		}
	}
	// The same empty file as BOTH configs keeps the system torrc out.
	f, d := slices.Index(args, "-f"), slices.Index(args, "--defaults-torrc")
	if f < 0 || d < 0 || args[f+1] != args[d+1] {
		t.Fatalf("-f and --defaults-torrc must name the same empty file: %v", args)
	}
}

// protocolRefusal is what tor prints, at err, right before it exits when the
// consensus requires a protocol it lacks (networkstatus.c) - word for word,
// because the supervisor recognises it by those words.
const protocolRefusal = "At least one protocol listed as required in the consensus is not supported by this version of Tor. " +
	"You should upgrade. This version of Tor will not work as a client on the Tor network. The missing protocols are: HSDir=3"

func TestTorsOwnLogIsRetoldScrubbed(t *testing.T) {
	l := &fakeLauncher{version: Version{0, 4, 9, 13}}
	h := newHarness(t, l, &keySource{})
	eventually(t, "running", func() bool { return h.s.Status().Phase == PhaseRunning })
	addr := h.s.Address()

	r := l.run(0)
	r.out <- "Oct 03 11:13:50.000 [notice] Bootstrapped 100% (done): Done"
	r.out <- "Oct 03 11:13:51.000 [warn] Problem with service " + addr + ".onion"
	r.out <- "Oct 03 11:13:52.000 [info] chatter nobody needs"
	r.out <- "Oct 03 11:13:53.000 [err] " + protocolRefusal

	eventually(t, "the protocol refusal reached the verdict", func() bool {
		st := h.s.Status()
		return st.Verdict == VerdictObsolete && strings.Contains(st.LastError, "listed as required in the consensus")
	})
	logged := h.logged()
	if !strings.Contains(logged, "Bootstrapped 100%") || !strings.Contains(logged, "Problem with service [onion]") {
		t.Fatalf("expected lines missing from the log: %s", logged)
	}
	if strings.Contains(logged, addr) {
		t.Fatal("the onion address reached the log")
	}
	if strings.Contains(logged, "chatter nobody needs") {
		t.Fatal("info-level noise reached the log")
	}
}
