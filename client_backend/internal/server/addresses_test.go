package server

import (
	"encoding/json"
	"errors"
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

// direct is directAddresses for a bind that resolves no names.
func direct(t *testing.T, bind string, list func() []net.IP) []string {
	t.Helper()
	got, ok := directAddresses(bind, list, func(string) ([]net.IP, error) {
		t.Fatalf("%q resolved a name", bind)
		return nil, nil
	})
	if !ok {
		t.Fatalf("directAddresses(%q) was not ok", bind)
	}
	return got
}

// Only what another machine can dial, in order of preference: the usual home
// range first, other private ranges after it, IPv6 last.
func TestDirectAddressesKeepOnlyWhatAnotherMachineCanDial(t *testing.T) {
	got := direct(t, "0.0.0.0:8080", ips(
		"192.168.1.20", "127.0.0.1", "::1", "fe80::1", "169.254.10.10", "0.0.0.0",
		"fd12:3456::20", "10.0.0.5", "192.168.1.20", // duplicate
	))
	want := []string{"192.168.1.20:8080", "10.0.0.5:8080", "[fd12:3456::20]:8080"}
	if !slices.Equal(got, want) {
		t.Fatalf("directAddresses = %v, want %v", got, want)
	}
}

func TestDirectAddressesAreCappedAtSixteen(t *testing.T) {
	var many []string
	for i := range 40 {
		many = append(many, fmt.Sprintf("10.0.%d.1", i))
	}
	if got := direct(t, ":8080", ips(many...)); len(got) != maxDirectAddresses {
		t.Fatalf("got %d addresses, want the cap of %d", len(got), maxDirectAddresses)
	}
}

// A machine full of container bridges and a VPN still lists its home address,
// and lists it first: the cap drops the least likely addresses, not whichever
// sort last as text.
func TestTheCapKeepsTheLikeliestAddresses(t *testing.T) {
	list := []string{"100.101.102.103", "203.0.113.7"}
	for i := range 20 {
		list = append(list, fmt.Sprintf("172.%d.0.1", 17+i%15))
	}
	list = append(list, "192.168.1.20")
	got := direct(t, "0.0.0.0:8080", ips(list...))
	if len(got) != maxDirectAddresses || got[0] != "192.168.1.20:8080" {
		t.Fatalf("direct = %v, want the home address first within the cap", got)
	}
	if slices.Contains(got, "100.101.102.103:8080") {
		t.Fatalf("direct = %v: the VPN's shared-range address outranked a bridge that made the cut", got)
	}
}

func TestAConcreteBindListsItselfUnlessItIsLoopback(t *testing.T) {
	none := ips()
	if got := direct(t, "192.168.1.10:9000", none); !slices.Equal(got, []string{"192.168.1.10:9000"}) {
		t.Fatalf("concrete bind = %v", got)
	}
	for _, bind := range []string{"127.0.0.1:8080", "[::1]:8080", "127.0.0.1:0", "nonsense"} {
		if got := direct(t, bind, ips("192.168.1.20")); len(got) != 0 {
			t.Errorf("directAddresses(%q) = %v, want nothing - a loopback bind is useless elsewhere and known here", bind, got)
		}
	}
}

// A bind host name is listed while it resolves to something dialable. A
// resolver that fails is not the name moving: the list stays as it was rather
// than flipping to empty and back - which would send server.addresses to every
// device twice for nothing.
func TestAHostNameThatFailsToResolveKeepsTheListItHad(t *testing.T) {
	var mu sync.Mutex
	answer := []net.IP{net.ParseIP("192.168.1.20")}
	var fail error
	st := newOnionStack(t, func(s *Server) {
		s.cfg.Addr = "nox.example:8080"
		s.addressPoll = time.Hour // only the test refreshes
		s.resolveHost = func(string) ([]net.IP, error) {
			mu.Lock()
			defer mu.Unlock()
			return answer, fail
		}
	})
	set := func(ips []net.IP, err error) {
		mu.Lock()
		answer, fail = ips, err
		mu.Unlock()
	}
	first := st.srv.addrs.Load()
	if !slices.Equal(first.Direct, []string{"nox.example:8080"}) {
		t.Fatalf("direct = %v, want the name", first.Direct)
	}

	set(nil, errors.New("resolver unreachable"))
	if st.srv.refreshAddresses() {
		t.Fatal("a failed lookup changed the list")
	}
	if cur := st.srv.addrs.Load(); cur.Version != first.Version || !slices.Equal(cur.Direct, first.Direct) {
		t.Fatalf("after a failed lookup: %v (version %d), want the list it had", cur.Direct, cur.Version)
	}

	set([]net.IP{net.ParseIP("127.0.0.1")}, nil)
	if !st.srv.refreshAddresses() || len(st.srv.addrs.Load().Direct) != 0 {
		t.Fatalf("a name that now resolves to loopback is still listed: %v", st.srv.addrs.Load().Direct)
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

// The two halves of "the event never overtakes the reply, and a list that
// moved mid-greeting still arrives", each pinned on a hook at its moment.
// Moved right after the greeting read its snapshot, the newer list must follow
// the reply at once - the poke sends it, with the poll an hour away. A watcher
// pass landing the instant the connection is marked greeted must find the
// reply already queued ahead of its event.
func TestAListThatMovesMidGreetingFollowsTheReply(t *testing.T) {
	for _, at := range []string{"after the read", "after markGreeted"} {
		t.Run(at, func(t *testing.T) {
			var mu sync.Mutex
			current := []string{"192.168.1.20"}
			var once sync.Once
			move := func(s *Server, send bool) {
				once.Do(func() {
					mu.Lock()
					current = []string{"192.168.1.21"}
					mu.Unlock()
					s.refreshAddresses()
					if send {
						s.sendAddresses()
					}
				})
			}
			st := newOnionStack(t, func(s *Server) {
				s.cfg.Addr = "0.0.0.0:8080"
				s.addressPoll = time.Hour
				s.listIPs = func() []net.IP {
					mu.Lock()
					defer mu.Unlock()
					return ips(current...)()
				}
				if at == "after the read" {
					s.afterAddressRead = func() { move(s, false) }
				} else {
					s.afterGreeted = func(*client) { move(s, true) }
				}
			})
			d := pairedDevice(t, st.ts, st.srv)
			c := dialWS(t, st.ts, st.srv)
			c.expectGreeting()
			c.send(fmt.Sprintf(`{"id":1,"cmd":"session.hello","data":{"schema":1,"device_key":%q,"signature":%q}}`,
				d.pub, d.sign(t, c.challenge)))

			// Read raw: the helpers skip events, and an event here is the bug.
			reply := c.read()
			if _, isEvent := reply["event"]; isEvent {
				t.Fatalf("an event came before the greeting reply: %v", reply)
			}
			var hello struct {
				Addresses addressSet `json:"addresses"`
			}
			mustUnmarshal(t, reply["data"], &hello)
			if !slices.Equal(hello.Addresses.Direct, []string{"192.168.1.20:8080"}) {
				t.Fatalf("reply carries %v, want the list the greeting read", hello.Addresses.Direct)
			}
			next := c.read()
			var event string
			mustUnmarshal(t, next["event"], &event)
			var moved addressSet
			mustUnmarshal(t, next["data"], &moved)
			if event != "server.addresses" || !slices.Equal(moved.Direct, []string{"192.168.1.21:8080"}) {
				t.Fatalf("after the reply: %s %v, want server.addresses with the moved list", event, moved.Direct)
			}
		})
	}
}
