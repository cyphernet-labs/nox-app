package store

import (
	"context"
	"errors"
	"testing"
)

func TestAClaimOverOnionIsRefusedAndTheTokenStays(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	if _, err := s.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	token, err := s.IssueClaimToken(ctx, 100)
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	if _, err := s.Pair(ctx, token, "dev-a", "test", PairOptions{ViaOnion: true}, 100); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("claim over onion err = %v, want ErrTokenInvalid", err)
	}
	if usable, err := s.ClaimTokenUsable(ctx, token); err != nil || !usable {
		t.Fatalf("the refusal spent the token: usable=%v err=%v", usable, err)
	}
	if _, err := s.Pair(ctx, token, "dev-a", "test", PairOptions{}, 101); err != nil {
		t.Fatalf("the same claim at home: %v", err)
	}
}

func TestAReplayedClaimOverOnionIsRefusedToo(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	if _, err := s.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	token, err := s.IssueClaimToken(ctx, 100)
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	if _, err := s.Pair(ctx, token, "dev-a", "test", PairOptions{}, 100); err != nil {
		t.Fatalf("claim: %v", err)
	}
	if _, err := s.Pair(ctx, token, "dev-a", "test", PairOptions{ViaOnion: true}, 101); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("replay over onion err = %v, want ErrTokenInvalid", err)
	}
	// The same replay at home is still the lost-reply recovery it always was.
	if _, err := s.Pair(ctx, token, "dev-a", "test", PairOptions{}, 102); err != nil {
		t.Fatalf("replay at home: %v", err)
	}
}

func TestADeviceInviteWorksOverOnion(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	owner := claimOwner(t, s, "dev-a")
	invite, err := s.IssueOnionInvite(ctx, owner.UserID, accessKey(9), 200)
	if err != nil {
		t.Fatalf("IssueOnionInvite: %v", err)
	}
	if _, err := s.Pair(ctx, invite, "dev-b", "test", PairOptions{ViaOnion: true, AccessKey: accessKey(2)}, 201); err != nil {
		t.Fatalf("an invite over onion: %v", err)
	}
	keys, _ := activeKeys(t, s, 201)
	if len(keys) != 1 || keys[0] != accessKey(2) {
		t.Fatalf("active keys = %v, want only the new device's own key - the one-time key died with the token", keys)
	}
}

func TestARePairWithoutAKeyKeepsTheOneTheDeviceHad(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	if _, err := s.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	claim, err := s.IssueClaimToken(ctx, 100)
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	owner, err := s.Pair(ctx, claim, "dev-a", "test", PairOptions{AccessKey: accessKey(1)}, 100)
	if err != nil {
		t.Fatalf("claim: %v", err)
	}
	invite, err := s.IssueDeviceInvite(ctx, owner.UserID, 200)
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	// Re-pairing one's own device without a key must not take its access away.
	if _, err := s.Pair(ctx, invite, "dev-a", "test", PairOptions{}, 201); err != nil {
		t.Fatalf("re-pair: %v", err)
	}
	if keys, _ := activeKeys(t, s, 201); len(keys) != 1 || keys[0] != accessKey(1) {
		t.Fatalf("active keys = %v, want the device's key kept", keys)
	}
	invite2, err := s.IssueDeviceInvite(ctx, owner.UserID, 300)
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	if _, err := s.Pair(ctx, invite2, "dev-a", "test", PairOptions{AccessKey: accessKey(3)}, 301); err != nil {
		t.Fatalf("re-pair with a key: %v", err)
	}
	if keys, _ := activeKeys(t, s, 301); len(keys) != 1 || keys[0] != accessKey(3) {
		t.Fatalf("active keys = %v, want the replacement", keys)
	}
}
