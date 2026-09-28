package server

import (
	"context"
	"crypto/ed25519"
	"net"
	"time"

	"nox.app/client-backend/internal/tor"
)

// torService is what the server needs from the tor side (039). Declared here,
// where it is consumed: *tor.Supervisor is the real one - tor.Disabled() when
// the server runs with -tor=false - and the tests drive the handlers through a
// fake without starting any tor.
type torService interface {
	// KeysChanged signals that the set of access keys may have changed. Called
	// after the reply to the command that changed it, never before: a republish
	// ahead of the reply could drop the very connection the reply travels on.
	KeysChanged()
	// ReadyForInvite reports whether an invite carrying the onion address
	// would work now.
	ReadyForInvite() bool
	// Offered reports whether the onion address belongs in the address list.
	Offered() bool
	// OnionPublicKey is the onion service's public key; nil without Tor.
	OnionPublicKey() ed25519.PublicKey
	// Address is the 56-character onion address without ".onion"; empty
	// without Tor. Never logged, never shown on the status page.
	Address() string
	// Status is the snapshot the status page shows.
	Status() tor.Status
}

// onionConnKey marks a request that arrived through the onion entry.
type onionConnKey struct{}

// markOnionConn is the onion server's ConnContext: every request on a
// connection accepted by that listener carries the mark.
//
// The mark is on the SOCKET, not derived from anything the request says - the
// same reasoning that put the status page on its own listener (035): a check
// on a header is one somebody eventually routes around with a header.
func markOnionConn(ctx context.Context, _ net.Conn) context.Context {
	return context.WithValue(ctx, onionConnKey{}, true)
}

// viaOnion reports whether the request came through the onion entry.
func viaOnion(ctx context.Context) bool {
	v, _ := ctx.Value(onionConnKey{}).(bool)
	return v
}

// activeKeys adapts the store's key read to what the supervisor asks for.
func (s *Server) activeKeys(ctx context.Context, now time.Time) ([]string, time.Time, error) {
	keys, next, err := s.store.ActiveAccessKeys(ctx, now.Unix())
	if err != nil {
		return nil, time.Time{}, err
	}
	var expiry time.Time
	if next > 0 {
		expiry = time.Unix(next, 0)
	}
	return keys, expiry, nil
}
