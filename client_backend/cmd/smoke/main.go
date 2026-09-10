// Command smoke walks the whole stage-2 flow against a RUNNING noxd and says
// whether it works.
//
// It exists because the flow crosses two devices and a real socket, which no
// unit test reaches end to end and no person wants to click through twice
// before a demo. Point it at the claim link a fresh server printed and it
// claims the machine, adds a second device of the same person, and has the two
// of them exchange a message.
//
// It talks to the wire directly rather than through the app: what is being
// checked is the server, and a failure here is the server's.
package main

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"strings"
	"time"

	"github.com/coder/websocket"
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
	fmt.Printf("\nserver %s\n", target.addr)

	step(1, "The owner claims the server")
	owner := newDevice()
	ownerID, err := claim(ctx, target, owner)
	if err != nil {
		return err
	}

	ownerConn, err := greet(ctx, target.addr, owner)
	if err != nil {
		return err
	}
	defer ownerConn.close()
	if _, err := ownerConn.call("identity.setLabel", data{"label": "Anna"}); err != nil {
		return err
	}
	ok("named: Anna")

	step(2, "The owner adds a second device of their own")
	phone, err := addDevice(ctx, target.addr, ownerConn, ownerID)
	if err != nil {
		return err
	}
	phoneConn, err := greet(ctx, target.addr, phone)
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
	c, err := dial(ctx, target.addr)
	if err != nil {
		return "", err
	}
	defer c.close()
	if _, err := c.greeting(); err != nil {
		return "", err
	}
	reply, err := c.call("pair", data{"token": target.token, "device_key": dev.pub, "platform": "macos"})
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

func addDevice(ctx context.Context, addr string, owner *conn, ownerID string) (device, error) {
	invite, err := owner.call("device.invite", data{})
	if err != nil {
		return device{}, err
	}
	ok("device invite issued (10 minutes)")

	dev := newDevice()
	c, err := dial(ctx, addr)
	if err != nil {
		return device{}, err
	}
	defer c.close()
	if _, err := c.greeting(); err != nil {
		return device{}, err
	}
	reply, err := c.call("pair", data{"token": invite["token"], "device_key": dev.pub, "platform": "android"})
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
	addr  string
	token string
}

// parseLink reads the pairing link's payload: version, host, port, server key,
// token (contract §8A).
func parseLink(raw string) (link, error) {
	if i := strings.Index(raw, "#"); i >= 0 {
		raw = raw[i+1:]
	}
	payload, err := base64.RawURLEncoding.DecodeString(strings.TrimSpace(raw))
	if err != nil {
		return link{}, fmt.Errorf("the link is not a pairing link: %w", err)
	}
	if len(payload) < 3 || payload[0] != 1 {
		return link{}, errors.New("unknown pairing link version")
	}
	at := 1
	var host string
	switch payload[at] {
	case 1:
		at++
		if len(payload) < at+4 {
			return link{}, errors.New("truncated link")
		}
		host = net.IP(payload[at : at+4]).String()
		at += 4
	case 2:
		at++
		if len(payload) < at+16 {
			return link{}, errors.New("truncated link")
		}
		host = "[" + net.IP(payload[at:at+16]).String() + "]"
		at += 16
	case 3:
		at++
		size := int(payload[at])
		at++
		if len(payload) < at+size {
			return link{}, errors.New("truncated link")
		}
		host = string(payload[at : at+size])
		at += size
	default:
		return link{}, errors.New("unknown host type in the link")
	}
	if len(payload) < at+2+32+16 {
		return link{}, errors.New("truncated link")
	}
	port := binary.BigEndian.Uint16(payload[at : at+2])
	at += 2 + 32 // the server key is checked by TLS pinning, not here
	token := base64.RawURLEncoding.EncodeToString(payload[at : at+16])
	return link{addr: net.JoinHostPort(host, fmt.Sprint(port)), token: token}, nil
}

type conn struct {
	ws  *websocket.Conn
	ctx context.Context
	id  int
}

func dial(ctx context.Context, addr string) (*conn, error) {
	ws, _, err := websocket.Dial(ctx, "ws://"+addr+"/ws", nil)
	if err != nil {
		return nil, fmt.Errorf("dial %s: %w", addr, err)
	}
	ws.SetReadLimit(1 << 20)
	return &conn{ws: ws, ctx: ctx}, nil
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

// greeting takes the server's opening frame and returns its challenge.
func (c *conn) greeting() (string, error) {
	frame, err := c.read()
	if err != nil {
		return "", err
	}
	srv, ok := frame["srv"].(data)
	if !ok {
		return "", fmt.Errorf("expected a server greeting, got %v", frame)
	}
	return srv["challenge"].(string), nil
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

type device struct {
	pub  string
	priv ed25519.PrivateKey
}

func newDevice() device {
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		panic(err)
	}
	return device{pub: base64.StdEncoding.EncodeToString(pub), priv: priv}
}

// greet opens a connection and completes a SIGNED greeting for a paired device.
func greet(ctx context.Context, addr string, dev device) (*conn, error) {
	c, err := dial(ctx, addr)
	if err != nil {
		return nil, err
	}
	challenge, err := c.greeting()
	if err != nil {
		c.close()
		return nil, err
	}
	raw, err := base64.StdEncoding.DecodeString(challenge)
	if err != nil {
		c.close()
		return nil, fmt.Errorf("undecodable challenge: %w", err)
	}
	signature := base64.StdEncoding.EncodeToString(ed25519.Sign(dev.priv, append([]byte("nox/challenge/v1:"), raw...)))
	if _, err := c.call("session.hello", data{"schema": 1, "device_key": dev.pub, "signature": signature}); err != nil {
		c.close()
		return nil, err
	}
	return c, nil
}

func step(n int, what string) { fmt.Printf("\n  %d. %s\n", n, what) }

func ok(format string, args ...any) { fmt.Printf("     ok  "+format+"\n", args...) }
