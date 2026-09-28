package tor

import (
	"errors"
	"slices"
	"strings"
	"testing"
	"time"
)

// published waits for the first ADD_ONION of run i and returns the fake.
func published(t *testing.T, l *fakeLauncher, i int) *fakeCtl {
	t.Helper()
	eventually(t, "first publication", func() bool {
		r := l.run(i)
		return r != nil && countPrefix(r.c.sent(), "ADD_ONION") > 0
	})
	return l.run(i).c
}

func TestABurstOfChangesIsOneRepublish(t *testing.T) {
	keys := &keySource{keys: []string{b64key(1)}}
	l := &fakeLauncher{version: Version{0, 4, 9, 13}}
	h := newHarness(t, l, keys)
	c := published(t, l, 0)

	keys.set([]string{b64key(1), b64key(2)}, time.Time{})
	for range 10 {
		h.s.KeysChanged()
	}
	eventually(t, "the republish", func() bool { return countPrefix(c.sent(), "ADD_ONION") == 2 })
	time.Sleep(50 * time.Millisecond)
	if n := countPrefix(c.sent(), "ADD_ONION"); n != 2 {
		t.Fatalf("ADD_ONION sent %d times for one burst, want 2 (first + one republish)", n)
	}
	if n := countPrefix(c.sent(), "DEL_ONION "+h.s.Address()); n != 1 {
		t.Fatalf("DEL_ONION sent %d times, want 1", n)
	}
}

func TestAnUnchangedSetPublishesNothing(t *testing.T) {
	keys := &keySource{keys: []string{b64key(1)}}
	l := &fakeLauncher{version: Version{0, 4, 9, 13}}
	h := newHarness(t, l, keys)
	c := published(t, l, 0)
	before := len(c.sent())

	h.s.KeysChanged()
	time.Sleep(80 * time.Millisecond)
	for _, cmd := range c.sent()[before:] {
		if strings.HasPrefix(cmd, "ADD_ONION") || strings.HasPrefix(cmd, "DEL_ONION") || strings.HasPrefix(cmd, "CLOSECIRCUIT") {
			t.Fatalf("an unchanged set sent %q: a re-registered key must not cut every connection", strings.Fields(cmd)[0])
		}
	}
}

// Circuits are cut whenever a key leaves the set - a swap included - and only
// this service's rendezvous circuits.
func TestARemovedKeyCutsOnlyThisServicesRendezvousCircuits(t *testing.T) {
	keys := &keySource{keys: []string{b64key(1)}}
	l := &fakeLauncher{version: Version{0, 4, 9, 13}}
	h := newHarness(t, l, keys)
	c := published(t, l, 0)
	addr := h.s.Address()
	c.setAnswer("circuit-status",
		"circuit-status=\n"+
			"11 BUILT $A~a,$B~b PURPOSE=HS_SERVICE_REND HS_STATE=HSSR_JOINED REND_QUERY="+addr+" TIME_CREATED=x\n"+
			"12 BUILT $A~a PURPOSE=HS_SERVICE_INTRO HS_STATE=HSSI_ESTABLISHED REND_QUERY="+addr+"\n"+
			"13 BUILT $A~a PURPOSE=HS_SERVICE_REND HS_STATE=HSSR_JOINED REND_QUERY=someoneelseaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"+
			"14 BUILT $A~a PURPOSE=GENERAL",
		"OK")

	// A swap: the one-time key goes, the device's own key comes. Same length,
	// and still a removal.
	keys.set([]string{b64key(2)}, time.Time{})
	h.s.KeysChanged()
	eventually(t, "the cut", func() bool { return countPrefix(c.sent(), "CLOSECIRCUIT") > 0 })
	time.Sleep(50 * time.Millisecond)
	var closed []string
	for _, cmd := range c.sent() {
		if strings.HasPrefix(cmd, "CLOSECIRCUIT ") {
			closed = append(closed, strings.TrimPrefix(cmd, "CLOSECIRCUIT "))
		}
	}
	if len(closed) != 1 || closed[0] != "11" {
		t.Fatalf("closed circuits %v, want only 11 - this service's rendezvous circuit", closed)
	}
}

func TestAddingKeysCutsNothing(t *testing.T) {
	keys := &keySource{keys: []string{b64key(1)}}
	l := &fakeLauncher{version: Version{0, 4, 9, 13}}
	h := newHarness(t, l, keys)
	c := published(t, l, 0)

	keys.set([]string{b64key(1), b64key(2)}, time.Time{})
	h.s.KeysChanged()
	eventually(t, "the republish", func() bool { return countPrefix(c.sent(), "ADD_ONION") == 2 })
	time.Sleep(60 * time.Millisecond)
	if n := countPrefix(c.sent(), "GETINFO circuit-status") + countPrefix(c.sent(), "CLOSECIRCUIT"); n != 0 {
		t.Fatalf("an added key touched the circuits (%d commands)", n)
	}
}

func TestTheLastKeyGoneTakesTheServiceDownAndCutsItsCircuits(t *testing.T) {
	keys := &keySource{keys: []string{b64key(1)}}
	l := &fakeLauncher{version: Version{0, 4, 9, 13}}
	h := newHarness(t, l, keys)
	c := published(t, l, 0)
	addr := h.s.Address()
	c.setAnswer("circuit-status", "circuit-status=21 BUILT $A~a PURPOSE=HS_SERVICE_REND REND_QUERY="+addr, "OK")

	keys.set(nil, time.Time{})
	h.s.KeysChanged()
	eventually(t, "down and cut", func() bool {
		return countPrefix(c.sent(), "DEL_ONION "+addr) == 1 && countPrefix(c.sent(), "CLOSECIRCUIT 21") == 1
	})
	if countPrefix(c.sent(), "ADD_ONION") != 1 {
		t.Fatal("an empty set was published")
	}
	eventually(t, "no keys, not offered", func() bool {
		return h.s.Status().Publication == PublicationNoKeys && !h.s.Offered()
	})
}

