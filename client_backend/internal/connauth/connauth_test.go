package connauth

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"testing"
	"time"

	"nox.app/client-backend/internal/securebox"
)

var box = securebox.New()

func keys(t *testing.T) securebox.KeyPair {
	t.Helper()
	pair, err := box.GenerateKeys()
	if err != nil {
		t.Fatal(err)
	}
	return pair
}

type served struct {
	device securebox.PublicKey
	rest   net.Conn
	err    error
}

// serve runs Respond on one end of a pipe and returns the other.
func serve(t *testing.T, ctx context.Context, server securebox.KeyPair) (net.Conn, <-chan served) {
	t.Helper()
	deviceEnd, serverEnd := net.Pipe()
	t.Cleanup(func() { _ = deviceEnd.Close(); _ = serverEnd.Close() })
	out := make(chan served, 1)
	go func() {
		device, rest, err := Respond(ctx, serverEnd, box, server.PrivateKey)
		if err != nil {
			_ = serverEnd.Close()
		}
		out <- served{device, rest, err}
	}()
	return deviceEnd, out
}

func TestADeviceAndTheServerPassAndTheConnectionGoesOn(t *testing.T) {
	server, device := keys(t), keys(t)
	conn, done := serve(t, context.Background(), server)
	rest, err := Initiate(context.Background(), conn, box, device.PrivateKey, "192.168.1.61:8443", server.PublicKey)
	if err != nil {
		t.Fatal(err)
	}
	got := <-done
	if got.err != nil {
		t.Fatal(got.err)
	}
	if got.device != device.PublicKey {
		t.Fatal("the server proved another device key")
	}
	// What comes next on the connection is the connection's, both ways.
	go func() { _, _ = rest.Write([]byte("GET /ws")) }()
	buf := make([]byte, 7)
	if _, err := io.ReadFull(got.rest, buf); err != nil || string(buf) != "GET /ws" {
		t.Fatalf("after the check: %q %v", buf, err)
	}
}

func TestAnotherServersKeyStopsTheDeviceBeforeAuth2(t *testing.T) {
	server, device, expected := keys(t), keys(t), keys(t)
	conn, done := serve(t, context.Background(), server)
	if _, err := Initiate(context.Background(), conn, box, device.PrivateKey, "h:1", expected.PublicKey); !errors.Is(err, ErrWrongServer) {
		t.Fatalf("Initiate: %v", err)
	}
	_ = conn.Close()
	// The server is still waiting for /auth2, which never came.
	if got := <-done; got.err == nil || errors.Is(got.err, ErrSignature) {
		t.Fatalf("the server: %v", got.err)
	}
}

// exchange writes raw bytes and reads one answer.
func exchange(t *testing.T, conn net.Conn, br *bufio.Reader, raw string) *http.Response {
	t.Helper()
	go func() { _, _ = io.WriteString(conn, raw) }()
	resp, err := http.ReadResponse(br, nil)
	if err != nil {
		t.Fatalf("no answer to %q: %v", raw[:min(len(raw), 30)], err)
	}
	_, _ = io.Copy(io.Discard, resp.Body)
	return resp
}

func rawPost(path, body string) string {
	return fmt.Sprintf("POST %s HTTP/1.1\r\nHost: h\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n%s", path, len(body), body)
}

func authBody(t *testing.T, device securebox.KeyPair) (string, securebox.Challenge) {
	t.Helper()
	challenge, public, err := box.GetChallenge(device.PrivateKey)
	if err != nil {
		t.Fatal(err)
	}
	body, _ := json.Marshal(authRequest{PK: b64.EncodeToString(public[:]), Challenge: b64.EncodeToString(challenge[:])})
	return string(body), challenge
}

