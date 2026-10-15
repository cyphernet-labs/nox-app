// Package connauth is the check every connection passes right after TLS 1.3
// and before anything else (contract §1, feature 050): two HTTP/1.1 requests,
// POST /auth and then POST /auth2, on that same connection.
//
//	device → POST /auth  {"pk", "challenge"}                 its key and a challenge
//	server ← 200         {"pk", "challenge", "signature"}    its key, its challenge, its
//	                                                          signature over the device's
//	device → POST /auth2 {"signature"}                       its signature over the server's
//	server ← 200                                              the connection goes on: /ws or a file
//
// Keys, challenges and signatures come from RustSecureBox
// (internal/securebox); this package only carries them. The check belongs to
// the connection: the server's challenge and the device's key live in
// Respond's locals between the two requests and nowhere else, and every new
// connection - the socket, each file transfer - goes through it again.
//
// Respond is the server's half; the channel listener runs it, so http.Server
// never sees a connection that has not passed (internal/server/channel.go).
// Initiate is the device's half, for the tests and cmd/smoke; the app's own
// lives in its Rust module and speaks the same bytes.
package connauth

import (
	"bufio"
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"strconv"
	"time"

	"nox.app/client-backend/internal/securebox"
)

const (
	// AuthPath and Auth2Path are the two steps.
	AuthPath  = "/auth"
	Auth2Path = "/auth2"

	// maxBody bounds the body of either request. Theirs are 119 and 107
	// bytes; anything near the bound is not a device.
	maxBody = 1 << 10
	// maxStage bounds everything the server reads before the check passes:
	// both requests with their headers. A peer that has not proved a key gets
	// no more of the server's memory than this.
	maxStage = 16 << 10
	// readBuffer is the bufio buffer requests are parsed from; a header line
	// longer than it is refused.
	readBuffer = 4 << 10
)

// The kinds of refusal - what the log names, never a key, a challenge or a
// signature. A caller tells them apart with errors.Is.
var (
	// ErrMalformed is a request whose body does not parse, has fields of the
	// wrong length, or comes without Content-Length or chunked: 400.
	ErrMalformed = errors.New("connauth: malformed request")
	// ErrOrder is a step out of order - /auth2 first, /auth again: 400.
	ErrOrder = errors.New("connauth: steps out of order")
	// ErrMethod is anything but POST on /auth or /auth2: 405.
	ErrMethod = errors.New("connauth: method not allowed")
	// ErrUnauthenticated is any other path before the check passed: 401.
	ErrUnauthenticated = errors.New("connauth: request before the check")
	// ErrSignature is a signature that does not verify: 401 from the server;
	// on the device's side, the server's signature over its challenge.
	ErrSignature = errors.New("connauth: the signature does not verify")
	// ErrWrongServer is, on the device's side, a server whose key is not the
	// one the pairing link named.
	ErrWrongServer = errors.New("connauth: another server's key")
	// ErrRefused is, on the device's side, any answer but 200.
	ErrRefused = errors.New("connauth: the server refused")
)

// authRequest, authAnswer and auth2Request are the bodies. Values are
// base64url without padding.
type authRequest struct {
	PK        string `json:"pk"`
	Challenge string `json:"challenge"`
}

type authAnswer struct {
	PK        string `json:"pk"`
	Challenge string `json:"challenge"`
	Signature string `json:"signature"`
}

type auth2Request struct {
	Signature string `json:"signature"`
}

var b64 = base64.RawURLEncoding.Strict()

// Respond takes conn through the check and returns the key the device proved,
// with the connection to go on with: conn itself, or conn behind whatever the
// device sent after /auth2 before its answer - nothing of what it sent is
// lost. A refusal is answered (400, 401 or 405, with Connection: close) and
// returned as one of the kinds above; the caller closes the connection. An
// error of RustSecureBox, or ctx ending, is answered with nothing.
//
// ctx bounds the whole exchange through conn's deadline, and a cancelled ctx
// cuts a read or a write that waits. The deadline stays on conn afterwards -
// the caller sets the one it needs next.
func Respond(ctx context.Context, conn net.Conn, box *securebox.Box, serverKey securebox.PrivateKey) (securebox.PublicKey, net.Conn, error) {
	if err := ctx.Err(); err != nil {
		return securebox.PublicKey{}, nil, err
	}
	left := bind(ctx, conn)
	device, rest, err := respond(conn, box, serverKey)
	if err := settle(ctx, left, err); err != nil {
		return securebox.PublicKey{}, nil, err
	}
	return device, rest, nil
}

