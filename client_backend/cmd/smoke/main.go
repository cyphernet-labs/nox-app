// Command smoke walks the whole stage-2 flow against a RUNNING noxd and says
// whether it works.
//
// It exists because the flow crosses several devices and a real socket, which
// no unit test reaches end to end and no person wants to click through twice
// before a demo. Point it at a machine link - the one on the service page, or
// the one `noxd link` prints - and it pairs a first device through it, adds a
// second by invite and allows it from the first, has a third declined, and has
// the two paired devices exchange a message.
//
// It talks to the wire directly rather than through the app - the channel
// included: TCP, TLS 1.3 that checks no certificate, then the channel check
// with a device key against the server key the link names (contract §1). What
// is being checked is the server, and a failure here is the server's.
package main

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/tls"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/coder/websocket"

	"nox.app/client-backend/internal/eidolon"
	"nox.app/client-backend/internal/server"
)

const usage = `usage: smoke <machine link>
       smoke -check <host:port> <server key, base64>

Give it a machine link: the one on the service page of a running noxd, or the
one "noxd link" prints (the server's log says where the page is, never what a
link is). It works on a fresh server - the first device creates the person -
and on one that has a person already, whom the first device then joins. The
link's direct addresses are tried in its order - the public one first, when it
has one - and the run goes on with the first that proves the key; an onion
address in the link is reported and not tried, because this program has no
Tor.

With -check it only opens the channel - TLS and the channel check, with a
throwaway device key - and says whether the machine at that address is the one
whose key it was given. Nothing is paired and nothing is sent.`

