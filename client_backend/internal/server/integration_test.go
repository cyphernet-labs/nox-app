package server

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"

	"nox.app/client-backend/internal/protocol"
)

// wsClient is a test-side protocol client over one connection.
type wsClient struct {
	t         *testing.T
	conn      *websocket.Conn
	ctx       context.Context
	challenge string
}

func dialWS(t *testing.T, ts *httptest.Server) *wsClient {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	t.Cleanup(cancel)
	conn, _, err := websocket.Dial(ctx, ts.URL+"/ws", nil)
	if err != nil {
		t.Fatalf("websocket.Dial: %v", err)
	}
	t.Cleanup(func() { _ = conn.Close(websocket.StatusNormalClosure, "") })
	conn.SetReadLimit(1 << 20)
	return &wsClient{t: t, conn: conn, ctx: ctx}
}

func (c *wsClient) send(frame string) {
	c.t.Helper()
	if err := c.conn.Write(c.ctx, websocket.MessageText, []byte(frame)); err != nil {
		c.t.Fatalf("write frame: %v", err)
	}
}

func (c *wsClient) read() map[string]json.RawMessage {
	c.t.Helper()
	rctx, cancel := context.WithTimeout(c.ctx, 5*time.Second)
	defer cancel()
	_, raw, err := c.conn.Read(rctx)
	if err != nil {
		c.t.Fatalf("read frame: %v", err)
	}
	var frame map[string]json.RawMessage
	if err := json.Unmarshal(raw, &frame); err != nil {
		c.t.Fatalf("frame is not a JSON object: %v (%s)", err, raw)
	}
	return frame
}

// expectGreeting consumes the srv greeting frame and remembers the challenge,
// which every later greeting on this connection has to sign.
func (c *wsClient) expectGreeting() {
	c.t.Helper()
	frame := c.read()
	raw, ok := frame["srv"]
	if !ok {
		c.t.Fatalf("first frame is not a greeting: %v", frame)
	}
	var body struct {
		Challenge string `json:"challenge"`
	}
	mustUnmarshal(c.t, raw, &body)
	c.challenge = body.Challenge
}

// device is one test device's key pair. The private half never leaves it, the
// same way it never leaves a real installation.
type device struct {
	pub  string
	priv ed25519.PrivateKey
}

func newDevice(t *testing.T) *device {
	t.Helper()
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("generate device key: %v", err)
	}
	return &device{pub: base64.StdEncoding.EncodeToString(pub), priv: priv}
}

// sign produces what a real client puts in `signature`: the signature over the
// prefixed RAW challenge bytes.
func (d *device) sign(t *testing.T, challenge string) string {
	t.Helper()
	raw, err := base64.StdEncoding.DecodeString(challenge)
	if err != nil {
		t.Fatalf("decode challenge: %v", err)
	}
	return base64.StdEncoding.EncodeToString(
		ed25519.Sign(d.priv, append([]byte(challengePrefix), raw...)))
}

// claimDevice pairs a fresh device by claiming the server. Returns the device
// and the identity the pairing produced.
func claimDevice(t *testing.T, ts *httptest.Server, srv *Server) (*device, map[string]json.RawMessage) {
	t.Helper()
	ctx := context.Background()
	if _, err := srv.store.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	token, err := srv.store.IssueClaimToken(ctx, time.Now().Unix())
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	return pairDevice(t, ts, token)
}