func respond(conn net.Conn, box *securebox.Box, serverKey securebox.PrivateKey) (securebox.PublicKey, net.Conn, error) {
	var none securebox.PublicKey
	br := bufio.NewReaderSize(io.LimitReader(conn, maxStage), readBuffer)

	// Step 1: /auth.
	body, err := readStep(conn, br, AuthPath)
	if err != nil {
		return none, nil, err
	}
	var req authRequest
	var device securebox.PublicKey
	var theirs securebox.Challenge
	if json.Unmarshal(body, &req) != nil || !decode(req.PK, device[:]) || !decode(req.Challenge, theirs[:]) {
		return none, nil, refuse(conn, http.StatusBadRequest, ErrMalformed)
	}
	ours, serverPublic, err := box.GetChallenge(serverKey)
	if err != nil {
		return none, nil, err
	}
	signature, err := box.SignChallenge(serverKey, theirs)
	if err != nil {
		return none, nil, err
	}
	answer, err := json.Marshal(authAnswer{
		PK:        b64.EncodeToString(serverPublic[:]),
		Challenge: b64.EncodeToString(ours[:]),
		Signature: b64.EncodeToString(signature[:]),
	})
	if err != nil {
		return none, nil, err
	}
	if err := writeAnswer(conn, http.StatusOK, answer, false); err != nil {
		return none, nil, fmt.Errorf("connauth: send the answer to /auth: %w", err)
	}

	// Step 2: /auth2, over the server's challenge, by the key of step 1.
	body, err = readStep(conn, br, Auth2Path)
	if err != nil {
		return none, nil, err
	}
	var req2 auth2Request
	var theirSignature securebox.Signature
	if json.Unmarshal(body, &req2) != nil || !decode(req2.Signature, theirSignature[:]) {
		return none, nil, refuse(conn, http.StatusBadRequest, ErrMalformed)
	}
	valid, err := box.CheckSignature(device, ours, theirSignature)
	if err != nil {
		return none, nil, err
	}
	if !valid {
		return none, nil, refuse(conn, http.StatusUnauthorized, ErrSignature)
	}
	if err := writeAnswer(conn, http.StatusOK, nil, false); err != nil {
		return none, nil, fmt.Errorf("connauth: send the answer to /auth2: %w", err)
	}
	return device, withRest(conn, br), nil
}

// readStep reads the next request, which must be a POST to want with a body
// of a declared length, and returns that body. Anything else is refused, in
// the contract's order: path and method, then the step, then the body.
func readStep(conn net.Conn, br *bufio.Reader, want string) ([]byte, error) {
	req, err := http.ReadRequest(br)
	if err != nil {
		// A peer gone before a whole request - or past maxStage - is a
		// connection that ended, not a request to answer.
		var netErr net.Error
		if errors.Is(err, io.EOF) || errors.Is(err, io.ErrUnexpectedEOF) || errors.As(err, &netErr) {
			return nil, fmt.Errorf("connauth: read %s: %w", want, err)
		}
		return nil, refuse(conn, http.StatusBadRequest, fmt.Errorf("%w: %w", ErrMalformed, err))
	}
	switch path := req.URL.Path; {
	case path != AuthPath && path != Auth2Path:
		return nil, refuse(conn, http.StatusUnauthorized, ErrUnauthenticated)
	case req.Method != http.MethodPost:
		return nil, refuse(conn, http.StatusMethodNotAllowed, ErrMethod)
	case path != want:
		return nil, refuse(conn, http.StatusBadRequest, ErrOrder)
	}
	if len(req.TransferEncoding) > 0 || req.ContentLength < 0 || req.ContentLength > maxBody {
		return nil, refuse(conn, http.StatusBadRequest, ErrMalformed)
	}
	body, err := io.ReadAll(req.Body)
	if err != nil || int64(len(body)) != req.ContentLength {
		return nil, refuse(conn, http.StatusBadRequest, ErrMalformed)
	}
	return body, nil
}

// decode reads a base64url value of exactly len(out) bytes into out.
func decode(s string, out []byte) bool {
	if b64.DecodedLen(len(s)) != len(out) {
		return false
	}
	n, err := b64.Decode(out, []byte(s))
	return err == nil && n == len(out)
}

// refuse answers status with Connection: close and returns kind. Whether the
// answer got out does not matter: the connection ends either way.
func refuse(conn net.Conn, status int, kind error) error {
	_ = writeAnswer(conn, status, nil, true)
	return kind
}

// writeAnswer writes one response. Written by hand rather than through
// http.ResponseWriter: two answers with fixed headers, before any server
// exists for this connection.
func writeAnswer(w io.Writer, status int, body []byte, closing bool) error {
	var b bytes.Buffer
	fmt.Fprintf(&b, "HTTP/1.1 %d %s\r\n", status, http.StatusText(status))
	if body != nil {
		b.WriteString("Content-Type: application/json\r\nCache-Control: no-store\r\n")
	}
	b.WriteString("Content-Length: " + strconv.Itoa(len(body)) + "\r\n")
	if closing {
		b.WriteString("Connection: close\r\n")
	}
	b.WriteString("\r\n")
	b.Write(body)
	_, err := w.Write(b.Bytes())
	return err
}

// withRest is conn, behind what br already holds: bytes the peer sent after
// /auth2 before its answer. Ours never does, but nothing it sends is dropped.
func withRest(conn net.Conn, br *bufio.Reader) net.Conn {
	n := br.Buffered()
	if n == 0 {
		return conn
	}
	held, _ := br.Peek(n)
	return &prefixConn{Conn: conn, prefix: bytes.NewReader(bytes.Clone(held))}
}