func TestEveryRefusalOfTheFirstRequest(t *testing.T) {
	device := keys(t)
	good, _ := authBody(t, device)
	short := `{"pk":"` + strings.Repeat("A", 42) + `","challenge":"` + strings.Repeat("A", 43) + `"}`
	padded := `{"pk":"` + strings.Repeat("A", 43) + `=","challenge":"` + strings.Repeat("A", 43) + `"}`
	cases := []struct {
		name   string
		raw    string
		status int
		kind   error
	}{
		{"the socket before the check", "GET /ws HTTP/1.1\r\nHost: h\r\nConnection: Upgrade\r\n\r\n", 401, ErrUnauthenticated},
		{"a file before the check", "GET /files/abc HTTP/1.1\r\nHost: h\r\n\r\n", 401, ErrUnauthenticated},
		{"health before the check", "GET /health HTTP/1.1\r\nHost: h\r\n\r\n", 401, ErrUnauthenticated},
		{"an unknown path", rawPost("/other", good), 401, ErrUnauthenticated},
		{"GET on /auth", "GET /auth HTTP/1.1\r\nHost: h\r\n\r\n", 405, ErrMethod},
		{"PUT on /auth2", "PUT /auth2 HTTP/1.1\r\nHost: h\r\nContent-Length: 0\r\n\r\n", 405, ErrMethod},
		{"/auth2 first", rawPost("/auth2", `{"signature":"x"}`), 400, ErrOrder},
		{"a body that is not JSON", rawPost("/auth", "not json"), 400, ErrMalformed},
		{"a JSON array", rawPost("/auth", "[]"), 400, ErrMalformed},
		{"a key of 31 bytes", rawPost("/auth", short), 400, ErrMalformed},
		{"padded base64", rawPost("/auth", padded), 400, ErrMalformed},
		{"no body at all", "POST /auth HTTP/1.1\r\nHost: h\r\nContent-Length: 0\r\n\r\n", 400, ErrMalformed},
		{"a body over 1 KiB", rawPost("/auth", `{"pk":"`+strings.Repeat("A", 1100)+`"}`), 400, ErrMalformed},
		{"chunked", "POST /auth HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n", 400, ErrMalformed},
		{"a request line that is not HTTP", "HELLO\r\n\r\n", 400, ErrMalformed},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			conn, done := serve(t, context.Background(), keys(t))
			resp := exchange(t, conn, bufio.NewReader(conn), c.raw)
			if resp.StatusCode != c.status {
				t.Fatalf("status %d, want %d", resp.StatusCode, c.status)
			}
			if !resp.Close {
				t.Fatal("a refusal without Connection: close")
			}
			if got := <-done; !errors.Is(got.err, c.kind) {
				t.Fatalf("kind %v, want %v", got.err, c.kind)
			}
		})
	}
}

func TestTheAnswerToAuthIsTheContracts(t *testing.T) {
	server, device := keys(t), keys(t)
	conn, _ := serve(t, context.Background(), server)
	body, challenge := authBody(t, device)
	resp := exchange(t, conn, bufio.NewReader(conn), rawPost("/auth", body))
	if resp.StatusCode != 200 || resp.Header.Get("Content-Type") != "application/json" ||
		resp.Header.Get("Cache-Control") != "no-store" || resp.ContentLength <= 0 || resp.Close {
		t.Fatalf("answer: %d %v", resp.StatusCode, resp.Header)
	}
	_ = challenge
}

// passAuth sends a good /auth and returns the server's challenge.
func passAuth(t *testing.T, conn net.Conn, br *bufio.Reader, device securebox.KeyPair) securebox.Challenge {
	t.Helper()
	body, _ := authBody(t, device)
	go func() { _, _ = io.WriteString(conn, rawPost("/auth", body)) }()
	resp, err := http.ReadResponse(br, nil)
	if err != nil || resp.StatusCode != 200 {
		t.Fatalf("/auth: %v", err)
	}
	var a authAnswer
	if err := json.NewDecoder(resp.Body).Decode(&a); err != nil {
		t.Fatal(err)
	}
	var c securebox.Challenge
	if !decode(a.Challenge, c[:]) {
		t.Fatal("the server's challenge")
	}
	return c
}

func TestEveryRefusalOfTheSecondRequest(t *testing.T) {
	device, stranger := keys(t), keys(t)
	again, _ := authBody(t, device)
	cases := []struct {
		name   string
		raw    func(securebox.Challenge) string
		status int
		kind   error
	}{
		{"/auth again", func(securebox.Challenge) string { return rawPost("/auth", again) }, 400, ErrOrder},
		{"the socket before /auth2", func(securebox.Challenge) string { return "GET /ws HTTP/1.1\r\nHost: h\r\n\r\n" }, 401, ErrUnauthenticated},
		{"another key's signature", func(c securebox.Challenge) string {
			sig, _ := box.SignChallenge(stranger.PrivateKey, c)
			return rawPost("/auth2", `{"signature":"`+b64.EncodeToString(sig[:])+`"}`)
		}, 401, ErrSignature},
		{"a signature over another challenge", func(securebox.Challenge) string {
			sig, _ := box.SignChallenge(device.PrivateKey, securebox.Challenge{1})
			return rawPost("/auth2", `{"signature":"`+b64.EncodeToString(sig[:])+`"}`)
		}, 401, ErrSignature},
		{"a signature of 63 bytes", func(securebox.Challenge) string {
			return rawPost("/auth2", `{"signature":"`+b64.EncodeToString(make([]byte, 63))+`"}`)
		}, 400, ErrMalformed},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			conn, done := serve(t, context.Background(), keys(t))
			br := bufio.NewReader(conn)
			challenge := passAuth(t, conn, br, device)
			resp := exchange(t, conn, br, c.raw(challenge))
			if resp.StatusCode != c.status || !resp.Close {
				t.Fatalf("status %d close %v, want %d", resp.StatusCode, resp.Close, c.status)
			}
			if got := <-done; !errors.Is(got.err, c.kind) {
				t.Fatalf("kind %v, want %v", got.err, c.kind)
			}
		})
	}
}