// pairDevice presents a token on a fresh connection, which is the one command
// allowed before a greeting.
func pairDevice(t *testing.T, ts *httptest.Server, token string) (*device, map[string]json.RawMessage) {
	t.Helper()
	d := newDevice(t)
	c := dialWS(t, ts)
	c.expectGreeting()
	c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"device_key":%q,"platform":"test"}}`, token, d.pub))
	data := c.expectOK(1)
	_ = c.conn.Close(websocket.StatusNormalClosure, "")
	return d, data
}

// greet performs a signed session.hello for an already paired device.
func (c *wsClient) greet(t *testing.T, id int, d *device, extra string) map[string]json.RawMessage {
	t.Helper()
	return c.hello(id, fmt.Sprintf(`,"device_key":%q,"signature":%q%s`, d.pub, d.sign(t, c.challenge), extra))
}

// hello performs session.hello and returns the reply data.
func (c *wsClient) hello(id int, extra string) map[string]json.RawMessage {
	c.t.Helper()
	c.send(fmt.Sprintf(`{"id":%d,"cmd":"session.hello","data":{"schema":1%s}}`, id, extra))
	return c.expectOK(id)
}

// expectOK reads frames until the reply for id arrives (skipping events) and
// asserts ok:true, returning its data object.
func (c *wsClient) expectOK(id int) map[string]json.RawMessage {
	c.t.Helper()
	reply := c.expectReply(id)
	var ok bool
	mustUnmarshal(c.t, reply["ok"], &ok)
	if !ok {
		c.t.Fatalf("reply %d not ok: %v", id, rawString(reply["error"]))
	}
	var data map[string]json.RawMessage
	mustUnmarshal(c.t, reply["data"], &data)
	return data
}

// expectErr reads the reply for id and asserts the error code.
func (c *wsClient) expectErr(id int, code string) {
	c.t.Helper()
	reply := c.expectReply(id)
	var ok bool
	mustUnmarshal(c.t, reply["ok"], &ok)
	if ok {
		c.t.Fatalf("reply %d unexpectedly ok", id)
	}
	var wireErr protocol.WireError
	mustUnmarshal(c.t, reply["error"], &wireErr)
	if wireErr.Code != code {
		c.t.Fatalf("error code = %q, want %q", wireErr.Code, code)
	}
}

func (c *wsClient) expectReply(id int) map[string]json.RawMessage {
	c.t.Helper()
	for range 50 {
		frame := c.read()
		if _, isEvent := frame["event"]; isEvent {
			continue
		}
		var gotID int
		mustUnmarshal(c.t, frame["id"], &gotID)
		if gotID != id {
			c.t.Fatalf("reply id = %d, want %d", gotID, id)
		}
		return frame
	}
	c.t.Fatalf("no reply for id %d", id)
	return nil
}

// expectEvent reads frames until an event arrives and returns (seq, type, data).
func (c *wsClient) expectEvent() (int64, string, map[string]json.RawMessage) {
	c.t.Helper()
	for range 50 {
		frame := c.read()
		if _, isEvent := frame["event"]; !isEvent {
			continue
		}
		var seq int64
		var name string
		var data map[string]json.RawMessage
		mustUnmarshal(c.t, frame["seq"], &seq)
		mustUnmarshal(c.t, frame["event"], &name)
		mustUnmarshal(c.t, frame["data"], &data)
		return seq, name, data
	}
	c.t.Fatal("no event frame arrived")
	return 0, "", nil
}

func mustUnmarshal(t *testing.T, raw json.RawMessage, v any) {
	t.Helper()
	if raw == nil {
		t.Fatal("missing expected JSON field")
	}
	if err := json.Unmarshal(raw, v); err != nil {
		t.Fatalf("unmarshal %s: %v", raw, err)
	}
}

func rawString(raw json.RawMessage) string {
	if raw == nil {
		return "<nil>"
	}
	return string(raw)
}

func TestStoryOneLiveExchange(t *testing.T) {
	ts, _ := newTestServer(t)

	anna := dialWS(t, ts)
	anna.expectGreeting()
	helloData := anna.hello(1, `,"label":"Anna"`)

	var ident identity
	mustUnmarshal(t, helloData["identity"], &ident)
	// The author id is the person, not the name: a rename must not rewrite who
	// owns the history, and a name must not double as credentials.
	if ident.Label != "Anna" {
		t.Fatalf("identity label = %q, want Anna", ident.Label)
	}
	if !regexp.MustCompile(`^u_[0-9a-f]{16}$`).MatchString(ident.ID) {
		t.Fatalf("identity id = %q, want the u_<16 hex> shape", ident.ID)
	}

	bob := dialWS(t, ts)
	bob.expectGreeting()
	bob.hello(1, `,"label":"Bob"`)

	createData := anna.expectOKAfter(2, `{"id":2,"cmd":"chat.create","data":{"name":"smoke"}}`)
	var chat protocol.Chat
	mustUnmarshal(t, createData["chat"], &chat)
	if chat.CreatedByLabel != "Anna" || chat.Name != "smoke" {
		t.Fatalf("chat = %+v", chat)
	}

	seq, name, evData := bob.expectEvent()
	if name != protocol.EventChatCreated || seq != 1 {
		t.Fatalf("bob got event %s seq %d, want chat.created seq 1", name, seq)
	}
	var evChat protocol.Chat
	mustUnmarshal(t, evData["chat_id"], &evChat.ChatID)
	if evChat.ChatID != chat.ChatID {
		t.Fatalf("event chat_id = %s, want %s", evChat.ChatID, chat.ChatID)
	}

	sendFrame := fmt.Sprintf(
		`{"id":3,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"a1","body":{"type":"text","text":"hello"}}}`,
		chat.ChatID)
	before := time.Now()
	sendData := anna.expectOKAfter(3, sendFrame)

	var echo protocol.Message
	mustUnmarshal(t, sendData["message"], &echo)
	if echo.ClientMessageID != "a1" || echo.AuthorLabel != "Anna" || echo.Seq != 2 {
		t.Fatalf("echo = %+v", echo)
	}

	seq, name, evData = bob.expectEvent()
	latency := time.Since(before)
	if name != protocol.EventMessageNew || seq != 2 {
		t.Fatalf("bob got event %s seq %d, want message.new seq 2", name, seq)
	}
	if latency >= time.Second {
		t.Fatalf("event delivery took %v, want < 1s (SC-002)", latency)
	}
	var evMsgID string
	mustUnmarshal(t, evData["message_id"], &evMsgID)
	if evMsgID != echo.MessageID {
		t.Fatalf("event message_id = %s, want %s", evMsgID, echo.MessageID)
	}
	// Contract §5: client_message_id belongs to the author's own frames only.
	if _, leaked := evData["client_message_id"]; leaked {
		t.Fatal("bob's message.new carries the author's client_message_id")
	}
}

// expectOKAfter sends a frame and returns the OK reply data for id.
func (c *wsClient) expectOKAfter(id int, frame string) map[string]json.RawMessage {
	c.t.Helper()
	c.send(frame)
	return c.expectOK(id)
}

func TestStoryOneDuplicateSendIsIdempotent(t *testing.T) {
	ts, _ := newTestServer(t)

	anna := dialWS(t, ts)
	anna.expectGreeting()
	anna.hello(1, ``)
	createData := anna.expectOKAfter(2, `{"id":2,"cmd":"chat.create","data":{"name":"dup"}}`)
	var chat protocol.Chat
	mustUnmarshal(t, createData["chat"], &chat)

	send := func(id int) protocol.Message {
		data := anna.expectOKAfter(id, fmt.Sprintf(
			`{"id":%d,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"same","body":{"type":"text","text":"x"}}}`,
			id, chat.ChatID))
		var msg protocol.Message
		mustUnmarshal(t, data["message"], &msg)
		return msg
	}

	first := send(3)
	second := send(4)
	if first.MessageID != second.MessageID || first.Seq != second.Seq {
		t.Fatalf("duplicate send produced a different message: %+v vs %+v", first, second)
	}

	// A watcher connected afterwards replays exactly two events: chat.created
	// and ONE message.new - the duplicate produced none.
	watcher := dialWS(t, ts)
	watcher.expectGreeting()
	watcher.hello(1, `,"since":0`)
	if seq, name, _ := watcher.expectEvent(); name != protocol.EventChatCreated || seq != 1 {
		t.Fatalf("replay[0] = %s/%d", name, seq)
	}
	if seq, name, _ := watcher.expectEvent(); name != protocol.EventMessageNew || seq != 2 {
		t.Fatalf("replay[1] = %s/%d", name, seq)
	}
}

func TestStoryOneNameTakenCaseInsensitiveAndConcurrentRace(t *testing.T) {
	ts, _ := newTestServer(t)

	anna := dialWS(t, ts)
	anna.expectGreeting()
	anna.hello(1, ``)
	anna.expectOKAfter(2, `{"id":2,"cmd":"chat.create","data":{"name":"General"}}`)

	anna.send(`{"id":3,"cmd":"chat.create","data":{"name":"general"}}`)
	anna.expectErr(3, protocol.ErrNameTaken)
	anna.send(`{"id":4,"cmd":"chat.create","data":{"name":"GENERAL"}}`)
	anna.expectErr(4, protocol.ErrNameTaken)

	// Concurrent same-name creates from two connections: exactly one wins.
	// Both frames are written before either reply is read, so the server
	// processes them concurrently; reads stay on the test goroutine.
	c1 := dialWS(t, ts)
	c1.expectGreeting()
	c1.hello(1, ``)
	c2 := dialWS(t, ts)
	c2.expectGreeting()
	c2.hello(1, ``)

	c1.send(`{"id":9,"cmd":"chat.create","data":{"name":"Race"}}`)
	c2.send(`{"id":9,"cmd":"chat.create","data":{"name":"Race"}}`)

	wins := 0
	for _, c := range []*wsClient{c1, c2} {
		reply := c.expectReply(9)
		var ok bool
		mustUnmarshal(t, reply["ok"], &ok)
		if ok {
			wins++
		}
	}
	if wins != 1 {
		t.Fatalf("concurrent create wins = %d, want exactly 1", wins)
	}
}

func TestStoryOneProtocolNegatives(t *testing.T) {
	ts, _ := newTestServer(t)

	t.Run("command before hello is rejected", func(t *testing.T) {
		c := dialWS(t, ts)
		c.expectGreeting()
		c.send(`{"id":1,"cmd":"chat.create","data":{"name":"early"}}`)
		c.expectErr(1, protocol.ErrInvalidRequest)
	})

	t.Run("unknown command", func(t *testing.T) {
		c := dialWS(t, ts)
		c.expectGreeting()
		c.hello(1, ``)
		c.send(`{"id":2,"cmd":"nope","data":{}}`)
		c.expectErr(2, protocol.ErrInvalidRequest)
	})

	t.Run("duplicate hello", func(t *testing.T) {
		c := dialWS(t, ts)
		c.expectGreeting()
		c.hello(1, ``)
		c.send(`{"id":2,"cmd":"session.hello","data":{"schema":1}}`)
		c.expectErr(2, protocol.ErrInvalidRequest)
	})

	t.Run("schema mismatch", func(t *testing.T) {
		c := dialWS(t, ts)
		c.expectGreeting()
		c.send(`{"id":1,"cmd":"session.hello","data":{"schema":99}}`)
		c.expectErr(1, protocol.ErrUnsupportedSchema)
	})

	t.Run("oversized body", func(t *testing.T) {
		c := dialWS(t, ts)
		c.expectGreeting()
		c.hello(1, ``)
		data := c.expectOKAfter(2, `{"id":2,"cmd":"chat.create","data":{"name":"big"}}`)
		var chat protocol.Chat
		mustUnmarshal(t, data["chat"], &chat)
		big := strings.Repeat("x", 70000)
		c.send(fmt.Sprintf(
			`{"id":3,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"b1","body":{"type":"text","text":%q}}}`,
			chat.ChatID, big))
		c.expectErr(3, protocol.ErrPayloadTooLarge)
	})

	t.Run("send to missing chat", func(t *testing.T) {
		c := dialWS(t, ts)
		c.expectGreeting()
		c.hello(1, ``)
		c.send(`{"id":2,"cmd":"message.send","data":{"chat_id":"c_missing","client_message_id":"m1","body":{"type":"text","text":"x"}}}`)
		c.expectErr(2, protocol.ErrNotFound)
	})

	t.Run("unparseable frame closes the connection, server survives", func(t *testing.T) {
		c := dialWS(t, ts)
		c.expectGreeting()
		c.send(`[not, an, object]`)
		waitClosed(t, c, websocket.StatusProtocolError)
		assertHealthy(t, ts)
	})

	t.Run("frame with id but no cmd gets invalid_request, connection survives", func(t *testing.T) {
		c := dialWS(t, ts)
		c.expectGreeting()
		c.send(`{"id":7,"data":{}}`)
		c.expectErr(7, protocol.ErrInvalidRequest)
		c.hello(8, ``)
	})

	t.Run("read-limit overflow closes the connection, server survives", func(t *testing.T) {
		c := dialWS(t, ts)
		c.expectGreeting()
		huge := strings.Repeat("a", 200000) // above max_frame_bytes 131072
		_ = c.conn.Write(c.ctx, websocket.MessageText, []byte(`{"id":1,"cmd":"session.hello","data":{"schema":1,"label":"`+huge+`"}}`))
		waitClosed(t, c, websocket.StatusMessageTooBig)
		assertHealthy(t, ts)
	})
}

func TestStoryOneDefaultLabelFallback(t *testing.T) {
	ts, _ := newTestServer(t)

	c := dialWS(t, ts)
	c.expectGreeting()
	data := c.hello(1, ``)
	var ident identity
	mustUnmarshal(t, data["identity"], &ident)
	// The design spec asks for User<random>; the counter this replaced lived in
	// process memory, so it both repeated names after a restart and reset to
	// User1.
	if !regexp.MustCompile(`^User[0-9]{4}$`).MatchString(ident.Label) {
		t.Fatalf("assigned label = %q, want the User<4 digits> shape", ident.Label)
	}

	// A second nameless connection is a different person. Their NAMES are not
	// asserted to differ: neither connection writes a users row (both are
	// ephemeral until they send something), so the de-duplication in
	// assignedLabelTx has nothing to see and a collision is possible by design -
	// labels are not unique, by owner decision.
	c2 := dialWS(t, ts)
	c2.expectGreeting()
	var ident2 identity
	mustUnmarshal(t, c2.hello(1, ``)["identity"], &ident2)
	if ident2.ID == ident.ID {
		t.Fatalf("two nameless connections share the identity %q", ident.ID)
	}
}

func waitClosed(t *testing.T, c *wsClient, want websocket.StatusCode) {
	t.Helper()
	rctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	for {
		_, _, err := c.conn.Read(rctx)
		if err != nil {
			if got := websocket.CloseStatus(err); got != want {
				t.Fatalf("close status = %v, want %v", got, want)
			}
			return
		}
	}
}

func assertHealthy(t *testing.T, ts *httptest.Server) {
	t.Helper()
	resp, err := http.Get(ts.URL + "/health")
	if err != nil {
		t.Fatalf("health after failure: %v", err)
	}
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("health status = %d", resp.StatusCode)
	}
}
