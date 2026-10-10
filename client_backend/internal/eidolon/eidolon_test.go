package eidolon

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net"
	"os"
	"sync"
	"testing"
	"time"
)

// vectors is testdata/vectors.json - a copy of the contract's shared vectors,
// the same file the app's Rust tests read.
type vectors struct {
	DeviceSeed         string `json:"device_seed"`
	DevicePublicKey    string `json:"device_public_key"`
	ServerSeed         string `json:"server_seed"`
	ServerPublicKey    string `json:"server_public_key"`
	ChannelBinding     string `json:"channel_binding"`
	AppMessage         string `json:"app_message"`
	ServerMessage      string `json:"server_message"`
	WrongServerSeed    string `json:"wrong_server_seed"`
	WrongServerMessage string `json:"wrong_server_message"`
	Expected           struct {
		OtherBinding string `json:"app_message_with_other_binding_at_server"`
		WrongServer  string `json:"wrong_server_message_at_app_expecting_server_public_key"`
	} `json:"expected"`
}

func loadVectors(t *testing.T) vectors {
	t.Helper()
	raw, err := os.ReadFile("testdata/vectors.json")
	if err != nil {
		t.Fatalf("read the vectors: %v", err)
	}
	var v vectors
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatalf("parse the vectors: %v", err)
	}
	return v
}

func unhex(t *testing.T, s string) []byte {
	t.Helper()
	b, err := hex.DecodeString(s)
	if err != nil {
		t.Fatalf("hex %q: %v", s, err)
	}
	return b
}

func keyFromSeed(t *testing.T, seedHex string) ed25519.PrivateKey {
	t.Helper()
	return ed25519.NewKeyFromSeed(unhex(t, seedHex))
}

// Both messages, byte for byte. The app's library and this package sign the
// same bytes the same way or neither end can ever check the other, and a
// difference shows up here rather than as a channel that never opens.
func TestTheMessagesAreTheSharedVectorsByteForByte(t *testing.T) {
	v := loadVectors(t)
	binding := unhex(t, v.ChannelBinding)
	for _, tc := range []struct {
		name, seed, pub, msg string
	}{
		{"app", v.DeviceSeed, v.DevicePublicKey, v.AppMessage},
		{"server", v.ServerSeed, v.ServerPublicKey, v.ServerMessage},
		{"wrong server", v.WrongServerSeed, "", v.WrongServerMessage},
	} {
		t.Run(tc.name, func(t *testing.T) {
			priv := keyFromSeed(t, tc.seed)
			if tc.pub != "" && !bytes.Equal(priv.Public().(ed25519.PublicKey), unhex(t, tc.pub)) {
				t.Fatalf("the seed gives %x, the vectors say %s", priv.Public(), tc.pub)
			}
			if got := Message(priv, binding); !bytes.Equal(got, unhex(t, tc.msg)) {
				t.Fatalf("message\n got %x\nwant %s", got, tc.msg)
			}
		})
	}
}

// recorder keeps what crossed one end of a connection, in each direction.
type recorder struct {
	net.Conn
	mu      sync.Mutex
	read    bytes.Buffer
	written bytes.Buffer
}

func (r *recorder) Read(p []byte) (int, error) {
	n, err := r.Conn.Read(p)
	r.mu.Lock()
	r.read.Write(p[:n])
	r.mu.Unlock()
	return n, err
}

func (r *recorder) Write(p []byte) (int, error) {
	r.mu.Lock()
	r.written.Write(p)
	r.mu.Unlock()
	return r.Conn.Write(p)
}

func (r *recorder) seen() (read, written []byte) {
	r.mu.Lock()
	defer r.mu.Unlock()
	return bytes.Clone(r.read.Bytes()), bytes.Clone(r.written.Bytes())
}

// pipe is an in-memory connection whose two ends are closed with the test.
func pipe(t *testing.T) (net.Conn, net.Conn) {
	t.Helper()
	a, b := net.Pipe()
	t.Cleanup(func() {
		_ = a.Close()
		_ = b.Close()
	})
	return a, b
}

