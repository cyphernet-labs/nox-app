// Package eidolon is the check that runs inside every channel right after the
// TLS 1.3 handshake and before the first byte of HTTP (contract §1, feature
// 044): each side proves that it holds an Ed25519 key, and proves it on THIS
// TLS session.
//
// The message is the same in both directions, 160 bytes:
//
//	public key (32) ‖ signature over the public key (64) ‖ signature over the binding (64)
//
// The binding is the TLS 1.3 exporter of the session (RFC 9266), so a party
// relaying between two sessions - one with each end - holds two different
// bindings and cannot produce a signature that either end accepts. Signatures
// are plain RFC 8032 Ed25519 over the raw bytes, which is what makes them
// deterministic and the shared vectors (testdata/vectors.json, the app's copy
// is byte for byte the same) comparable at all.
//
// The format and the order of the checks are those of eidolon-auth 0.3.1, the
// library the app runs: the initiator writes first, the responder checks the
// message whole and only then answers with its own. Nothing here knows which
// keys are welcome - the server accepts any key and asks its store afterwards,
// the device accepts exactly the one its pairing link named.
package eidolon

import (
	"context"
	"crypto/ed25519"
	"errors"
	"fmt"
	"io"
	"time"
)

const (
	// MessageSize is the length of one message: key, signature over the key,
	// signature over the binding.
	MessageSize = ed25519.PublicKeySize + 2*ed25519.SignatureSize
	// BindingSize is the length of the channel binding both sides sign.
	BindingSize = 32
	// ExporterLabel is the RFC 9266 label of the TLS 1.3 exporter the binding
	// comes from, with an empty context. Exported so the two ends of this
	// repository - the server and cmd/smoke - cannot spell it differently.
	ExporterLabel = "EXPORTER-Channel-Binding"
)

// The four refusals, named after eidolon-auth's own so the two
// implementations can be compared failure for failure. A caller tells them
// apart with errors.Is; I/O failures come back wrapped and match none of them.
var (
	// ErrInvalidLen is a message that is not 160 bytes - including a peer that
	// stopped before sending a whole one.
	ErrInvalidLen = errors.New("eidolon: the message is not 160 bytes")
	// ErrInvalidCert is a key whose signature over itself does not verify.
	ErrInvalidCert = errors.New("eidolon: the signature over the key does not verify")
	// ErrSigMismatch is a signature over the binding that does not verify. A
	// party relaying between two TLS sessions shows up as exactly this: it can
	// forward a genuine message, but one signed over the other session.
	ErrSigMismatch = errors.New("eidolon: the signature over the channel binding does not verify")
	// ErrUnauthorized is a well-formed message from a key other than the one
	// expected: another machine answering at the address.
	ErrUnauthorized = errors.New("eidolon: the key is not the expected one")
)

// Message is the message priv presents on the channel bound by binding.
func Message(priv ed25519.PrivateKey, binding []byte) []byte {
	pub := priv.Public().(ed25519.PublicKey)
	msg := make([]byte, 0, MessageSize)
	msg = append(msg, pub...)
	msg = append(msg, ed25519.Sign(priv, pub)...)
	return append(msg, ed25519.Sign(priv, binding)...)
}

// Verify checks a message against binding and returns the key it proves, in
// eidolon-auth's order: the length, the signature over the key, the signature
// over the binding. Which keys are welcome is the caller's question.
func Verify(msg, binding []byte) (ed25519.PublicKey, error) {
	if len(msg) != MessageSize {
		return nil, fmt.Errorf("%w: got %d", ErrInvalidLen, len(msg))
	}
	pub := ed25519.PublicKey(msg[:ed25519.PublicKeySize])
	keySig := msg[ed25519.PublicKeySize : ed25519.PublicKeySize+ed25519.SignatureSize]
	bindingSig := msg[ed25519.PublicKeySize+ed25519.SignatureSize:]
	if !ed25519.Verify(pub, pub, keySig) {
		return nil, ErrInvalidCert
	}
	if !ed25519.Verify(pub, binding, bindingSig) {
		return nil, ErrSigMismatch
	}
	// A copy, not a window into msg: the caller keeps the key for the life of
	// the connection, and the buffer it came in is the caller's to reuse.
	return append(ed25519.PublicKey(nil), pub...), nil
}

