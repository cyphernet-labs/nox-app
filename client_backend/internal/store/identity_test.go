package store

import (
	"context"
	"errors"
	"regexp"
	"testing"
	"testing/synctest"
)

// Recognition changed shape in feature 032. A greeting no longer brings anyone
// into being: people are created by pairing, and a connection whose key nobody
// knows is not a new person but an unauthorised one. These cover that boundary.

// claimPerson pairs one device by claiming the server, the way the first
// device of a fresh install does.
func claimPerson(t *testing.T, s *Store, deviceKey string) Identity {
	t.Helper()
	ctx := context.Background()
	if _, err := s.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	token, err := s.IssueClaimToken(ctx, 100)
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	id, err := s.Pair(ctx, token, deviceKey, "test", 100)
	if err != nil {
		t.Fatalf("Pair: %v", err)
	}
	return id
}

func TestGreetingFromAPairedDeviceFindsThePerson(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	paired := claimPerson(t, s, "dev-phone")

	got, err := s.ResolveIdentity(ctx, "dev-phone", "", 200)
	if err != nil {
		t.Fatalf("ResolveIdentity: %v", err)
	}
	if got.UserID != paired.UserID {
		t.Fatalf("user id = %q, want %q", got.UserID, paired.UserID)
	}
	if got.Created {
		t.Fatal("a greeting must never report having created the person")
	}
}

// The load-bearing one. Before pairing, an unknown key was silently enrolled
// as a brand-new person, which is why anyone who learned a login identifier
// became its owner. Now it is refused.
func TestGreetingFromAnUnknownDeviceIsRefusedRatherThanEnrolled(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	claimPerson(t, s, "dev-phone")

	_, err := s.ResolveIdentity(ctx, "dev-stranger", "", 200)
	if !errors.Is(err, ErrDeviceUnknown) {
		t.Fatalf("err = %v, want ErrDeviceUnknown", err)
	}

	var people int
	if err := s.read.QueryRowContext(ctx, "SELECT COUNT(1) FROM users").Scan(&people); err != nil {
		t.Fatalf("count users: %v", err)
	}
	if people != 1 {
		t.Fatalf("users = %d, want 1: the refused greeting must write nothing", people)
	}
}

// A revoked device and a device facing a rebuilt store are indistinguishable
// on purpose: both mean "this is not my server any more", and the client is
// meant to behave identically.
func TestARevokedDeviceLooksExactlyLikeAnUnknownOne(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	claimPerson(t, s, "dev-phone")

	if err := s.RevokeDevice(ctx, "dev-phone"); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}

	_, err := s.ResolveIdentity(ctx, "dev-phone", "", 300)
	if !errors.Is(err, ErrDeviceUnknown) {
		t.Fatalf("err = %v, want ErrDeviceUnknown", err)
	}
}

func TestAnonymousConnectionGetsAnIdentityAndWritesNoRow(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	id, err := s.ResolveIdentity(ctx, "", "", 100)
	if err != nil {
		t.Fatalf("ResolveIdentity: %v", err)
	}
	if !id.Ephemeral || id.UserID == "" {
		t.Fatalf("identity = %+v, want an ephemeral one with an id", id)
	}

	var people int
	if err := s.read.QueryRowContext(ctx, "SELECT COUNT(1) FROM users").Scan(&people); err != nil {
		t.Fatalf("count users: %v", err)
	}
	if people != 0 {
		t.Fatalf("users = %d, want 0: an anonymous greeting writes nothing", people)
	}
}

// A device carrying a stale cache would otherwise push an old name back over a
// rename made elsewhere, and the two devices of one person would flip-flop.
func TestGreetingWithoutALabelDoesNotRename(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	claimPerson(t, s, "dev-phone")

	named, err := s.ResolveIdentity(ctx, "dev-phone", "Anna", 200)
	if err != nil {
		t.Fatalf("name: %v", err)
	}
	if named.Label != "Anna" {
		t.Fatalf("label = %q, want Anna", named.Label)
	}

	silent, err := s.ResolveIdentity(ctx, "dev-phone", "", 300)
	if err != nil {
		t.Fatalf("silent greeting: %v", err)
	}
	if silent.Label != "Anna" {
		t.Fatalf("label = %q after a greeting that stated none, want Anna", silent.Label)
	}
}

func TestGreetingNeverRebindsADeviceToAnotherPerson(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	owner := claimPerson(t, s, "dev-phone")

	// A second device of the SAME person, via an invite.
	token, err := s.IssueDeviceInvite(ctx, owner.UserID, 200)
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	second, err := s.Pair(ctx, token, "dev-desktop", "test", 200)
	if err != nil {
		t.Fatalf("Pair second device: %v", err)
	}
	if second.UserID != owner.UserID {
		t.Fatalf("second device belongs to %q, want %q", second.UserID, owner.UserID)
	}
	if second.Created {
		t.Fatal("adding a device must not report having created a person")
	}
}

func TestResolveIdentityEmitsNoEvent(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	claimPerson(t, s, "dev-phone")

	if _, err := s.ResolveIdentity(ctx, "dev-phone", "Anna", 200); err != nil {
		t.Fatalf("ResolveIdentity: %v", err)
	}

	var events int
	if err := s.read.QueryRowContext(ctx, "SELECT COUNT(1) FROM events").Scan(&events); err != nil {
		t.Fatalf("count events: %v", err)
	}
	if events != 0 {
		t.Fatalf("events = %d, want 0: identity is not visible on the wire", events)
	}
}

func TestConcurrentGreetingsOfOneDeviceStaySerialised(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		s := newStore(t)
		ctx := context.Background()
		claimPerson(t, s, "dev-phone")

		ids := make(chan string, 2)
		for range 2 {
			go func() {
				id, err := s.ResolveIdentity(ctx, "dev-phone", "", 200)
				if err != nil {
					ids <- "err:" + err.Error()
					return
				}
				ids <- id.UserID
			}()
		}
		first, second := <-ids, <-ids
		if first != second {
			t.Fatalf("two greetings of one device resolved to %q and %q", first, second)
		}
	})
}

func TestAssignedLabelHasTheShapeTheDesignSpecAsks(t *testing.T) {
	shape := regexp.MustCompile(`^User[0-9]{4}$`)
	seen := map[string]bool{}
	for i := range 10 {
		s := newStore(t)
		id := claimPerson(t, s, "dev-"+string(rune('a'+i)))
		if !shape.MatchString(id.Label) {
			t.Fatalf("assigned label %q does not match User<4 digits>", id.Label)
		}
		seen[id.Label] = true
	}
	if len(seen) < 9 {
		t.Fatalf("only %d distinct names out of 10; the assignment is not random enough", len(seen))
	}
}

func TestJournalIDIsStableAcrossCalls(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	if err := s.EnsureJournal(ctx); err != nil {
		t.Fatalf("EnsureJournal: %v", err)
	}
	first, err := s.JournalID(ctx)
	if err != nil {
		t.Fatalf("JournalID: %v", err)
	}
	// Idempotent: a restart must not hand clients a new world.
	if err := s.EnsureJournal(ctx); err != nil {
		t.Fatalf("EnsureJournal again: %v", err)
	}
	second, err := s.JournalID(ctx)
	if err != nil {
		t.Fatalf("JournalID again: %v", err)
	}
	if first != second || first == "" {
		t.Fatalf("journal id = %q then %q", first, second)
	}
}
