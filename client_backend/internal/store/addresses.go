package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

// The two addresses this machine stores (feature 045): a public host:port and
// the onion address of the service a SEPARATE tor publishes for it. The
// addresses it finds on its own networks are not stored - they are looked up
// while it runs, and a stored copy would only go stale.
//
// Both live on the single server_identity row, beside the key they are NOT: an
// address says where to knock, the key says who answers, and the channel check
// proves the key on every connection whatever address it came in on. Nothing
// here validates a value - the server does, before it writes - so the store
// stays the one place that writes and never the place that decides what is
// well-formed.

// AddressKind names one of the two stored addresses. The values are the ones
// the service page's form posts as `kind`.
type AddressKind string

const (
	AddressPublic AddressKind = "public"
	AddressOnion  AddressKind = "onion"
)

// ErrUnknownAddressKind refuses a kind that is neither of the two. The SQL for
// each kind is written out below rather than built from the kind, so an
// unknown one has nowhere to go.
var ErrUnknownAddressKind = errors.New("unknown address kind")

// Addresses is what the machine row says about where it can be reached, and
// which start parameter each address was last written from. An empty string is
// a NULL: no address, or no parameter ever applied.
type Addresses struct {
	Public      string
	Onion       string
	PublicParam string
	OnionParam  string
}

// Value is the stored address of kind, empty when it is not set.
func (a Addresses) Value(kind AddressKind) string {
	switch kind {
	case AddressPublic:
		return a.Public
	case AddressOnion:
		return a.Onion
	}
	return ""
}

// Param is the start parameter kind was last written from, empty when none
// ever was.
func (a Addresses) Param(kind AddressKind) string {
	switch kind {
	case AddressPublic:
		return a.PublicParam
	case AddressOnion:
		return a.OnionParam
	}
	return ""
}

// Addresses reads both addresses and both remembered parameters in one row.
func (s *Store) Addresses(ctx context.Context) (Addresses, error) {
	var public, onion, publicParam, onionParam sql.NullString
	err := s.read.QueryRowContext(ctx,
		"SELECT public_address, onion_address, public_address_param, onion_address_param FROM server_identity WHERE id = 1").
		Scan(&public, &onion, &publicParam, &onionParam)
	if errors.Is(err, sql.ErrNoRows) {
		return Addresses{}, ErrNoServerIdentity
	}
	if err != nil {
		return Addresses{}, fmt.Errorf("read addresses: %w", err)
	}
	return Addresses{Public: public.String, Onion: onion.String, PublicParam: publicParam.String, OnionParam: onionParam.String}, nil
}

// SetAddress writes one address as the service page sets it: a value, or
// nothing for empty. The remembered start parameter is left exactly as it was
// - that is what lets the page's edit survive a restart with the same
// parameter still in the unit file.
func (s *Store) SetAddress(ctx context.Context, kind AddressKind, value string) error {
	var query string
	switch kind {
	case AddressPublic:
		query = "UPDATE server_identity SET public_address = ? WHERE id = 1"
	case AddressOnion:
		query = "UPDATE server_identity SET onion_address = ? WHERE id = 1"
	default:
		return ErrUnknownAddressKind
	}
	return s.updateIdentityRow(ctx, "set address", query, nullIfEmpty(value))
}

// ApplyAddressParam writes an address from its start parameter: the value and
// the parameter it came from, in ONE statement. Apart, a crash between the two
// would either lose the address or remember a parameter that was never
// applied - and the next start would then skip it as already seen.
func (s *Store) ApplyAddressParam(ctx context.Context, kind AddressKind, value, param string) error {
	if value == "" || param == "" {
		// A parameter never deletes: an empty one changes nothing, and the
		// caller never gets here with one.
		return errors.New("apply address parameter: the value and the parameter are both required")
	}
	var query string
	switch kind {
	case AddressPublic:
		query = "UPDATE server_identity SET public_address = ?, public_address_param = ? WHERE id = 1"
	case AddressOnion:
		query = "UPDATE server_identity SET onion_address = ?, onion_address_param = ? WHERE id = 1"
	default:
		return ErrUnknownAddressKind
	}
	return s.updateIdentityRow(ctx, "apply address parameter", query, value, param)
}

// updateIdentityRow runs one UPDATE of the machine row on the write handle and
// insists it found the row: an address written to a store without a machine
// identity would vanish without a word.
func (s *Store) updateIdentityRow(ctx context.Context, what, query string, args ...any) error {
	res, err := s.write.ExecContext(ctx, query, args...)
	if err != nil {
		return fmt.Errorf("%s: %w", what, err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("%s: %w", what, err)
	}
	if n == 0 {
		return ErrNoServerIdentity
	}
	return nil
}

// nullIfEmpty stores an empty string as NULL, which is what the columns' CHECK
// constraints expect "not set" to look like.
func nullIfEmpty(v string) any {
	if v == "" {
		return nil
	}
	return v
}
