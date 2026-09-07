package store

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"testing"
)

func TestCountsOnAnEmptyStoreAreZerosRatherThanAbsent(t *testing.T) {
	s := newStore(t)
	got, err := s.CountEverything(context.Background())
	if err != nil {
		t.Fatalf("CountEverything: %v", err)
	}
	if got != (Counts{}) {
		t.Fatalf("counts = %+v, want all zeros", got)
	}
}

// Four DIFFERENT numbers on purpose: with two of them equal, swapping the two
// fields in the Scan would pass, and the page would show a message count under
// "Chats" with every test green.
func TestCountsFollowWhatTheStoreHolds(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	owner := claimOwner(t, s, "dev-owner")

	// Two people.
	token, err := s.IssuePersonInvite(ctx, owner.UserID, 200)
	if err != nil {
		t.Fatalf("IssuePersonInvite: %v", err)
	}
	req := present(t, s, token, "dev-guest", 300)
	guest, err := s.ConfirmPair(ctx, req.RequestID, owner.UserID, true, 310)
	if err != nil {
		t.Fatalf("ConfirmPair: %v", err)
	}
	// Three devices.
	invite, err := s.IssueDeviceInvite(ctx, owner.UserID, 400)
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	if _, err := s.Pair(ctx, invite, "dev-owner-2", "test", 410); err != nil {
		t.Fatalf("Pair: %v", err)
	}
	// One chat, four messages.
	chat, _, err := s.CreateChat(ctx, "Kitchen", owner.Label, 500)
	if err != nil {
		t.Fatalf("CreateChat: %v", err)
	}
	for i := range 4 {
		if _, _, _, err := s.SendMessage(ctx, chat.ChatID, fmt.Sprintf("m%d", i), guest.Identity,
			json.RawMessage(`{"type":"text","text":"x"}`), "", int64(600+i)); err != nil {
			t.Fatalf("SendMessage: %v", err)
		}
	}

	got, err := s.CountEverything(ctx)
	if err != nil {
		t.Fatalf("CountEverything: %v", err)
	}
	want := Counts{People: 2, Devices: 3, Chats: 1, Messages: 4}
	if got != want {
		t.Fatalf("counts = %+v, want %+v", got, want)
	}
}

// The service page shows these on a screen people glance at over each other's
// shoulders, so the QUERY itself must not reach a column that names anybody.
// Asserted against the SQL rather than against the output: a page that merely
// declines to print a name is one edit away from printing it.
func TestTheCountingQueryTouchesNothingThatNamesAnybody(t *testing.T) {
	source := readSource(t, "stats.go")
	start := strings.Index(source, "`")
	end := strings.LastIndex(source, "`")
	if start < 0 || end <= start {
		t.Fatal("no SQL literal found in stats.go")
	}
	sql := strings.ToLower(source[start : end+1])
	for _, forbidden := range []string{"label", "name", "body", "device_key", "token", "author"} {
		if strings.Contains(sql, forbidden) {
			t.Fatalf("the counting query mentions %q; it must reach nothing that names a person", forbidden)
		}
	}
	if !strings.Contains(sql, "count(1)") {
		t.Fatal("the counting query stopped counting")
	}
}