func TestAOneTimeKeyIsRepublishedAwayWhenItExpires(t *testing.T) {
	expiry := time.Now().Add(150 * time.Millisecond)
	keys := &keySource{keys: []string{b64key(1), b64key(9)}, expiry: expiry}
	l := &fakeLauncher{version: Version{0, 4, 9, 13}}
	h := newHarness(t, l, keys)
	c := published(t, l, 0)

	// What the store will say once the invite has expired.
	keys.set([]string{b64key(1)}, time.Time{})
	eventually(t, "republish at expiry", func() bool { return countPrefix(c.sent(), "ADD_ONION") == 2 })
	adds := 0
	for _, cmd := range c.sent() {
		if strings.HasPrefix(cmd, "ADD_ONION") {
			adds++
			if adds == 2 && strings.Contains(cmd, clientKey(t, 9)) {
				t.Fatal("the expired one-time key is still in the service")
			}
		}
	}
	eventually(t, "and the cut", func() bool { return countPrefix(c.sent(), "GETINFO circuit-status") > 0 })
	_ = h
}

func TestAMissingTorKeepsTheServerGoingAndSaysWhy(t *testing.T) {
	l := &fakeLauncher{locateErr: ErrNotFound}
	h := newHarness(t, l, &keySource{keys: []string{b64key(1)}})
	eventually(t, "binary-missing", func() bool {
		st := h.s.Status()
		return st.Phase == PhaseBinaryMissing && strings.Contains(st.LastError, "not found")
	})
	if h.s.Offered() || h.s.ReadyForInvite() {
		t.Fatal("a server with no tor offers an onion address")
	}
	if l.startCount() != 0 {
		t.Fatal("tried to start a tor that was not found")
	}

	// Installed later: the periodic recheck picks it up without a restart.
	l.mu.Lock()
	l.locateErr, l.version = nil, Version{0, 4, 9, 13}
	l.mu.Unlock()
	eventually(t, "started after the recheck", func() bool { return l.startCount() == 1 })
	eventually(t, "offered once tor is usable and a key exists", h.s.Offered)
}

func TestAnOldTorIsNamedAndNotRun(t *testing.T) {
	l := &fakeLauncher{locateErr: errors.Join(errTooOld), version: Version{0, 4, 8, 17}}
	h := newHarness(t, l, &keySource{})
	eventually(t, "binary-too-old", func() bool {
		st := h.s.Status()
		return st.Phase == PhaseBinaryTooOld && strings.Contains(st.LastError, "0.4.8.17")
	})
	if l.startCount() != 0 {
		t.Fatal("started a tor below the floor")
	}
}

func TestACrashedTorIsRestartedWithAGrowingPause(t *testing.T) {
	l := &fakeLauncher{version: Version{0, 4, 9, 13}}
	pauses := make(chan time.Duration, 16)
	h := newHarness(t, l, &keySource{keys: []string{b64key(1)}}, func(s *Supervisor) {
		s.retryHook = func(d time.Duration) { pauses <- d }
	})
	published(t, l, 0)

	var got []time.Duration
	for i := range 4 {
		close(l.run(i).exit)
		select {
		case d := <-pauses:
			got = append(got, d)
		case <-time.After(5 * time.Second):
			t.Fatal("no restart was scheduled")
		}
		eventually(t, "restarted", func() bool { return l.startCount() >= i+2 })
	}
	// 10ms, 20ms, 40ms, then the 40ms cap: it grew instead of hammering tor.
	want := []time.Duration{10 * time.Millisecond, 20 * time.Millisecond, 40 * time.Millisecond, 40 * time.Millisecond}
	if !slices.Equal(got, want) {
		t.Fatalf("pauses = %v, want %v", got, want)
	}
	// Offered never flapped off: a crash is a temporary failure.
	if !h.s.Offered() {
		t.Fatal("a crash took the onion address out of the list")
	}
}

func TestKeysChangingWhileTorIsDownStillMoveOffered(t *testing.T) {
	keys := &keySource{}
	l := &fakeLauncher{version: Version{0, 4, 9, 13}, startErr: errors.New("boom")}
	h := newHarness(t, l, keys)
	eventually(t, "waiting to retry", func() bool { return h.s.Status().Phase == PhaseWaitingRetry })
	if h.s.Offered() {
		t.Fatal("offered with no keys")
	}
	keys.set([]string{b64key(1)}, time.Time{})
	h.s.KeysChanged()
	eventually(t, "offered follows the key while tor is down", h.s.Offered)
}

func TestDisabledAnswersNoTorHere(t *testing.T) {
	s := Disabled()
	s.KeysChanged()
	s.KeysChanged() // never blocks
	if s.Offered() || s.ReadyForInvite() || s.OnionPublicKey() != nil || s.Address() != "" {
		t.Fatal("a disabled supervisor offers something")
	}
	if st := s.Status(); st.Enabled || st.Phase != PhaseDisabled {
		t.Fatalf("status = %+v", st)
	}
	done := make(chan struct{})
	go func() {
		s.Run(t.Context())
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("a disabled supervisor's Run did not return at once")
	}
}
