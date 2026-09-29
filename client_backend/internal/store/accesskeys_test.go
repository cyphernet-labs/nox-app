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

func activeKeys(t *testing.T, s *Store, now int64) ([]string, int64) {
	t.Helper()
	keys, next, err := s.ActiveAccessKeys(context.Background(), now)
	if err != nil {
		t.Fatalf("ActiveAccessKeys: %v", err)
	}
	return keys, next
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

	keys, next := activeKeys(t, s, 100)
	if !slices.Equal(keys, []string{accessKey(2)}) || next != 0 {
		t.Fatalf("active keys = %v next=%d, want only the replacement and no expiry", keys, next)
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
	if keys, _ := activeKeys(t, s, 100); len(keys) != 0 {
		t.Fatalf("active keys after revocation = %v, want none", keys)
	}
}

// A one-time key works exactly as long as its invite does: issued it is
// active, and using, expiring and burning the invite each switch it off with no
// write of their own.
func TestAOneTimeKeyLivesAndDiesWithItsInvite(t *testing.T) {
	ctx := context.Background()

	t.Run("live until it expires", func(t *testing.T) {
		s := newStore(t)
		claimOwner(t, s, "dev-a")
		if _, err := s.IssueOnionInvite(ctx, "dev-a", accessKey(9), 1000); err != nil {
			t.Fatalf("IssueOnionInvite: %v", err)
		}
		keys, next := activeKeys(t, s, 1000)
		if !slices.Equal(keys, []string{accessKey(9)}) || next != 1000+InviteTTLSeconds {
			t.Fatalf("active = %v next=%d, want the one-time key expiring at %d", keys, next, 1000+InviteTTLSeconds)
		}
		if keys, next := activeKeys(t, s, 1000+InviteTTLSeconds); len(keys) != 0 || next != 0 {
			t.Fatalf("at expiry: active = %v next=%d, want nothing", keys, next)
		}
	})

	t.Run("dead once used", func(t *testing.T) {
		s := newStore(t)
		claimOwner(t, s, "dev-a")
		token, err := s.IssueOnionInvite(ctx, "dev-a", accessKey(9), 1000)
		if err != nil {
			t.Fatalf("IssueOnionInvite: %v", err)
		}
		if _, err := pairID(ctx, s, token, "dev-b", "test", 1001); err != nil {
			t.Fatalf("pair: %v", err)
		}
		if keys, _ := activeKeys(t, s, 1001); len(keys) != 0 {
			t.Fatalf("active after use = %v, want none", keys)
		}
	})

	t.Run("dead once burned by a revocation", func(t *testing.T) {
		s := newStore(t)
		claimOwner(t, s, "dev-a")
		if _, err := s.IssueOnionInvite(ctx, "dev-a", accessKey(9), 1000); err != nil {
			t.Fatalf("IssueOnionInvite: %v", err)
		}
		if err := s.RevokeDevice(ctx, "dev-a"); err != nil {
			t.Fatalf("RevokeDevice: %v", err)
		}
		if keys, _ := activeKeys(t, s, 1001); len(keys) != 0 {
			t.Fatalf("active after the person's device was revoked = %v, want none", keys)
		}
	})
}

func TestTheSameKeyTwiceIsOneClientAndTheListIsSorted(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	claimOwner(t, s, "dev-a")
	if _, err := s.SetAccessKey(ctx, "dev-a", accessKey(5)); err != nil {
		t.Fatalf("SetAccessKey: %v", err)
	}
	// The same key on a live invite: one client to tor, not two.
	if _, err := s.IssueOnionInvite(ctx, "dev-a", accessKey(5), 1000); err != nil {
		t.Fatalf("IssueOnionInvite: %v", err)
	}
	if _, err := s.IssueOnionInvite(ctx, "dev-a", accessKey(1), 1000); err != nil {
		t.Fatalf("IssueOnionInvite: %v", err)
	}
	keys, _ := activeKeys(t, s, 1000)
	if !slices.Equal(keys, []string{accessKey(1), accessKey(5)}) {
		t.Fatalf("active = %v, want two distinct keys in order", keys)
	}
}

func TestAPlainInviteCarriesNoKey(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	claimOwner(t, s, "dev-a")
	if _, err := s.IssueDeviceInvite(ctx, "dev-a", 1000); err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	if keys, next := activeKeys(t, s, 1000); len(keys) != 0 || next != 0 {
		t.Fatalf("active = %v next=%d, want nothing from an invite without onion", keys, next)
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
	if keys, _ := activeKeys(t, s, 300); !slices.Equal(keys, []string{accessKey(1), accessKey(2)}) {
		t.Fatalf("active keys = %v, want each device's own", keys)
	}
}

// A one-time key never becomes a device's key: its private half travels in a
// link that outlives the invite, so it is refused at the pairing that spends
// the invite and at any registration after.
func TestAOneTimeKeyNeverBecomesADevicesKey(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	claimOwner(t, s, "dev-a")
	invite, err := s.IssueOnionInvite(ctx, "dev-a", accessKey(9), 200)
	if err != nil {
		t.Fatalf("IssueOnionInvite: %v", err)
	}
	opts := PairOptions{ViaOnion: true, AccessKey: accessKey(9)}
	if _, err := s.Pair(ctx, invite, "dev-b", "test", opts, 201); !errors.Is(err, ErrAccessKeyTaken) {
		t.Fatalf("pair with the invite's own key: err = %v, want ErrAccessKeyTaken", err)
	}
	opts.AccessKey = accessKey(2)
	if _, err := s.Pair(ctx, invite, "dev-b", "test", opts, 202); err != nil {
		t.Fatalf("the refusal spent the invite: %v", err)
	}
	if _, err := s.SetAccessKey(ctx, "dev-b", accessKey(9)); !errors.Is(err, ErrAccessKeyTaken) {
		t.Fatalf("SetAccessKey to the spent invite's key: err = %v, want ErrAccessKeyTaken", err)
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
	if _, err := s.IssueOnionInvite(ctx, "dev-b", accessKey(9), 300); !errors.Is(err, ErrDeviceUnknown) {
		t.Fatalf("onion invite from the revoked device: err = %v, want ErrDeviceUnknown", err)
	}
	if _, err := s.IssueDeviceInvite(ctx, "dev-never-paired", 300); !errors.Is(err, ErrDeviceUnknown) {
		t.Fatalf("invite from a key never paired: err = %v, want ErrDeviceUnknown", err)
	}
	if after := tokens(); after != before {
		t.Fatalf("tokens %d -> %d, want nothing written", before, after)
	}
	if keys, _ := activeKeys(t, s, 300); len(keys) != 0 {
		t.Fatalf("active keys = %v, want no one-time key from a refused invite", keys)
	}
}