// The whole exchange, both halves running against each other, and what went
// over the wire is exactly the two vector messages - device first, server
// second, and nothing else.
func TestAnExchangeCarriesTheVectorMessagesInOrder(t *testing.T) {
	v := loadVectors(t)
	binding := unhex(t, v.ChannelBinding)
	device, server := pipe(t)
	wire := &recorder{Conn: server}

	type result struct {
		peer ed25519.PublicKey
		err  error
	}
	responded := make(chan result, 1)
	go func() {
		peer, err := Respond(t.Context(), wire, binding, keyFromSeed(t, v.ServerSeed))
		responded <- result{peer, err}
	}()

	if err := Initiate(t.Context(), device, binding, keyFromSeed(t, v.DeviceSeed), unhex(t, v.ServerPublicKey)); err != nil {
		t.Fatalf("Initiate: %v", err)
	}
	got := <-responded
	if got.err != nil {
		t.Fatalf("Respond: %v", got.err)
	}
	if !bytes.Equal(got.peer, unhex(t, v.DevicePublicKey)) {
		t.Fatalf("Respond proved %x, want the device key %s", got.peer, v.DevicePublicKey)
	}
	read, written := wire.seen()
	if !bytes.Equal(read, unhex(t, v.AppMessage)) {
		t.Fatalf("the server read %x, want the app message", read)
	}
	if !bytes.Equal(written, unhex(t, v.ServerMessage)) {
		t.Fatalf("the server wrote %x, want the server message", written)
	}
}

// The vector case: a genuine device message checked against another binding -
// which is what a server sees when a relay forwards a message signed on the
// relay's other session.
func TestAMessageSignedOnAnotherChannelIsASignatureMismatch(t *testing.T) {
	v := loadVectors(t)
	if v.Expected.OtherBinding != "sig_mismatch" {
		t.Fatalf("the vectors expect %q; this test pins sig_mismatch", v.Expected.OtherBinding)
	}
	other := bytes.Repeat([]byte{0xee}, BindingSize)
	if _, err := Verify(unhex(t, v.AppMessage), other); !errors.Is(err, ErrSigMismatch) {
		t.Fatalf("Verify against another binding = %v, want ErrSigMismatch", err)
	}
}

// The relay itself, end to end: it sits between a device and the server, one
// session with each, and forwards the device's message unchanged. The server
// refuses it and says nothing back - not even its own key.
func TestARelayBetweenTwoChannelsIsRefusedAndAnsweredWithNothing(t *testing.T) {
	v := loadVectors(t)
	deviceSide, relayFromDevice := pipe(t)
	relayToServer, serverSide := pipe(t)
	deviceBinding := bytes.Repeat([]byte{0x01}, BindingSize)
	serverBinding := bytes.Repeat([]byte{0x02}, BindingSize)

	responded := make(chan error, 1)
	go func() {
		_, err := Respond(t.Context(), serverSide, serverBinding, keyFromSeed(t, v.ServerSeed))
		responded <- err
		_ = serverSide.Close()
	}()
	initiated := make(chan error, 1)
	go func() {
		initiated <- Initiate(t.Context(), deviceSide, deviceBinding, keyFromSeed(t, v.DeviceSeed), unhex(t, v.ServerPublicKey))
	}()

	// The relay: one message across, then whatever the server says back.
	msg := make([]byte, MessageSize)
	if _, err := io.ReadFull(relayFromDevice, msg); err != nil {
		t.Fatalf("relay read: %v", err)
	}
	if _, err := relayToServer.Write(msg); err != nil {
		t.Fatalf("relay write: %v", err)
	}
	if err := <-responded; !errors.Is(err, ErrSigMismatch) {
		t.Fatalf("the server answered the relay with %v, want ErrSigMismatch", err)
	}
	if n, err := io.Copy(io.Discard, relayToServer); n != 0 {
		t.Fatalf("the server sent the relay %d bytes (err %v), want none", n, err)
	}
	// With nothing to forward the relay hangs up, and the device has nothing
	// to accept.
	_ = relayFromDevice.Close()
	if err := <-initiated; err == nil {
		t.Fatal("the device completed a check through a relay")
	}
}

// The other vector case: a well-formed answer from another machine. The
// device must not take it for its server.
func TestAnotherServerIsUnauthorizedAtTheDevice(t *testing.T) {
	v := loadVectors(t)
	if v.Expected.WrongServer != "unauthorized" {
		t.Fatalf("the vectors expect %q; this test pins unauthorized", v.Expected.WrongServer)
	}
	binding := unhex(t, v.ChannelBinding)
	device, impostor := pipe(t)
	go func() {
		msg := make([]byte, MessageSize)
		if _, err := io.ReadFull(impostor, msg); err != nil {
			return
		}
		_, _ = impostor.Write(unhex(t, v.WrongServerMessage))
	}()
	err := Initiate(t.Context(), device, binding, keyFromSeed(t, v.DeviceSeed), unhex(t, v.ServerPublicKey))
	if !errors.Is(err, ErrUnauthorized) {
		t.Fatalf("Initiate against another server = %v, want ErrUnauthorized", err)
	}
}

