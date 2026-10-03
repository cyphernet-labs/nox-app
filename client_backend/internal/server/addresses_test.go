package server

import (
	"encoding/json"
	"fmt"
	"net"
	"slices"
	"sync"
	"testing"
	"time"
)

func ips(list ...string) func() []net.IP {
	return func() []net.IP {
		out := make([]net.IP, 0, len(list))
		for _, s := range list {
			out = append(out, net.ParseIP(s))
		}
		return out
	}
}

func TestDirectAddressesKeepOnlyWhatAnotherMachineCanDial(t *testing.T) {
	got := directAddresses("0.0.0.0:8080", ips(
		"192.168.1.20", "127.0.0.1", "::1", "fe80::1", "169.254.10.10", "0.0.0.0",
		"fd12:3456::20", "10.0.0.5", "192.168.1.20", // duplicate
	))
	want := []string{"10.0.0.5:8080", "192.168.1.20:8080", "[fd12:3456::20]:8080"}
	if !slices.Equal(got, want) {
		t.Fatalf("directAddresses = %v, want %v", got, want)
	}
}

func TestDirectAddressesAreCappedAtSixteen(t *testing.T) {
	var many []string
	for i := range 40 {
		many = append(many, fmt.Sprintf("10.0.%d.1", i))
	}
	if got := directAddresses(":8080", ips(many...)); len(got) != maxDirectAddresses {
		t.Fatalf("got %d addresses, want the cap of %d", len(got), maxDirectAddresses)
	}
}

func TestAConcreteBindListsItselfUnlessItIsLoopback(t *testing.T) {
	none := ips()
	if got := directAddresses("192.168.1.10:9000", none); !slices.Equal(got, []string{"192.168.1.10:9000"}) {
		t.Fatalf("concrete bind = %v", got)
	}
	for _, bind := range []string{"127.0.0.1:8080", "[::1]:8080", "127.0.0.1:0", "nonsense"} {
		if got := directAddresses(bind, ips("192.168.1.20")); len(got) != 0 {
			t.Errorf("directAddresses(%q) = %v, want nothing - a loopback bind is useless elsewhere and known here", bind, got)
		}
	}
}

func TestTheGreetingCarriesTheAddressesAlways(t *testing.T) {
	ts, srv := newTestServer(t)
	c := dialWS(t, ts, srv)
	c.expectGreeting()
	data := c.hello(1, "")

	var addrs struct {
		Direct []string `json:"direct"`
		Onion  *string  `json:"onion"`
	}
	mustUnmarshal(t, data["addresses"], &addrs)
	if addrs.Direct == nil {
		t.Fatal("addresses.direct is missing; the contract promises it, possibly empty")
	}
	if addrs.Onion != nil {
		t.Fatalf("an onion address without Tor: %q", *addrs.Onion)
	}
}

func TestTheOnionAddressIsListedWhileOffered(t *testing.T) {
	st := newOnionStack(t, func(s *Server) {
		s.cfg.Addr = "0.0.0.0:8080"
		s.listIPs = ips("192.168.1.20")
	})
	st.tor.set(true, true)
	// The snapshot was taken at startup, before the fake said yes; the watcher
	// learns on its next look.
	st.srv.pokeAddresses()
	eventually(t, "the snapshot names the onion address", func() bool {
		cur := st.srv.addrs.Load()
		return cur != nil && cur.Onion != ""
	})

	c := dialWS(t, st.ts, st.srv)
	c.expectGreeting()
	data := c.hello(1, "")
	var addrs addressSet
	mustUnmarshal(t, data["addresses"], &addrs)
	if want := st.tor.addr + ".onion:443"; addrs.Onion != want {
		t.Fatalf("onion = %q, want %q", addrs.Onion, want)
	}
	if !slices.Equal(addrs.Direct, []string{"192.168.1.20:8080"}) {
		t.Fatalf("direct = %v", addrs.Direct)
	}
}

// The event goes to greeted connections only, never ahead of the greeting
// reply, and a connection never ends on an older list than the newest one.
func TestAddressChangesReachGreetedConnectionsOnly(t *testing.T) {
	var mu sync.Mutex
	current := []string{"192.168.1.20"}
	st := newOnionStack(t, func(s *Server) {
		s.cfg.Addr = "0.0.0.0:8080"
		s.listIPs = func() []net.IP {
			mu.Lock()
			defer mu.Unlock()
			return ips(current...)()
		}
	})
	setIPs := func(list ...string) {
		mu.Lock()
		current = list
		mu.Unlock()
	}

	greeted := dialWS(t, st.ts, st.srv)
	greeted.expectGreeting()
	greeted.hello(1, "")

	// Connected but not greeted: it must hear nothing.
	silent := dialWS(t, st.ts, st.srv)
	silent.expectGreeting()

	// The router hands the machine a new address, twice in a row.
	setIPs("192.168.1.21")
	st.srv.pokeAddresses()
	setIPs("192.168.1.22")
	st.srv.pokeAddresses()

	var last []string
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		seq, name, data := greeted.expectEvent()
		if name != "server.addresses" || seq != 0 {
			continue
		}
		var got addressSet
		raw, _ := json.Marshal(data)
		if err := json.Unmarshal(raw, &got); err != nil {
			t.Fatalf("event payload: %v", err)
		}
		last = got.Direct
		if slices.Equal(last, []string{"192.168.1.22:8080"}) {
			break
		}
	}
	if !slices.Equal(last, []string{"192.168.1.22:8080"}) {
		t.Fatalf("the greeted connection ended on %v, want the newest list", last)
	}
	silent.expectNoFrame(200 * time.Millisecond)
}

func TestAGreetingNeverSeesTheEventBeforeItsReply(t *testing.T) {
	st := newOnionStack(t, func(s *Server) {
		s.cfg.Addr = "0.0.0.0:8080"
		s.listIPs = ips("192.168.1.20")
	})
	for i := range 20 {
		c := dialWS(t, st.ts, st.srv)
		c.expectGreeting()
		// Move the list while the greeting is on its way.
		st.tor.set(i%2 == 0, false)
		st.srv.pokeAddresses()
		c.send(fmt.Sprintf(`{"id":1,"cmd":"session.hello","data":{"schema":1,"device_key":%q,"signature":%q}}`,
			c.devKey(t), c.devSig(t)))
		frame := c.read()
		if _, isEvent := frame["event"]; isEvent {
			t.Fatalf("round %d: an event arrived before the greeting reply: %v", i, frame)
		}
	}
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