// Respond is the server's half: it reads exactly one message, checks it, and
// only then answers with its own - so a peer that fails the check is answered
// with nothing at all, not even the server's key. Every key that passes is
// accepted; it returns the key the peer proved.
//
// ctx bounds the exchange through rw's deadline when rw has one (a net.Conn
// does): ctx's deadline becomes rw's, and a cancelled ctx cuts a read or a
// write that is waiting. The deadline stays on rw afterwards - a caller that
// goes on using it sets the one it needs.
func Respond(ctx context.Context, rw io.ReadWriter, binding []byte, priv ed25519.PrivateKey) (ed25519.PublicKey, error) {
	if err := checkBinding(binding); err != nil {
		return nil, err
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	left := bind(ctx, rw)
	peer, err := respond(rw, binding, priv)
	if err := settle(ctx, left, err); err != nil {
		return nil, err
	}
	return peer, nil
}

func respond(rw io.ReadWriter, binding []byte, priv ed25519.PrivateKey) (ed25519.PublicKey, error) {
	msg, err := readMessage(rw)
	if err != nil {
		return nil, err
	}
	peer, err := Verify(msg, binding)
	if err != nil {
		return nil, err
	}
	if _, err := rw.Write(Message(priv, binding)); err != nil {
		return nil, fmt.Errorf("eidolon: send the answer: %w", err)
	}
	return peer, nil
}

// Initiate is the device's half: it writes its message first, reads the
// answer, checks it, and then checks that the key it proves is server - the
// one the pairing link named. A caller that writes nothing else until
// Initiate returns nil never hands a byte of its own to a machine it has not
// recognised.
//
// ctx is honoured as in Respond.
func Initiate(ctx context.Context, rw io.ReadWriter, binding []byte, priv ed25519.PrivateKey, server ed25519.PublicKey) error {
	if err := checkBinding(binding); err != nil {
		return err
	}
	if len(server) != ed25519.PublicKeySize {
		return fmt.Errorf("eidolon: the expected server key is %d bytes, want %d", len(server), ed25519.PublicKeySize)
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	left := bind(ctx, rw)
	return settle(ctx, left, initiate(rw, binding, priv, server))
}

func initiate(rw io.ReadWriter, binding []byte, priv ed25519.PrivateKey, server ed25519.PublicKey) error {
	if _, err := rw.Write(Message(priv, binding)); err != nil {
		return fmt.Errorf("eidolon: send the message: %w", err)
	}
	msg, err := readMessage(rw)
	if err != nil {
		return err
	}
	peer, err := Verify(msg, binding)
	if err != nil {
		return err
	}
	if !peer.Equal(server) {
		return ErrUnauthorized
	}
	return nil
}

// readMessage reads exactly one message. A peer that ends the stream before
// a whole one sent a message of the wrong length; any other failure is the
// transport's and comes back as it was.
func readMessage(r io.Reader) ([]byte, error) {
	msg := make([]byte, MessageSize)
	if _, err := io.ReadFull(r, msg); err != nil {
		if errors.Is(err, io.EOF) || errors.Is(err, io.ErrUnexpectedEOF) {
			return nil, fmt.Errorf("%w: the peer stopped before a whole message", ErrInvalidLen)
		}
		return nil, fmt.Errorf("eidolon: read the message: %w", err)
	}
	return msg, nil
}

// checkBinding refuses a binding of the wrong size. Only a caller's bug gets
// here - and the bug it guards against is the dangerous one: both ends signing
// an empty binding would accept a relay as readily as a direct connection.
func checkBinding(binding []byte) error {
	if len(binding) != BindingSize {
		return fmt.Errorf("eidolon: the channel binding is %d bytes, want %d", len(binding), BindingSize)
	}
	return nil
}

// settle turns the end of an exchange into its answer. When ctx ended under
// it, ctx's error is the answer whatever the I/O said - the connection's
// deadline is in the past now. And an I/O failure at or after ctx's deadline
// is that deadline: rw's deadline and ctx's timer fire at the same instant,
// and which of the two a caller hears must not depend on the scheduler.
func settle(ctx context.Context, left func() bool, err error) error {
	if !left() {
		return fmt.Errorf("eidolon: %w", ctx.Err())
	}
	if err != nil {
		if deadline, ok := ctx.Deadline(); ok && !time.Now().Before(deadline) {
			return fmt.Errorf("eidolon: %w: %w", context.DeadlineExceeded, err)
		}
	}
	return err
}

// deadliner is the part of net.Conn the exchange needs to honour a context.
type deadliner interface {
	SetDeadline(t time.Time) error
}

// bind ties rw to ctx for the length of one exchange. The returned function
// reports whether ctx left the exchange alone: false means ctx ended while it
// ran and rw's deadline has been pulled into the past, so the connection is
// unusable whatever the exchange itself returned.
//
// A reader without deadlines - a buffer in a test - cannot be interrupted;
// for it the answer is only whether ctx is still alive.
func bind(ctx context.Context, rw io.ReadWriter) func() bool {
	conn, ok := rw.(deadliner)
	if !ok {
		return func() bool { return ctx.Err() == nil }
	}
	if deadline, ok := ctx.Deadline(); ok {
		_ = conn.SetDeadline(deadline)
	}
	// A deadline in the past wakes a read or a write that is waiting. Closing
	// the connection would too, but the connection is the caller's to close.
	return context.AfterFunc(ctx, func() { _ = conn.SetDeadline(time.Unix(1, 0)) })
}