func main() {
	switch {
	case len(os.Args) == 4 && os.Args[1] == "-check":
		if err := check(os.Args[2], os.Args[3]); err != nil {
			fmt.Fprintf(os.Stderr, "not this server: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("ok")
	case len(os.Args) == 2:
		if err := run(os.Args[1]); err != nil {
			fmt.Fprintf(os.Stderr, "\n  FAILED: %v\n\n", err)
			os.Exit(1)
		}
	default:
		fmt.Fprintln(os.Stderr, usage)
		os.Exit(2)
	}
}

// check opens one channel to addr and closes it. The answer is whether the
// machine there proved the given key: the stand script asks it to tell its own
// server from somebody else's holding the same port.
func check(addr, serverKey string) error {
	key, err := base64.StdEncoding.DecodeString(serverKey)
	if err != nil || len(key) != ed25519.PublicKeySize {
		return errors.New("the server key is not 32 bytes of base64")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	channel, err := openChannel(ctx, link{addr: addr, serverKey: key}, newDevice())
	if err != nil {
		return err
	}
	return channel.Close()
}

// reach picks the link's first direct address that opens a channel proving
// the link's key - the order the app tries them in. A throwaway device key is
// enough: the channel says which machine answered before anything is paired.
func reach(target link) (link, error) {
	var tried []string
	for _, addr := range target.addrs {
		if err := check(addr, base64.StdEncoding.EncodeToString(target.serverKey)); err != nil {
			tried = append(tried, fmt.Sprintf("%s (%v)", addr, err))
			continue
		}
		target.addr = addr
		return target, nil
	}
	return link{}, fmt.Errorf("no direct address in the link reaches the server it names: %s", strings.Join(tried, "; "))
}

func run(rawLink string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()

	parsed, err := parseLink(rawLink)
	if err != nil {
		return err
	}
	target, err := reach(parsed)
	if err != nil {
		return err
	}
	fmt.Printf("\nserver %s, key %s\n", target.addr, base64.StdEncoding.EncodeToString(target.serverKey))
	if target.onion {
		// Named, never printed: the address is in the link already, and this
		// program has no Tor to try it with.
		fmt.Println("the link also names an onion service - not tried here, there is no Tor in this program")
	}

	step(1, "The first device pairs through the machine link")
	first := newDevice()
	personID, created, err := pairFirst(ctx, target, first)
	if err != nil {
		return err
	}

	firstConn, err := greet(ctx, target, first)
	if err != nil {
		return err
	}
	defer firstConn.close()
	if created {
		if _, err := firstConn.call("identity.setLabel", data{"label": "Anna"}); err != nil {
			return err
		}
		ok("named: Anna")
	}

	step(2, "A second device joins by invite, allowed on the first")
	phoneConn, err := inviteAndAllow(ctx, target, firstConn, personID)
	if err != nil {
		return err
	}
	defer phoneConn.close()
	devices, err := firstConn.call("device.list", data{})
	if err != nil {
		return err
	}
	ok("device.list shows %d devices", len(devices["devices"].([]any)))

	step(3, "A third device is declined, and nothing is paired")
	if err := inviteAndDeny(ctx, target, firstConn); err != nil {
		return err
	}

	step(4, "The two devices exchange a message")
	if err := talk(firstConn, phoneConn, personID); err != nil {
		return err
	}

	fmt.Printf("\n  every step passed\n\n")
	return nil
}

// pairFirst pairs dev through the machine link. On a fresh server it creates
// the person; on one that has a person it joins them - either is right, and
// which one happened is said.
func pairFirst(ctx context.Context, target link, dev device) (string, bool, error) {
	c, err := dial(ctx, target, dev)
	if err != nil {
		return "", false, err
	}
	defer c.close()
	if err := c.greeting(); err != nil {
		return "", false, err
	}
	reply, err := c.call("pair", data{"token": target.token, "platform": "macos"})
	if err != nil {
		return "", false, err
	}
	id, okID := reply["identity"].(map[string]any)
	if !okID {
		return "", false, fmt.Errorf("the machine link carried no identity: %v", reply)
	}
	created, okCreated := id["created"].(bool)
	if !okCreated {
		return "", false, fmt.Errorf("the identity does not say whether it was created: %v", id)
	}
	if created {
		ok("paired: the person was created - a fresh server")
	} else {
		ok("paired: joined the person already here, no naming step")
	}
	return id["id"].(string), created, nil
}

// invite has the greeted device issue an invite and checks what it says about
// itself.
func invite(issuer *conn) (string, error) {
	reply, err := issuer.call("device.invite", data{})
	if err != nil {
		return "", err
	}
	inviteLink, err := server.ParsePairingLink(fmt.Sprint(reply["link"]))
	if err != nil {
		return "", fmt.Errorf("the invite link does not read back: %w", err)
	}
	// The two flags say what the link carries (045): an onion address, a
	// public one. Both are always there, and the onion one must match the link.
	onion, okOnion := reply["onion"].(bool)
	public, okPublic := reply["public"].(bool)
	if !okOnion || !okPublic {
		return "", fmt.Errorf("the invite reply lacks its onion/public flags: %v", reply)
	}
	if onion != (inviteLink.Onion != nil) {
		return "", fmt.Errorf("the invite says onion=%v, and its link says otherwise", onion)
	}
	ok("device invite issued (10 minutes), a version-3 link: onion=%v public=%v", onion, public)
	return fmt.Sprint(reply["token"]), nil
}

// request presents an invite as dev and expects to be told to wait - an
// invite pairs nothing until the device that issued it answers (046). It
// returns the connection, which is where the answer arrives, and the request.
func request(ctx context.Context, target link, dev device, token, platform string) (*conn, string, error) {
	c, err := dial(ctx, target, dev)
	if err != nil {
		return nil, "", err
	}
	if err := c.greeting(); err != nil {
		c.close()
		return nil, "", err
	}
	reply, err := c.call("pair", data{"token": token, "platform": platform})
	if err != nil {
		c.close()
		return nil, "", err
	}
	if reply["status"] != "pending" {
		c.close()
		return nil, "", fmt.Errorf("an invite must wait for Allow, got %v", reply)
	}
	requestID, _ := reply["request_id"].(string)
	if requestID == "" {
		c.close()
		return nil, "", fmt.Errorf("the pending reply names no request: %v", reply)
	}
	ok("%s waits for approval: %s", platform, requestID)
	return c, requestID, nil
}

// asked waits on the issuing device for the request to arrive.
func asked(issuer *conn, requestID, platform string) error {
	ev, err := issuer.event("device.pairRequested")
	if err != nil {
		return err
	}
	if ev["request_id"] != requestID || ev["platform"] != platform {
		return fmt.Errorf("the issuing device was asked about %v, want %s from %s", ev, requestID, platform)
	}
	ok("the first device is asked: New device: %s", platform)
	return nil
}

// inviteAndAllow adds a device by invite and allows it from the first one. The
// new device greets on the connection it waited on, and is returned greeted.
func inviteAndAllow(ctx context.Context, target link, issuer *conn, personID string) (*conn, error) {
	token, err := invite(issuer)
	if err != nil {
		return nil, err
	}
	phone, requestID, err := request(ctx, target, newDevice(), token, "android")
	if err != nil {
		return nil, err
	}
	if err := asked(issuer, requestID, "android"); err != nil {
		phone.close()
		return nil, err
	}
	if _, err := issuer.call("device.approve", data{"request_id": requestID, "allow": true}); err != nil {
		phone.close()
		return nil, err
	}
	resolved, err := phone.event("pair.resolved")
	if err != nil {
		phone.close()
		return nil, err
	}
	id, _ := resolved["identity"].(map[string]any)
	if resolved["outcome"] != "allowed" || id == nil || id["id"] != personID || id["created"] != false {
		phone.close()
		return nil, fmt.Errorf("Allow ended as %v, want allowed into %s with created=false", resolved, personID)
	}
	if ev, err := issuer.event("device.pairResolved"); err != nil || ev["request_id"] != requestID {
		phone.close()
		return nil, fmt.Errorf("the issuing device was not told the request is over: %v %v", ev, err)
	}
	ok("allowed: the new device joined the SAME person, created=false - no naming step")
	if _, err := phone.call("session.hello", data{"schema": 1}); err != nil {
		phone.close()
		return nil, err
	}
	ok("it greets on the connection it waited on")
	return phone, nil
}

// inviteAndDeny has a device ask and be declined: it is told, nothing is
// paired, and a repeat of pair says declined too.
func inviteAndDeny(ctx context.Context, target link, issuer *conn) error {
	token, err := invite(issuer)
	if err != nil {
		return err
	}
	dev := newDevice()
	tablet, requestID, err := request(ctx, target, dev, token, "ios")
	if err != nil {
		return err
	}
	defer tablet.close()
	if err := asked(issuer, requestID, "ios"); err != nil {
		return err
	}
	if _, err := issuer.call("device.approve", data{"request_id": requestID, "allow": false}); err != nil {
		return err
	}
	resolved, err := tablet.event("pair.resolved")
	if err != nil {
		return err
	}
	if resolved["outcome"] != "denied" {
		return fmt.Errorf("Deny ended as %v, want denied", resolved)
	}
	ok("declined: Your other device declined this request.")
	again, err := tablet.call("pair", data{"token": token, "platform": "ios"})
	if err != nil {
		return err
	}
	if again["status"] != "denied" {
		return fmt.Errorf("a repeat after Deny = %v, want denied", again)
	}
	if _, err := tablet.call("session.hello", data{"schema": 1}); err == nil {
		return errors.New("a declined device was let in")
	}
	ok("a repeat says declined, and its greeting is refused - nothing was paired")
	return nil
}

// talk has the person's two devices exchange a message through the server.
//
// Both connections belong to the SAME human being, so the echo must come back
// marked as their own - that is the whole assertion. Nothing here needs a
// second person: this machine has one, and talking to anybody else goes
// through a relay that does not exist yet.
//
// The chat's name and the send key are this run's own: a server the smoke has
// run against before holds the last run's chat - a name taken - and its send
// key, which would answer with the old message instead of sending a new one.
func talk(desktop, phone *conn, personID string) error {
	run := runSuffix()
	created, err := desktop.call("chat.create", data{"name": "Kitchen " + run})
	if err != nil {
		return err
	}
	chat := created["chat"].(map[string]any)
	ok("the chat %q is created on the desktop", chat["name"])

	if _, err := phone.call("message.send", data{
		"chat_id": chat["chat_id"], "client_message_id": "smoke-" + run,
		"body": data{"type": "text", "text": "the boiler is leaking"},
	}); err != nil {
		return err
	}
	msg, err := desktop.event("message.new")
	if err != nil {
		return err
	}
	if msg["author_id"] != personID {
		return fmt.Errorf("a message sent from her own phone came back as somebody else: %v", msg["author_id"])
	}
	ok("the desktop received it, authored by %v - her own", msg["author_label"])
	return nil
}

// --- the wire ---------------------------------------------------------------

type data = map[string]any

type link struct {
	// addrs are the link's direct addresses in its order: the public address
	// first when the link carries one, then the direct one (045).
	addrs []string
	// onion says the link names an onion service as well.
	onion bool
	// addr is the address this run talks to: the first of addrs that proved
	// the key, or the one -check was given.
	addr string
	// serverKey is the machine's Ed25519 key: the only answer to the channel
	// check this smoke run accepts.
	serverKey ed25519.PublicKey
	token     string
}

// parseLink reads a version-3 link with the server's own parser - the one its
// tests hold to the shared vectors.
func parseLink(raw string) (link, error) {
	parsed, err := server.ParsePairingLink(raw)
	if err != nil {
		return link{}, err
	}
	if len(parsed.Direct) == 0 {
		return link{}, errors.New("the link names no direct address, and this program has no Tor to try the onion one with")
	}
	return link{addrs: parsed.Direct, onion: parsed.Onion != nil, serverKey: parsed.ServerKey, token: parsed.Token}, nil
}

type conn struct {
	ws  *websocket.Conn
	ctx context.Context
	id  int
}

// dial opens one connection as dev the way the app does: the channel first,
// then the WebSocket over it. Every dial in this file goes through it, so there
// is no unchecked path to forget about - and the smoke run fails the same way
// a real device would if the machine answering is the wrong one.
func dial(ctx context.Context, target link, dev device) (*conn, error) {
	channel, err := openChannel(ctx, target, dev)
	if err != nil {
		return nil, err
	}
	// The HTTP client gets exactly the one connection the check passed on, and
	// no way to open another behind it.
	var once sync.Once
	transport := &http.Transport{
		DialTLSContext: func(context.Context, string, string) (net.Conn, error) {
			var handed net.Conn
			once.Do(func() { handed = channel })
			if handed == nil {
				return nil, errors.New("this client has one verified connection and it is in use")
			}
			return handed, nil
		},
	}
	ws, _, err := websocket.Dial(ctx, "wss://"+target.addr+"/ws", &websocket.DialOptions{HTTPClient: &http.Client{Transport: transport}})
	if err != nil {
		_ = channel.Close()
		return nil, fmt.Errorf("dial %s: %w", target.addr, err)
	}
	ws.SetReadLimit(1 << 20)
	return &conn{ws: ws, ctx: ctx}, nil
}

// openChannel is the channel of contract §1, client side: TCP, TLS 1.3 that
// checks no certificate - the certificate is technical and names nothing -
// then the channel check over the session's exporter, with this device's key,
// accepting only the server key the link named. Nothing else is written until
// that check passed.
func openChannel(ctx context.Context, target link, dev device) (*tls.Conn, error) {
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	raw, err := (&net.Dialer{}).DialContext(ctx, "tcp", target.addr)
	if err != nil {
		return nil, fmt.Errorf("dial %s: %w", target.addr, err)
	}
	tc := tls.Client(raw, &tls.Config{
		//nolint:gosec // the certificate is technical by design; the channel check below is what decides
		InsecureSkipVerify:     true,
		MinVersion:             tls.VersionTLS13,
		NextProtos:             []string{"http/1.1"},
		SessionTicketsDisabled: true,
	})
	if err := tc.HandshakeContext(ctx); err != nil {
		_ = raw.Close()
		return nil, fmt.Errorf("tls with %s: %w", target.addr, err)
	}
	state := tc.ConnectionState()
	binding, err := state.ExportKeyingMaterial(eidolon.ExporterLabel, nil, eidolon.BindingSize)
	if err != nil {
		_ = raw.Close()
		return nil, fmt.Errorf("channel binding: %w", err)
	}
	if err := eidolon.Initiate(ctx, tc, binding, dev.priv, target.serverKey); err != nil {
		_ = raw.Close()
		if errors.Is(err, eidolon.ErrUnauthorized) {
			return nil, fmt.Errorf("the machine at %s is not the one the link names: %w", target.addr, err)
		}
		return nil, fmt.Errorf("channel check with %s: %w", target.addr, err)
	}
	if err := tc.SetDeadline(time.Time{}); err != nil {
		_ = raw.Close()
		return nil, fmt.Errorf("clear the channel deadline: %w", err)
	}
	return tc, nil
}

func (c *conn) close() { _ = c.ws.Close(websocket.StatusNormalClosure, "") }

func (c *conn) read() (data, error) {
	_, raw, err := c.ws.Read(c.ctx)
	if err != nil {
		return nil, fmt.Errorf("read: %w", err)
	}
	var frame data
	if err := json.Unmarshal(raw, &frame); err != nil {
		return nil, fmt.Errorf("undecodable frame: %w", err)
	}
	return frame, nil
}

// greeting takes the server's opening frame, which is the schema and nothing
// else: the channel already proved who is on each end.
func (c *conn) greeting() error {
	frame, err := c.read()
	if err != nil {
		return err
	}
	if _, ok := frame["srv"].(data); !ok {
		return fmt.Errorf("expected a server greeting, got %v", frame)
	}
	return nil
}

// call sends a command and waits for ITS reply, letting events past.
func (c *conn) call(cmd string, body data) (data, error) {
	c.id++
	id := c.id
	frame, err := json.Marshal(data{"id": id, "cmd": cmd, "data": body})
	if err != nil {
		return nil, err
	}
	if err := c.ws.Write(c.ctx, websocket.MessageText, frame); err != nil {
		return nil, fmt.Errorf("send %s: %w", cmd, err)
	}
	for range 50 {
		reply, err := c.read()
		if err != nil {
			return nil, err
		}
		got, ok := reply["id"].(float64)
		if !ok || int(got) != id {
			continue
		}
		if accepted, _ := reply["ok"].(bool); !accepted {
			return nil, fmt.Errorf("%s refused: %v", cmd, reply["error"])
		}
		if payload, ok := reply["data"].(data); ok {
			return payload, nil
		}
		return data{}, nil
	}
	return nil, fmt.Errorf("no reply to %s", cmd)
}

// event waits for one named event, letting everything else past.
func (c *conn) event(name string) (data, error) {
	for range 50 {
		frame, err := c.read()
		if err != nil {
			return nil, err
		}
		if got, ok := frame["event"].(string); ok && got == name {
			payload, _ := frame["data"].(data)
			return payload, nil
		}
	}
	return nil, fmt.Errorf("no %s event arrived", name)
}

// device is one installation's key pair; the channel check proves it.
type device struct {
	priv ed25519.PrivateKey
}

func newDevice() device {
	_, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		panic(err)
	}
	return device{priv: priv}
}

// greet opens a connection as a paired device and greets. The greeting names
// no key: the server knows the device by the channel it came through.
func greet(ctx context.Context, target link, dev device) (*conn, error) {
	c, err := dial(ctx, target, dev)
	if err != nil {
		return nil, err
	}
	if err := c.greeting(); err != nil {
		c.close()
		return nil, err
	}
	if _, err := c.call("session.hello", data{"schema": 1}); err != nil {
		c.close()
		return nil, err
	}
	return c, nil
}

// runSuffix names one run of the smoke: four random bytes in hex.
func runSuffix() string {
	var b [4]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b[:])
}

func step(n int, what string) { fmt.Printf("\n  %d. %s\n", n, what) }

func ok(format string, args ...any) { fmt.Printf("     ok  "+format+"\n", args...) }