// prefixConn reads prefix first, then conn.
type prefixConn struct {
	net.Conn
	prefix *bytes.Reader
}

func (c *prefixConn) Read(b []byte) (int, error) {
	if c.prefix.Len() > 0 {
		return c.prefix.Read(b)
	}
	return c.Conn.Read(b)
}

// Initiate is the device's half, as the app's Rust module does it: /auth with
// its key and a fresh challenge; the server's signature over that challenge
// checked, then the server's key against server - the key the pairing link
// named; only then /auth2. host is what the Host header says. A caller that
// writes nothing else until Initiate returns never hands a byte of its own to a
// machine it has not recognised. It returns the connection to go on with.
//
// ctx is honoured as in Respond.
func Initiate(ctx context.Context, conn net.Conn, box *securebox.Box, deviceKey securebox.PrivateKey, host string, server securebox.PublicKey) (net.Conn, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	left := bind(ctx, conn)
	rest, err := initiate(conn, box, deviceKey, host, server)
	if err := settle(ctx, left, err); err != nil {
		return nil, err
	}
	return rest, nil
}

func initiate(conn net.Conn, box *securebox.Box, deviceKey securebox.PrivateKey, host string, server securebox.PublicKey) (net.Conn, error) {
	ours, devicePublic, err := box.GetChallenge(deviceKey)
	if err != nil {
		return nil, err
	}
	body, err := json.Marshal(authRequest{PK: b64.EncodeToString(devicePublic[:]), Challenge: b64.EncodeToString(ours[:])})
	if err != nil {
		return nil, err
	}
	br := bufio.NewReaderSize(conn, readBuffer)
	answer, err := post(conn, br, host, AuthPath, body)
	if err != nil {
		return nil, err
	}
	var a authAnswer
	var serverPublic securebox.PublicKey
	var theirs securebox.Challenge
	var signature securebox.Signature
	if json.Unmarshal(answer, &a) != nil || !decode(a.PK, serverPublic[:]) || !decode(a.Challenge, theirs[:]) ||
		!decode(a.Signature, signature[:]) {
		return nil, ErrMalformed
	}
	valid, err := box.CheckSignature(serverPublic, ours, signature)
	if err != nil {
		return nil, err
	}
	if !valid {
		return nil, ErrSignature
	}
	if serverPublic != server {
		return nil, ErrWrongServer
	}
	mine, err := box.SignChallenge(deviceKey, theirs)
	if err != nil {
		return nil, err
	}
	body, err = json.Marshal(auth2Request{Signature: b64.EncodeToString(mine[:])})
	if err != nil {
		return nil, err
	}
	if _, err := post(conn, br, host, Auth2Path, body); err != nil {
		return nil, err
	}
	return withRest(conn, br), nil
}

// post sends one request and reads its answer: the body of a 200, or
// ErrRefused for anything else.
func post(conn net.Conn, br *bufio.Reader, host, path string, body []byte) ([]byte, error) {
	req := fmt.Sprintf("POST %s HTTP/1.1\r\nHost: %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n",
		path, host, len(body))
	if _, err := conn.Write(append([]byte(req), body...)); err != nil {
		return nil, fmt.Errorf("connauth: send %s: %w", path, err)
	}
	resp, err := http.ReadResponse(br, &http.Request{Method: http.MethodPost})
	if err != nil {
		return nil, fmt.Errorf("connauth: read the answer to %s: %w", path, err)
	}
	defer resp.Body.Close()
	answer, err := io.ReadAll(io.LimitReader(resp.Body, maxBody+1))
	if err != nil {
		return nil, fmt.Errorf("connauth: read the answer to %s: %w", path, err)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("%w: %s answered %d", ErrRefused, path, resp.StatusCode)
	}
	if len(answer) > maxBody {
		return nil, ErrMalformed
	}
	return answer, nil
}

// settle turns the end of an exchange into its answer. When ctx ended under
// it, ctx's error is the answer whatever the I/O said - the connection's
// deadline is in the past now. And an I/O failure at or after ctx's deadline
// is that deadline: conn's deadline and ctx's timer fire at the same instant,
// and which of the two a caller hears must not depend on the scheduler.
func settle(ctx context.Context, left func() bool, err error) error {
	if !left() {
		return fmt.Errorf("connauth: %w", ctx.Err())
	}
	if err != nil {
		if deadline, ok := ctx.Deadline(); ok && !time.Now().Before(deadline) {
			return fmt.Errorf("connauth: %w: %w", context.DeadlineExceeded, err)
		}
	}
	return err
}

// bind ties conn to ctx for the length of one exchange. The returned function
// reports whether ctx left the exchange alone: false means ctx ended while it
// ran and conn's deadline has been pulled into the past, so the connection is
// unusable whatever the exchange itself returned.
func bind(ctx context.Context, conn net.Conn) func() bool {
	if deadline, ok := ctx.Deadline(); ok {
		_ = conn.SetDeadline(deadline)
	}
	// A deadline in the past wakes a read or a write that is waiting. Closing
	// the connection would too, but the connection is the caller's to close.
	return context.AfterFunc(ctx, func() { _ = conn.SetDeadline(time.Unix(1, 0)) })
}