func TestAMessageOfAnyOtherLengthIsInvalidLen(t *testing.T) {
	v := loadVectors(t)
	binding := unhex(t, v.ChannelBinding)
	msg := unhex(t, v.AppMessage)
	for _, tc := range []struct {
		name string
		msg  []byte
	}{
		{"empty", nil},
		{"one byte short", msg[:MessageSize-1]},
		{"one byte long", append(bytes.Clone(msg), 0)},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := Verify(tc.msg, binding); !errors.Is(err, ErrInvalidLen) {
				t.Fatalf("Verify(%d bytes) = %v, want ErrInvalidLen", len(tc.msg), err)
			}
		})
	}

	// And on the stream: a peer that stops before a whole message.
	server, peer := pipe(t)
	go func() {
		_, _ = peer.Write(msg[:100])
		_ = peer.Close()
	}()
	if _, err := Respond(t.Context(), server, binding, keyFromSeed(t, v.ServerSeed)); !errors.Is(err, ErrInvalidLen) {
		t.Fatalf("Respond to a short message = %v, want ErrInvalidLen", err)
	}
}

func TestAKeyThatDoesNotSignItselfIsInvalidCert(t *testing.T) {
	v := loadVectors(t)
	msg := unhex(t, v.AppMessage)
	msg[ed25519.PublicKeySize+5] ^= 0x01
	if _, err := Verify(msg, unhex(t, v.ChannelBinding)); !errors.Is(err, ErrInvalidCert) {
		t.Fatalf("Verify with a broken key signature = %v, want ErrInvalidCert", err)
	}
}

// A peer that never says anything holds the responder only until ctx's
// deadline - the server's whole budget for the channel rests on this.
func TestASilentPeerIsCutAtTheDeadline(t *testing.T) {
	v := loadVectors(t)
	server, _ := pipe(t)
	ctx, cancel := context.WithTimeout(t.Context(), 100*time.Millisecond)
	defer cancel()

	start := time.Now()
	_, err := Respond(ctx, server, unhex(t, v.ChannelBinding), keyFromSeed(t, v.ServerSeed))
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("Respond to a silent peer = %v, want the deadline", err)
	}
	if took := time.Since(start); took > 2*time.Second {
		t.Fatalf("the deadline cut the exchange after %v", took)
	}
}

// Cancelling - a listener closing - cuts an exchange that is waiting, without
// a deadline anywhere.
func TestACancelledContextCutsAWaitingExchange(t *testing.T) {
	v := loadVectors(t)
	device, _ := pipe(t)
	ctx, cancel := context.WithCancel(t.Context())
	time.AfterFunc(50*time.Millisecond, cancel)
	// Initiate writes first; nobody reads, so it waits in the write.
	err := Initiate(ctx, device, unhex(t, v.ChannelBinding), keyFromSeed(t, v.DeviceSeed), unhex(t, v.ServerPublicKey))
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("Initiate on a cancelled context = %v, want context.Canceled", err)
	}
}

// Both ends signing an empty binding would accept a relay as readily as a
// direct connection, so a binding of the wrong size is a refusal before a
// single byte moves.
func TestABindingOfTheWrongSizeIsRefusedBeforeAnythingIsSent(t *testing.T) {
	v := loadVectors(t)
	short := make([]byte, BindingSize-1)
	conn, peer := pipe(t)
	if _, err := Respond(t.Context(), conn, short, keyFromSeed(t, v.ServerSeed)); err == nil {
		t.Fatal("Respond accepted a short binding")
	}
	if err := Initiate(t.Context(), conn, nil, keyFromSeed(t, v.DeviceSeed), unhex(t, v.ServerPublicKey)); err == nil {
		t.Fatal("Initiate accepted an empty binding")
	}
	if err := Initiate(t.Context(), conn, unhex(t, v.ChannelBinding), keyFromSeed(t, v.DeviceSeed), nil); err == nil {
		t.Fatal("Initiate accepted no expected server key")
	}
	// Nothing reached the other end: a write on a pipe would still be waiting
	// for this read.
	_ = peer.SetReadDeadline(time.Now().Add(50 * time.Millisecond))
	if n, _ := peer.Read(make([]byte, 1)); n != 0 {
		t.Fatal("a refused call wrote to the connection")
	}
}
