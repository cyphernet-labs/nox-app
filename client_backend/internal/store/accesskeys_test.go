package store

import (
	"context"
	"encoding/base64"
	"errors"
	"slices"
	"testing"
)

// accessKey is a distinct, well-formed public access key for a test.
func accessKey(b byte) string {
	k := make([]byte, 32)
	for i := range k {
		k[i] = b
	}
	return base64.StdEncoding.EncodeToString(k)
}

func activeKeys(t *testing.T, s *Store) []string {
	t.Helper()
	keys, err := s.ActiveAccessKeys(context.Background())
	if err != nil {
		t.Fatalf("ActiveAccessKeys: %v", err)
	}
	return keys
}

func TestADeviceHasOneAccessKeyAndANewOneReplacesIt(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	claimOwner(t, s, "dev-a")

	changed, err := s.SetAccessKey(ctx, "dev-a", accessKey(1))
	if err != nil || !changed {
		t.Fatalf("first SetAccessKey = %v, %v; want changed", changed, err)
	}
	changed, err = s.SetAccessKey(ctx, "dev-a", accessKey(1))
	if err != nil || changed {
		t.Fatalf("the same key again = %v, %v; want unchanged, so nothing republishes", changed, err)
	}
	if _, err := s.SetAccessKey(ctx, "dev-a", accessKey(2)); err != nil {
		t.Fatalf("replace: %v", err)
	}

	if keys := activeKeys(t, s); !slices.Equal(keys, []string{accessKey(2)}) {
		t.Fatalf("active keys = %v, want only the replacement", keys)
	}
	if n, err := s.CountDevicesWithAccess(ctx); err != nil || n != 1 {
		t.Fatalf("CountDevicesWithAccess = %d, %v", n, err)
	}
}

func TestAKeyForADeviceThatIsGoneIsRefused(t *testing.T) {
	s := newStore(t)
	claimOwner(t, s, "dev-a")
	if _, err := s.SetAccessKey(context.Background(), "dev-unknown", accessKey(1)); !errors.Is(err, ErrDeviceUnknown) {
		t.Fatalf("err = %v, want ErrDeviceUnknown", err)
	}
}

func TestRevokingADeviceTakesItsAccessKeyWithIt(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	claimOwner(t, s, "dev-a")
	if _, err := s.SetAccessKey(ctx, "dev-a", accessKey(1)); err != nil {
		t.Fatalf("SetAccessKey: %v", err)
	}
	if err := s.RevokeDevice(ctx, "dev-a"); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}
	if keys := activeKeys(t, s); len(keys) != 0 {
		t.Fatalf("active keys after revocation = %v, want none", keys)
	}
}

// The list tor gets is sorted, so an unchanged set of keys is recognisably
// unchanged and nothing is republished for nothing.
func TestTheKeyListIsSorted(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	claimOwner(t, s, "dev-a")
	invite, err := s.IssueDeviceInvite(ctx, "dev-a", 1000)
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	if _, err := pairID(ctx, s, invite, "dev-b", "test", 1001); err != nil {
		t.Fatalf("pair dev-b: %v", err)
	}
	if _, err := s.SetAccessKey(ctx, "dev-a", accessKey(5)); err != nil {
		t.Fatalf("SetAccessKey: %v", err)
	}
	if _, err := s.SetAccessKey(ctx, "dev-b", accessKey(1)); err != nil {
		t.Fatalf("SetAccessKey: %v", err)
	}
	if keys := activeKeys(t, s); !slices.Equal(keys, []string{accessKey(1), accessKey(5)}) {
		t.Fatalf("active = %v, want both keys in order", keys)
	}
}

// An invite opens nothing on the onion service: the one-time keys onion
// invites used to carry went with 044, and the column with them.
func TestAnInviteCarriesNoKey(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	claimOwner(t, s, "dev-a")
	if _, err := s.IssueDeviceInvite(ctx, "dev-a", 1000); err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	if keys := activeKeys(t, s); len(keys) != 0 {
		t.Fatalf("active = %v, want nothing from an invite", keys)
	}
}

// An access key belongs to one device: a key two devices share would outlive
// the revocation of either. The second holder is refused whether the key comes
// with the pairing or is registered later, and a refused pairing spends
// nothing.
func TestAnAccessKeyBelongsToOneDevice(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	claimOwner(t, s, "dev-a")
	if _, err := s.SetAccessKey(ctx, "dev-a", accessKey(1)); err != nil {
		t.Fatalf("SetAccessKey: %v", err)
	}
	invite, err := s.IssueDeviceInvite(ctx, "dev-a", 200)
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	if _, err := s.Pair(ctx, invite, "dev-b", "test", PairOptions{AccessKey: accessKey(1)}, 201); !errors.Is(err, ErrAccessKeyTaken) {
		t.Fatalf("pair with dev-a's key: err = %v, want ErrAccessKeyTaken", err)
	}
	if _, err := s.Pair(ctx, invite, "dev-b", "test", PairOptions{AccessKey: accessKey(2)}, 202); err != nil {
		t.Fatalf("the refusal spent the invite: %v", err)
	}
	if _, err := s.SetAccessKey(ctx, "dev-b", accessKey(1)); !errors.Is(err, ErrAccessKeyTaken) {
		t.Fatalf("SetAccessKey to dev-a's key: err = %v, want ErrAccessKeyTaken", err)
	}
	// A device's OWN key is no collision.
	if changed, err := s.SetAccessKey(ctx, "dev-a", accessKey(1)); err != nil || changed {
		t.Fatalf("dev-a's own key again = %v, %v; want unchanged", changed, err)
	}
	if keys := activeKeys(t, s); !slices.Equal(keys, []string{accessKey(1), accessKey(2)}) {
		t.Fatalf("active keys = %v, want each device's own", keys)
	}
}

// An invite comes only from a device that is still there. A device revoked
// from another one may have a command on its way; the store refuses it in the
// statement that writes the token, which puts the two in one order - so the
// revocation's burning of live invites cannot miss one minted after it.
func TestAnInviteFromADeviceThatIsGoneIsRefused(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	claimOwner(t, s, "dev-a")
	invite, err := s.IssueDeviceInvite(ctx, "dev-a", 200)
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	if _, err := pairID(ctx, s, invite, "dev-b", "test", 201); err != nil {
		t.Fatalf("pair dev-b: %v", err)
	}
	if err := s.RevokeDevice(ctx, "dev-b"); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}

	tokens := func() int {
		var n int
		if err := s.read.QueryRowContext(ctx, "SELECT COUNT(1) FROM pair_tokens").Scan(&n); err != nil {
			t.Fatalf("count tokens: %v", err)
		}
		return n
	}
	before := tokens()
	if _, err := s.IssueDeviceInvite(ctx, "dev-b", 300); !errors.Is(err, ErrDeviceUnknown) {
		t.Fatalf("invite from the revoked device: err = %v, want ErrDeviceUnknown", err)
	}
	if _, err := s.IssueDeviceInvite(ctx, "dev-never-paired", 300); !errors.Is(err, ErrDeviceUnknown) {
		t.Fatalf("invite from a key never paired: err = %v, want ErrDeviceUnknown", err)
	}
	if after := tokens(); after != before {
		t.Fatalf("tokens %d -> %d, want nothing written", before, after)
	}
}
