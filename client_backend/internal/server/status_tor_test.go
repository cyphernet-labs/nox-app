package server

import (
	"strings"
	"testing"
	"time"

	"nox.app/client-backend/internal/tor"
)

func (f *fakeTor) setStatus(st tor.Status) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.status = st
}

func TestTheClaimedPageNamesEveryTorState(t *testing.T) {
	st := newOnionStack(t)
	pairedDevice(t, st.ts, st.srv) // claimed

	for _, tc := range []struct {
		name   string
		status tor.Status
		want   []string
		warn   bool
	}{
		{"turned off", tor.Status{Enabled: false, Phase: tor.PhaseDisabled},
			[]string{"Tor is turned off (-tor=false)"}, false},
		{"not installed", tor.Status{Enabled: true, Phase: tor.PhaseBinaryMissing, Publication: tor.PublicationTorDown},
			[]string{"tor not found — install tor 0.4.9 or newer", "Not published: tor is not running"}, true},
		{"too old", tor.Status{Enabled: true, Phase: tor.PhaseBinaryTooOld, Version: "0.4.8.17"},
			[]string{"tor 0.4.8.17 is too old"}, true},
		{"connecting", tor.Status{Enabled: true, Phase: tor.PhaseConnecting, Bootstrap: 45, Version: "0.4.9.13", Publication: tor.PublicationNoKeys},
			[]string{"Connecting to the Tor network (45%)", "Not published: no device has access yet", "0.4.9.13"}, false},
		{"published", tor.Status{Enabled: true, Phase: tor.PhaseRunning, Bootstrap: 100, Version: "0.4.9.13",
			Verdict: tor.VerdictRecommended, Publication: tor.PublicationPublished},
			[]string{"Connected to the Tor network", "Published", "recommended by the network", "0 of 1"}, false},
		{"outdated", tor.Status{Enabled: true, Phase: tor.PhaseRunning, Verdict: tor.VerdictOutdated, Publication: tor.PublicationPublishing},
			[]string{"outdated — update tor", "Publishing…"}, true},
		{"obsolete", tor.Status{Enabled: true, Phase: tor.PhaseRunning, Verdict: tor.VerdictObsolete},
			[]string{"no longer accepted by the network — update tor"}, true},
		{"restarting", tor.Status{Enabled: true, Phase: tor.PhaseWaitingRetry, RetryIn: 4 * time.Second, LastError: "tor stopped: tor exited"},
			[]string{"tor stopped — retrying in 4s", "Last error", "tor exited"}, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			st.tor.setStatus(tc.status)
			body := statusBody(t, st.srv)
			for _, want := range tc.want {
				if !strings.Contains(body, want) {
					t.Errorf("page lacks %q", want)
				}
			}
			if warned := strings.Contains(body, `<p class="warn">`); warned != tc.warn {
				t.Errorf("warning shown = %v, want %v", warned, tc.warn)
			}
		})
	}
}

func TestTheUnclaimedPageHasOneTorLine(t *testing.T) {
	st := newOnionStack(t)
	st.tor.setStatus(tor.Status{Enabled: true, Phase: tor.PhaseBinaryMissing})
	body := statusBody(t, st.srv)
	if !strings.Contains(body, "Tor: tor not found — install tor 0.4.9 or newer") {
		t.Fatalf("the unclaimed page does not say why Tor is not working: %s", body)
	}
	if strings.Contains(body, "Devices with access from anywhere") {
		t.Fatal("the unclaimed page shows the claimed details")
	}
}

// Neither the onion address nor anything key-shaped reaches the page, in any
// state - including a last error that tried to carry one.
func TestThePageNeverShowsTheOnionAddressOrAKey(t *testing.T) {
	st := newOnionStack(t)
	pairedDevice(t, st.ts, st.srv)
	leaky := "upload failed for " + st.tor.addr + ".onion with key MHyDhk8oM8tCei7xwAoBPP3/J2jZgMCjpSDwBpBN6U+bTwr+KAt0aneG"
	st.tor.setStatus(tor.Status{Enabled: true, Phase: tor.PhaseRunning, Publication: tor.PublicationPublished, LastError: leaky})
	st.tor.set(true, true)
	body := statusBody(t, st.srv)
	if strings.Contains(body, st.tor.addr) {
		t.Fatal("the onion address is on the page")
	}
	if strings.Contains(body, "MHyDhk8oM8tCei7xwAoBPP3") {
		t.Fatal("key material is on the page")
	}
}
