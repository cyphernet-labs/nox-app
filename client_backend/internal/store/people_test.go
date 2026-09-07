package store

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
)

func TestTheCircleNamesEverybodyAndMarksExactlyOneOwner(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	owner := claimOwner(t, s, "dev-owner")

	token, err := s.IssuePersonInvite(ctx, owner.UserID, 200)
	if err != nil {
		t.Fatalf("IssuePersonInvite: %v", err)
	}
	req := present(t, s, token, "dev-guest", 300)
	guest, err := s.ConfirmPair(ctx, req.RequestID, owner.UserID, true, 310)
	if err != nil {
		t.Fatalf("ConfirmPair: %v", err)
	}

	people, err := s.ListPeople(ctx)
	if err != nil {
		t.Fatalf("ListPeople: %v", err)
	}
	if len(people) != 2 {
		t.Fatalf("people = %+v, want two", people)
	}
	owners := 0
	seen := map[string]bool{}
	for _, p := range people {
		seen[p.UserID] = true
		if p.Label == "" {
			t.Fatalf("person %q has no name", p.UserID)
		}
		if p.Owner {
			owners++
			if p.UserID != owner.UserID {
				t.Fatalf("owner mark on %q, want %q", p.UserID, owner.UserID)
			}
		}
	}
	if owners != 1 {
		t.Fatalf("owner marks = %d, want exactly one", owners)
	}
	if !seen[owner.UserID] || !seen[guest.Identity.UserID] {
		t.Fatalf("people = %+v, want both the owner and the invited person", people)
	}
}

// "Who lives here" is not "who owns how much hardware". The shape is pinned
// against the JSON, not against the struct: a field added later would ride out
// to every paired device without anybody deciding to send it.
func TestTheCircleCarriesNoDevicesKeysOrCounters(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	claimOwner(t, s, "dev-owner")

	people, err := s.ListPeople(ctx)
	if err != nil {
		t.Fatalf("ListPeople: %v", err)
	}
	raw, err := json.Marshal(people)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var rows []map[string]json.RawMessage
	if err := json.Unmarshal(raw, &rows); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(rows) != 1 {
		t.Fatalf("rows = %d, want 1", len(rows))
	}
	for field := range rows[0] {
		switch field {
		case "id", "label", "owner":
		default:
			t.Fatalf("unexpected field %q in %s", field, raw)
		}
	}
	if strings.Contains(string(raw), "dev-owner") {
		t.Fatalf("a device key reached the circle list: %s", raw)
	}
}

// The mark answers the same question a greeting answers, and reads it from the
// same place. Two sources would disagree eventually.
func TestTheCircleAgreesWithTheGreetingAboutOwnership(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	owner := claimOwner(t, s, "dev-owner")

	greeted, err := s.ResolveIdentity(ctx, "dev-owner", "", 400)
	if err != nil {
		t.Fatalf("ResolveIdentity: %v", err)
	}
	people, err := s.ListPeople(ctx)
	if err != nil {
		t.Fatalf("ListPeople: %v", err)
	}
	for _, p := range people {
		if p.UserID == owner.UserID && p.Owner != greeted.Owner {
			t.Fatalf("circle says owner=%v, greeting says owner=%v", p.Owner, greeted.Owner)
		}
	}
}
