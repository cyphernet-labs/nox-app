package tor

import (
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"
)

// lastPrefixed is the last command sent that starts with prefix.
func lastPrefixed(cmds []string, prefix string) string {
	for i := len(cmds) - 1; i >= 0; i-- {
		if strings.HasPrefix(cmds[i], prefix) {
			return cmds[i]
		}
	}
	return ""
}

// The read that follows a revocation failing once must not lose the
// revocation: the read is retried, and the revoked key leaves the service.
func TestAFailedKeyReadIsRetriedSoARevocationIsNotLost(t *testing.T) {
	keys := &keySource{keys: []string{b64key(1), b64key(2)}}
	l := &fakeLauncher{version: Version{0, 4, 9, 13}}
	h := newHarness(t, l, keys)
	c := published(t, l, 0)

	keys.set([]string{b64key(1)}, time.Time{})
	keys.failReads(1)
	h.s.KeysChanged()
	eventually(t, "the revoked key republished away", func() bool {
		return countPrefix(c.sent(), "ADD_ONION") == 2 && !strings.Contains(lastPrefixed(c.sent(), "ADD_ONION"), clientKey(t, 2))
	})
	if strings.Contains(h.logged(), "took the onion service down") {
		t.Fatal("one failed read took the service down")
	}
}

// A failed read must not leave the expiry timer armed from a moment already
// past: it would fire at once, fail again, and spin.
func TestFailingKeyReadsDoNotSpin(t *testing.T) {
	keys := &keySource{keys: []string{b64key(1), b64key(9)}, expiry: time.Now().Add(30 * time.Millisecond)}
	l := &fakeLauncher{version: Version{0, 4, 9, 13}}
	newHarness(t, l, keys)
	published(t, l, 0)

	keys.failReads(-1)
	before := keys.readCount()
	time.Sleep(300 * time.Millisecond)
	// Retries come at 10, 20, 40, 80 ms and so on: a handful. The spin this
	// guards against read a hundred thousand times in the same window.
	if n := keys.readCount() - before; n > 30 {
		t.Fatalf("%d reads of the keys in 300 ms while they kept failing: the supervisor is spinning", n)
	}
}

// Keys that cannot be read are a list nobody can check - perhaps one a revoked
// device is still on. After a few failures in a row the service goes down and
// its circuits are cut; it comes back with the first read that succeeds.
func TestKeysThatCannotBeReadTakeTheServiceDownUntilTheyCanAgain(t *testing.T) {
	keys := &keySource{keys: []string{b64key(1)}}
	l := &fakeLauncher{version: Version{0, 4, 9, 13}}
	h := newHarness(t, l, keys, func(s *Supervisor) { s.keyRetryMax = 20 * time.Millisecond })
	c := published(t, l, 0)
	addr := h.s.Address()
	c.setAnswer("circuit-status", "circuit-status=21 BUILT $A~a PURPOSE=HS_SERVICE_REND REND_QUERY="+addr, "OK")

	keys.failReads(-1)
	h.s.KeysChanged()
	eventually(t, "down and cut", func() bool {
		return countPrefix(c.sent(), "DEL_ONION "+addr) == 1 && countPrefix(c.sent(), "CLOSECIRCUIT 21") == 1 &&
			h.s.Status().Publication == PublicationKeysUnreadable
	})
	if n := countPrefix(c.sent(), "ADD_ONION"); n != 1 {
		t.Fatalf("ADD_ONION sent %d times while the keys could not be read", n)
	}

	keys.failReads(0)
	eventually(t, "back once a read succeeds", func() bool {
		return countPrefix(c.sent(), "ADD_ONION") == 2 && h.s.Status().Publication == PublicationPublishing
	})
}

// A tor that dies while starting printed why - a directory it may not use, a
// lock another tor holds - and that is the only account there is.
func TestATorThatDiesAtStartSaysWhyInTheLogAndOnThePage(t *testing.T) {
	l := &fakeLauncher{
		version:  Version{0, 4, 9, 13},
		startErr: errors.New("tor exited before opening its control port"),
		startLines: []string{
			"Oct 03 11:13:50.000 [notice] Tor 0.4.9.13 running on Darwin",
			"Oct 03 11:13:50.000 [warn] Directory /data/nox.db-tor cannot be read: Permission denied",
		},
	}
	h := newHarness(t, l, &keySource{}, func(s *Supervisor) { s.backoffMin, s.backoffMax = time.Hour, time.Hour })
	eventually(t, "tor's own reason on the page", func() bool {
		st := h.s.Status()
		return st.Phase == PhaseWaitingRetry && strings.Contains(st.LastError, "cannot be read: Permission denied")
	})
	if !strings.Contains(h.logged(), "cannot be read: Permission denied") {
		t.Fatalf("tor's reason did not reach the log: %s", h.logged())
	}
}

// tor prints why it leaves and leaves in the same breath. Whichever of the two
// the supervisor notices first, the reason survives: in the verdict, and as
// the reason tor stopped - not "tor exited". Both are ready before the
// supervisor first looks, so which it takes is a coin toss each time.
func TestTorsLastWordsSurviveItsExit(t *testing.T) {
	for i := range 10 {
		t.Run(fmt.Sprint(i), func(t *testing.T) {
			l := &fakeLauncher{version: Version{0, 4, 9, 13}, started: func(r *fakeRun) {
				r.out <- "Oct 03 11:13:53.000 [err] " + protocolRefusal
				close(r.exit)
			}}
			h := newHarness(t, l, &keySource{}, func(s *Supervisor) { s.backoffMin, s.backoffMax = time.Hour, time.Hour })
			eventually(t, "the refusal kept", func() bool {
				st := h.s.Status()
				return st.Phase == PhaseWaitingRetry && st.Verdict == VerdictObsolete &&
					strings.Contains(st.LastError, "listed as required in the consensus")
			})
		})
	}
}

// A tor that is there and will not even print its version - the unsigned
// macOS build is killed at launch - is not "not found": the cure differs.
func TestATorThatWillNotRunIsToldApartFromAMissingOne(t *testing.T) {
	l := &fakeLauncher{locateErr: fmt.Errorf("run tor --version: %w", errors.New("signal: killed"))}
	h := newHarness(t, l, &keySource{keys: []string{b64key(1)}})
	eventually(t, "binary-unusable", func() bool {
		st := h.s.Status()
		return st.Phase == PhaseBinaryUnusable && strings.Contains(st.LastError, "did not run") &&
			strings.Contains(st.LastError, "killed")
	})
	if h.s.Offered() || l.startCount() != 0 {
		t.Fatal("a tor that will not run was offered or started")
	}
}

// An invite's one-time key that runs out while tor is down stops being offered
// then - not when the pause before the next start is over.
func TestAnExpiringOneTimeKeyStopsBeingOfferedWhileTorIsDown(t *testing.T) {
	keys := &keySource{keys: []string{b64key(9)}, expiry: time.Now().Add(100 * time.Millisecond)}
	l := &fakeLauncher{version: Version{0, 4, 9, 13}, startErr: errors.New("boom")}
	h := newHarness(t, l, keys, func(s *Supervisor) { s.backoffMin, s.backoffMax = time.Hour, time.Hour })
	eventually(t, "offered while the one-time key lives", h.s.Offered)

	// What the store says once the invite has expired. No KeysChanged: an
	// expiry is nobody's write.
	keys.set(nil, time.Time{})
	eventually(t, "not offered once it expired", func() bool { return !h.s.Offered() })
}
