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
		owner := claimOwner(t, s, "dev-a")
		if _, err := s.IssueOnionInvite(ctx, owner.UserID, accessKey(9), 1000); err != nil {
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
		owner := claimOwner(t, s, "dev-a")
		token, err := s.IssueOnionInvite(ctx, owner.UserID, accessKey(9), 1000)
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
		owner := claimOwner(t, s, "dev-a")
		if _, err := s.IssueOnionInvite(ctx, owner.UserID, accessKey(9), 1000); err != nil {
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
	owner := claimOwner(t, s, "dev-a")
	if _, err := s.SetAccessKey(ctx, "dev-a", accessKey(5)); err != nil {
		t.Fatalf("SetAccessKey: %v", err)
	}
	// The same key on a live invite: one client to tor, not two.
	if _, err := s.IssueOnionInvite(ctx, owner.UserID, accessKey(5), 1000); err != nil {
		t.Fatalf("IssueOnionInvite: %v", err)
	}
	if _, err := s.IssueOnionInvite(ctx, owner.UserID, accessKey(1), 1000); err != nil {
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
	owner := claimOwner(t, s, "dev-a")
	if _, err := s.IssueDeviceInvite(ctx, owner.UserID, 1000); err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	if keys, next := activeKeys(t, s, 1000); len(keys) != 0 || next != 0 {
		t.Fatalf("active = %v next=%d, want nothing from an invite without onion", keys, next)
	}
}
