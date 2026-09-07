package store

import (
	"context"
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

func TestCountsFollowWhatTheStoreHolds(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	owner := claimOwner(t, s, "dev-owner")

	token, err := s.IssuePersonInvite(ctx, owner.UserID, 200)
	if err != nil {
		t.Fatalf("IssuePersonInvite: %v", err)
	}
	req := present(t, s, token, "dev-guest", 300)
	if _, err := s.ConfirmPair(ctx, req.RequestID, owner.UserID, true, 310); err != nil {
		t.Fatalf("ConfirmPair: %v", err)
	}

	got, err := s.CountEverything(ctx)
	if err != nil {
		t.Fatalf("CountEverything: %v", err)
	}
	if got.People != 2 || got.Devices != 2 {
		t.Fatalf("counts = %+v, want two people and two devices", got)
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
