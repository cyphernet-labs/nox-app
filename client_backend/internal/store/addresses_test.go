package store

import (
	"context"
	"errors"
	"path/filepath"
	"testing"

	"nox.app/client-backend/internal/db"
)

const (
	testOnion  = "25njqamcweflpvkl73j4szahhihoc4xt3ktcgjnpaingr5yhkenl5sid.onion"
	testPublic = "nox.example.org:8443"
)

func mustAddresses(t *testing.T, s *Store) Addresses {
	t.Helper()
	got, err := s.Addresses(context.Background())
	if err != nil {
		t.Fatalf("Addresses: %v", err)
	}
	return got
}

// A machine starts knowing no address of its own beyond what it finds on its
// networks, and no parameter has ever been applied.
func TestAFreshMachineStoresNoAddresses(t *testing.T) {
	s := newStore(t)
	if _, err := s.EnsureServerIdentity(context.Background()); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	if got := mustAddresses(t, s); got != (Addresses{}) {
		t.Fatalf("a fresh machine stores %+v, want nothing", got)
	}
}

// The page's Set writes the address and leaves the remembered parameter alone:
// that is what lets an edit made on the page survive a restart with the same
// parameter still in the unit file. Empty deletes.
func TestSetAddressWritesTheValueAndLeavesTheParameter(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	if _, err := s.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	if err := s.ApplyAddressParam(ctx, AddressOnion, testOnion, testOnion+":443"); err != nil {
		t.Fatalf("ApplyAddressParam: %v", err)
	}

	other := "6bauzvyr6myctqykmykeuo3p3yc3iy7tilx5g3sxxpuifdwab54o56id.onion"
	if err := s.SetAddress(ctx, AddressOnion, other); err != nil {
		t.Fatalf("SetAddress onion: %v", err)
	}
	if err := s.SetAddress(ctx, AddressPublic, testPublic); err != nil {
		t.Fatalf("SetAddress public: %v", err)
	}
	got := mustAddresses(t, s)
	want := Addresses{Public: testPublic, Onion: other, OnionParam: testOnion + ":443"}
	if got != want {
		t.Fatalf("after Set: %+v, want %+v", got, want)
	}

	if err := s.SetAddress(ctx, AddressOnion, ""); err != nil {
		t.Fatalf("SetAddress empty: %v", err)
	}
	got = mustAddresses(t, s)
	if got.Onion != "" || got.OnionParam != testOnion+":443" || got.Public != testPublic {
		t.Fatalf("after deleting the onion address: %+v, want it gone and the rest kept", got)
	}
}

// A start parameter writes the address and the parameter it came from
// together, and survives a reopen - the next start compares against it.
func TestApplyAddressParamWritesBothAndSurvivesAReopen(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "addresses.db")
	first := openStoreAt(t, path)
	if _, err := first.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	if err := first.ApplyAddressParam(ctx, AddressPublic, testPublic, " "+testPublic); err != nil {
		t.Fatalf("ApplyAddressParam public: %v", err)
	}
	if err := first.ApplyAddressParam(ctx, AddressOnion, testOnion, testOnion); err != nil {
		t.Fatalf("ApplyAddressParam onion: %v", err)
	}

	got := mustAddresses(t, openStoreAt(t, path))
	want := Addresses{Public: testPublic, Onion: testOnion, PublicParam: " " + testPublic, OnionParam: testOnion}
	if got != want {
		t.Fatalf("after a reopen: %+v, want %+v", got, want)
	}
	if got.Value(AddressPublic) != testPublic || got.Param(AddressOnion) != testOnion {
		t.Fatalf("Value/Param read the wrong columns: %+v", got)
	}
}

// A parameter never deletes, and a kind that is neither of the two writes
// nothing at all.
func TestTheAddressWritesRefuseWhatTheyCannotPlace(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	if _, err := s.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	if err := s.SetAddress(ctx, AddressKind("direct"), testPublic); !errors.Is(err, ErrUnknownAddressKind) {
		t.Fatalf("SetAddress(direct) = %v, want ErrUnknownAddressKind", err)
	}
	if err := s.ApplyAddressParam(ctx, AddressKind("direct"), testPublic, testPublic); !errors.Is(err, ErrUnknownAddressKind) {
		t.Fatalf("ApplyAddressParam(direct) = %v, want ErrUnknownAddressKind", err)
	}
	if err := s.ApplyAddressParam(ctx, AddressPublic, "", ""); err == nil {
		t.Fatal("an empty parameter was applied")
	}
	if got := mustAddresses(t, s); got != (Addresses{}) {
		t.Fatalf("a refused write left %+v", got)
	}
}

// An address written to a store with no machine row would vanish without a
// word; the write says so instead.
func TestAnAddressNeedsTheMachineRow(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	if err := s.SetAddress(ctx, AddressOnion, testOnion); !errors.Is(err, ErrNoServerIdentity) {
		t.Fatalf("SetAddress without a machine = %v, want ErrNoServerIdentity", err)
	}
	if _, err := s.Addresses(ctx); !errors.Is(err, ErrNoServerIdentity) {
		t.Fatalf("Addresses without a machine = %v, want ErrNoServerIdentity", err)
	}
}

// A backup is the database file and nothing else: restoring it brings the
// addresses back with everything else, with no settings file to forget.
func TestABackupCarriesTheAddresses(t *testing.T) {
	dir := t.TempDir()
	ctx := context.Background()
	live := openStoreAt(t, filepath.Join(dir, "live.db"))
	if _, err := live.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	if err := live.SetAddress(ctx, AddressOnion, testOnion); err != nil {
		t.Fatalf("SetAddress: %v", err)
	}
	backup := filepath.Join(dir, "backup.db")
	if err := db.Snapshot(ctx, live.read, backup, testKey); err != nil {
		t.Fatalf("snapshot: %v", err)
	}
	if got := mustAddresses(t, openStoreAt(t, backup)); got.Onion != testOnion {
		t.Fatalf("the restored copy stores %+v, want the onion address", got)
	}
}
