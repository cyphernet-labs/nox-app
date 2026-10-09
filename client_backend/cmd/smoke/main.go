// Command smoke walks the whole stage-2 flow against a RUNNING noxd and says
// whether it works.
//
// It exists because the flow crosses two devices and a real socket, which no
// unit test reaches end to end and no person wants to click through twice
// before a demo. Point it at the claim link a fresh server printed and it
// claims the machine, adds a second device of the same person, and has the two
// of them exchange a message.
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
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/coder/websocket"

	"nox.app/client-backend/internal/eidolon"
	"nox.app/client-backend/internal/server"
)

const usage = `usage: smoke <pairing link>

Give it the claim link a freshly started noxd printed, or the one on its
service page. The server must have no owner yet.`

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, usage)
		os.Exit(2)
	}
	if err := run(os.Args[1]); err != nil {
		fmt.Fprintf(os.Stderr, "\n  FAILED: %v\n\n", err)
		os.Exit(1)
	}
}

func run(rawLink string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()

	target, err := parseLink(rawLink)
	if err != nil {
		return err
	}
	fmt.Printf("\nserver %s, key %s\n", target.addr, base64.StdEncoding.EncodeToString(target.serverKey))

	step(1, "The owner claims the server")
	owner := newDevice()
	ownerID, err := claim(ctx, target, owner)
	if err != nil {
		return err
	}

	ownerConn, err := greet(ctx, target, owner)
	if err != nil {
		return err
	}
	defer ownerConn.close()
	if _, err := ownerConn.call("identity.setLabel", data{"label": "Anna"}); err != nil {
		return err
	}
	ok("named: Anna")

	step(2, "The owner adds a second device of their own")
	phone, err := addDevice(ctx, target, ownerConn, ownerID)
	if err != nil {
		return err
	}
	phoneConn, err := greet(ctx, target, phone)
	if err != nil {
		return err
	}
	defer phoneConn.close()
	devices, err := ownerConn.call("device.list", data{})
	if err != nil {
		return err
	}
	ok("device.list shows %d devices", len(devices["devices"].([]any)))

	step(3, "The two devices exchange a message")
	if err := talk(ownerConn, phoneConn, ownerID); err != nil {
		return err
	}

	fmt.Printf("\n  every step passed\n\n")
	return nil
}

func claim(ctx context.Context, target link, dev device) (string, error) {
	c, err := dial(ctx, target, dev)
	if err != nil {
		return "", err
	}
	defer c.close()
	if err := c.greeting(); err != nil {
		return "", err
	}
	reply, err := c.call("pair", data{"token": target.token, "platform": "macos"})
	if err != nil {
		return "", err
	}
	id, okID := reply["identity"].(map[string]any)
	if !okID {
		return "", fmt.Errorf("the claim carried no identity: %v", reply)
	}
	if id["created"] != true {
		return "", fmt.Errorf("a claim must create the person, got %v", id)
	}
	ok("claimed: created=%v", id["created"])
	return id["id"].(string), nil
}

func addDevice(ctx context.Context, target link, owner *conn, ownerID string) (device, error) {
	invite, err := owner.call("device.invite", data{})
	if err != nil {
		return device{}, err
	}
	if _, err := server.ParsePairingLink(fmt.Sprint(invite["link"])); err != nil {
		return device{}, fmt.Errorf("the invite link does not read back: %w", err)
	}
	// Pairing through the onion service waits for 045, so no invite may say
	// it does.
	if invite["onion"] != false {
		return device{}, fmt.Errorf("the invite says onion=%v, want false", invite["onion"])
	}
	ok("device invite issued (10 minutes), a version-3 link")

	dev := newDevice()
	c, err := dial(ctx, target, dev)
	if err != nil {
		return device{}, err
	}
	defer c.close()
	if err := c.greeting(); err != nil {
		return device{}, err
	}
	reply, err := c.call("pair", data{"token": invite["token"], "platform": "android"})
	if err != nil {
		return device{}, err
	}
	id := reply["identity"].(map[string]any)
	if id["id"] != ownerID {
		return device{}, errors.New("the second device joined a different person")
	}
	if id["created"] == true {
		return device{}, errors.New("a device invite created a person")
	}
	ok("paired to the SAME person, created=false - no naming step")
	return dev, nil
}

// talk has the person's two devices exchange a message through the server.
//
// Both connections belong to the SAME human being, so the echo must come back
// marked as their own - that is the whole assertion. Nothing here needs a
// second person: this machine has one, and talking to anybody else goes
// through a relay that does not exist yet.
func talk(desktop, phone *conn, ownerID string) error {
	created, err := desktop.call("chat.create", data{"name": "Kitchen"})
	if err != nil {
		return err
	}
	chat := created["chat"].(map[string]any)
	ok("Anna created the chat %q on her desktop", chat["name"])

	if _, err := phone.call("message.send", data{
		"chat_id": chat["chat_id"], "client_message_id": "smoke-1",
		"body": data{"type": "text", "text": "the boiler is leaking"},
	}); err != nil {
		return err
	}
	msg, err := desktop.event("message.new")
	if err != nil {
		return err
	}
	if msg["author_id"] != ownerID {
		return fmt.Errorf("a message sent from her own phone came back as somebody else: %v", msg["author_id"])
	}
	ok("the desktop received it, authored by %v - her own", msg["author_label"])
	return nil
}

// --- the wire ---------------------------------------------------------------

type data = map[string]any

type link struct {
	// addr is the first direct address of the link - where a device at home
	// starts.
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
		return link{}, errors.New("the link names no direct address, and pairing works only at home")
	}
	return link{addr: parsed.Direct[0], serverKey: parsed.ServerKey, token: parsed.Token}, nil
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

func step(n int, what string) { fmt.Printf("\n  %d. %s\n", n, what) }

func ok(format string, args ...any) { fmt.Printf("     ok  "+format+"\n", args...) }