func TestBytesSentAfterAuth2ReachTheServer(t *testing.T) {
	device := keys(t)
	conn, done := serve(t, context.Background(), keys(t))
	br := bufio.NewReader(conn)
	challenge := passAuth(t, conn, br, device)
	sig, _ := box.SignChallenge(device.PrivateKey, challenge)
	raw := rawPost("/auth2", `{"signature":"`+b64.EncodeToString(sig[:])+`"}`) + "GET /ws HTTP/1.1\r\n"
	resp := exchange(t, conn, br, raw)
	if resp.StatusCode != 200 || resp.ContentLength != 0 || resp.Close {
		t.Fatalf("/auth2: %d", resp.StatusCode)
	}
	got := <-done
	if got.err != nil {
		t.Fatal(got.err)
	}
	line, err := bufio.NewReader(got.rest).ReadString('\n')
	if err != nil || line != "GET /ws HTTP/1.1\r\n" {
		t.Fatalf("the rest: %q %v", line, err)
	}
}

func TestTheDeadlineEndsTheCheckWithoutAWord(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	conn, done := serve(t, ctx, keys(t))
	got := <-done
	if !errors.Is(got.err, context.DeadlineExceeded) {
		t.Fatalf("%v", got.err)
	}
	_ = conn.SetReadDeadline(time.Now().Add(100 * time.Millisecond))
	if n, _ := conn.Read(make([]byte, 1)); n != 0 {
		t.Fatal("the server said something")
	}
}

// fakeServer answers /auth with whatever answer makes, then 200 to /auth2.
func fakeServer(t *testing.T, answer func(deviceChallenge securebox.Challenge) (int, string)) net.Conn {
	t.Helper()
	deviceEnd, serverEnd := net.Pipe()
	t.Cleanup(func() { _ = deviceEnd.Close(); _ = serverEnd.Close() })
	go func() {
		br := bufio.NewReader(serverEnd)
		req, err := http.ReadRequest(br)
		if err != nil {
			return
		}
		var r authRequest
		_ = json.NewDecoder(req.Body).Decode(&r)
		var c securebox.Challenge
		decode(r.Challenge, c[:])
		status, body := answer(c)
		_ = writeAnswer(serverEnd, status, []byte(body), false)
	}()
	return deviceEnd
}

func TestTheDeviceRefusesABadAnswer(t *testing.T) {
	server, device := keys(t), keys(t)
	signed := func(c securebox.Challenge, by securebox.KeyPair) string {
		ours, _, _ := box.GetChallenge(by.PrivateKey)
		sig, _ := box.SignChallenge(by.PrivateKey, c)
		b, _ := json.Marshal(authAnswer{PK: b64.EncodeToString(server.PublicKey[:]), Challenge: b64.EncodeToString(ours[:]), Signature: b64.EncodeToString(sig[:])})
		return string(b)
	}
	cases := []struct {
		name   string
		answer func(securebox.Challenge) (int, string)
		kind   error
	}{
		{"a signature over another challenge", func(securebox.Challenge) (int, string) { return 200, signed(securebox.Challenge{9}, server) }, ErrSignature},
		{"another key's signature under the right key", func(c securebox.Challenge) (int, string) { return 200, signed(c, device) }, ErrSignature},
		{"a refusal", func(securebox.Challenge) (int, string) { return 404, "" }, ErrRefused},
		{"not the contract's body", func(securebox.Challenge) (int, string) { return 200, `{"pk":"x"}` }, ErrMalformed},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			conn := fakeServer(t, c.answer)
			if _, err := Initiate(context.Background(), conn, box, device.PrivateKey, "h:1", server.PublicKey); !errors.Is(err, c.kind) {
				t.Fatalf("%v, want %v", err, c.kind)
			}
		})
	}
}
