package store

import (
	"context"
	"regexp"
	"testing"
	"testing/synctest"
)

// The invariants exercised here are the contract of ResolveIdentity, listed as
// I1..I9 in specs/030-server-user-entity/contracts/identity-resolution.md.

func TestResolveIdentityRecognisesTheSamePersonAcrossDevices(t *testing.T) { // I1
	s := newStore(t)
	ctx := context.Background()

	first, err := s.ResolveIdentity(ctx, "digest-anna", "dev-phone", "Anna", 100)
	if err != nil {
		t.Fatalf("first resolve: %v", err)
	}
	// Same person, a device she has never used before - a reinstall or a second
	// machine, which is the whole point of keying the person on what she holds.
	second, err := s.ResolveIdentity(ctx, "digest-anna", "dev-laptop", "", 200)
	if err != nil {
		t.Fatalf("second resolve: %v", err)
	}
	if second.UserID != first.UserID {
		t.Fatalf("user id = %q, want the first %q", second.UserID, first.UserID)
	}

	var users, devices int
	if err := s.read.QueryRow("SELECT COUNT(1) FROM users").Scan(&users); err != nil {
		t.Fatalf("count users: %v", err)
	}
	if err := s.read.QueryRow("SELECT COUNT(1) FROM devices WHERE user_id = ?", first.UserID).Scan(&devices); err != nil {
		t.Fatalf("count devices: %v", err)
	}
	if users != 1 || devices != 2 {
		t.Fatalf("users = %d, devices = %d; want 1 and 2", users, devices)
	}
}

func TestResolveIdentityRecognisesTheSameDeviceWithoutADigest(t *testing.T) { // I2
	s := newStore(t)
	ctx := context.Background()

	first, err := s.ResolveIdentity(ctx, "", "dev-phone", "Boris", 100)
	if err != nil {
		t.Fatalf("first resolve: %v", err)
	}
	second, err := s.ResolveIdentity(ctx, "", "dev-phone", "", 200)
	if err != nil {
		t.Fatalf("second resolve: %v", err)
	}
	if second.UserID != first.UserID || second.Label != "Boris" {
		t.Fatalf("second = %+v, want the first %+v", second, first)
	}
}

func TestResolveIdentityRebindsADeviceToThePersonItPresents(t *testing.T) { // I3
	s := newStore(t)
	ctx := context.Background()

	anna, err := s.ResolveIdentity(ctx, "digest-anna", "dev-shared", "Anna", 100)
	if err != nil {
		t.Fatalf("anna: %v", err)
	}
	var createdBefore int64
	if err := s.read.QueryRow("SELECT created_at FROM devices WHERE device_key = ?", "dev-shared").Scan(&createdBefore); err != nil {
		t.Fatalf("read created_at: %v", err)
	}

	// The person wins: letting the device win would keep an old install holding
	// someone else's history.
	boris, err := s.ResolveIdentity(ctx, "digest-boris", "dev-shared", "Boris", 200)
	if err != nil {
		t.Fatalf("boris: %v", err)
	}
	if boris.UserID == anna.UserID {
		t.Fatalf("boris inherited anna's identity %q", anna.UserID)
	}

	var owner string
	var createdAfter, lastSeen int64
	err = s.read.QueryRow("SELECT user_id, created_at, last_seen_at FROM devices WHERE device_key = ?", "dev-shared").
		Scan(&owner, &createdAfter, &lastSeen)
	if err != nil {
		t.Fatalf("read device: %v", err)
	}
	if owner != boris.UserID {
		t.Fatalf("device owner = %q, want boris %q", owner, boris.UserID)
	}
	if createdAfter != createdBefore { // I9
		t.Fatalf("created_at moved from %d to %d", createdBefore, createdAfter)
	}
	if lastSeen != 200 { // I9
		t.Fatalf("last_seen_at = %d, want 200", lastSeen)
	}
}

func TestResolveIdentityNeverRefusesWhateverItIsGiven(t *testing.T) { // I4
	s := newStore(t)
	ctx := context.Background()

	long := ""
	for range 4096 {
		long += "x"
	}
	cases := []struct{ name, digest, device, label string }{
		{"empty everything", "", "", ""},
		{"very long digest", long, "", ""},
		{"non-hex digest", "not a digest at all", "", ""},
		{"very long device key", "", long, ""},
		{"very long label", "", "dev-1", long},
		{"label with newlines", "", "dev-2", "a\nb"},
		// SQLite's length() stops at the first NUL, so a leading NUL used to be
		// seen as empty by the schema's CHECK and refused the whole greeting.
		{"label that starts with NUL", "", "dev-3", "\x00"},
		{"digest that starts with NUL", "\x00digest", "", "Anna"},
		{"label with an embedded NUL", "", "dev-4", "An\x00na"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if _, err := s.ResolveIdentity(ctx, c.digest, c.device, c.label, 100); err != nil {
				t.Fatalf("ResolveIdentity refused %s: %v", c.name, err)
			}
		})
	}
}

func TestResolveIdentityWritesNoRowForAnAnonymousConnection(t *testing.T) { // I5
	s := newStore(t)
	ctx := context.Background()

	var before int
	if err := s.read.QueryRow("SELECT COUNT(1) FROM users").Scan(&before); err != nil {
		t.Fatalf("count before: %v", err)
	}
	id, err := s.ResolveIdentity(ctx, "", "", "", 100)
	if err != nil {
		t.Fatalf("resolve: %v", err)
	}
	if !id.Ephemeral {
		t.Fatalf("identity = %+v, want Ephemeral", id)
	}
	var after int
	if err := s.read.QueryRow("SELECT COUNT(1) FROM users").Scan(&after); err != nil {
		t.Fatalf("count after: %v", err)
	}
	if after != before {
		t.Fatalf("users grew from %d to %d; probes and hand tools must leave no rows", before, after)
	}
}

func TestResolveIdentityWithoutALabelDoesNotRename(t *testing.T) { // I6
	s := newStore(t)
	ctx := context.Background()

	if _, err := s.ResolveIdentity(ctx, "digest-anna", "dev-a", "Anna", 100); err != nil {
		t.Fatalf("first: %v", err)
	}
	if _, err := s.ResolveIdentity(ctx, "digest-anna", "dev-a", "Anna2", 200); err != nil {
		t.Fatalf("rename: %v", err)
	}
	// A second device with a stale cache reconnects and states nothing. Writing
	// the presented name on every greeting would push Anna back over Anna2 and
	// the two devices would flip-flop forever.
	back, err := s.ResolveIdentity(ctx, "digest-anna", "dev-b", "", 300)
	if err != nil {
		t.Fatalf("stale device: %v", err)
	}
	if back.Label != "Anna2" {
		t.Fatalf("label = %q, want Anna2 to survive a nameless greeting", back.Label)
	}
}

func TestResolveIdentityEmitsNoEvent(t *testing.T) { // I7
	s := newStore(t)
	ctx := context.Background()

	var before int64
	if err := s.read.QueryRow("SELECT COALESCE(MAX(seq), 0) FROM events").Scan(&before); err != nil {
		t.Fatalf("max seq before: %v", err)
	}
	for i := range 5 {
		if _, err := s.ResolveIdentity(ctx, "", "dev-"+string(rune('a'+i)), "", 100); err != nil {
			t.Fatalf("resolve %d: %v", i, err)
		}
	}
	var after int64
	if err := s.read.QueryRow("SELECT COALESCE(MAX(seq), 0) FROM events").Scan(&after); err != nil {
		t.Fatalf("max seq after: %v", err)
	}
	if after != before {
		t.Fatalf("seq moved from %d to %d; a person coming into being is not visible on the wire", before, after)
	}
}

func TestResolveIdentityConcurrentFirstGreetingsCreateOnePerson(t *testing.T) { // I8
	synctest.Test(t, func(t *testing.T) {
		s := newStore(t)
		ctx := context.Background()

		const conns = 8
		ids := make([]string, conns)
		done := make(chan int, conns)
		for i := range conns {
			go func() {
				id, err := s.ResolveIdentity(ctx, "digest-anna", "", "Anna", 100)
				if err == nil {
					ids[i] = id.UserID
				}
				done <- i
			}()
		}
		for range conns {
			<-done
		}

		var users int
		if err := s.read.QueryRow("SELECT COUNT(1) FROM users").Scan(&users); err != nil {
			t.Fatalf("count users: %v", err)
		}
		if users != 1 {
			t.Fatalf("users = %d, want 1: the single-writer pool must serialise first greetings", users)
		}
		for i, id := range ids {
			if id != ids[0] {
				t.Fatalf("goroutine %d resolved %q, want %q", i, id, ids[0])
			}
		}
	})
}

func TestAssignedLabelHasTheShapeTheDesignSpecAsks(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	shape := regexp.MustCompile(`^User[0-9]{4}$`)
	seen := map[string]bool{}
	for i := range 10 {
		id, err := s.ResolveIdentity(ctx, "", "dev-"+string(rune('a'+i)), "", 100)
		if err != nil {
			t.Fatalf("resolve %d: %v", i, err)
		}
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

// The Created flag is what tells the client to offer the naming step. Every
// arm of the resolution has to state it, and getting one wrong is invisible on
// the server: it surfaces as a person being sent to Set username and having
// the name they were known by overwritten.
func TestResolveIdentityReportsWhetherItCreatedThePerson(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	t.Run("inserted by digest", func(t *testing.T) {
		id, err := s.ResolveIdentity(ctx, "digest-new", "", "", 100)
		if err != nil {
			t.Fatalf("resolve: %v", err)
		}
		if !id.Created {
			t.Fatal("a person who did not exist before this answer must report Created")
		}
	})

	t.Run("found by digest", func(t *testing.T) {
		if _, err := s.ResolveIdentity(ctx, "digest-known", "", "Anna", 100); err != nil {
			t.Fatalf("first: %v", err)
		}
		id, err := s.ResolveIdentity(ctx, "digest-known", "", "", 200)
		if err != nil {
			t.Fatalf("second: %v", err)
		}
		if id.Created {
			t.Fatal("a returning person must not report Created")
		}
	})

	t.Run("inserted by device", func(t *testing.T) {
		id, err := s.ResolveIdentity(ctx, "", "dev-fresh", "", 100)
		if err != nil {
			t.Fatalf("resolve: %v", err)
		}
		if !id.Created {
			t.Fatal("a device nobody has seen brings a person into being")
		}
	})

	t.Run("found by device", func(t *testing.T) {
		if _, err := s.ResolveIdentity(ctx, "", "dev-known", "Boris", 100); err != nil {
			t.Fatalf("first: %v", err)
		}
		id, err := s.ResolveIdentity(ctx, "", "dev-known", "", 200)
		if err != nil {
			t.Fatalf("second: %v", err)
		}
		if id.Created {
			t.Fatal("a returning device must not report Created")
		}
	})

	t.Run("ephemeral", func(t *testing.T) {
		id, err := s.ResolveIdentity(ctx, "", "", "", 100)
		if err != nil {
			t.Fatalf("resolve: %v", err)
		}
		if !id.Created || !id.Ephemeral {
			t.Fatalf("identity = %+v; until this answer no such person existed, row or not", id)
		}
	})

	t.Run("a known device presenting a new person creates that person", func(t *testing.T) {
		if _, err := s.ResolveIdentity(ctx, "digest-a", "dev-shared", "A", 100); err != nil {
			t.Fatalf("first: %v", err)
		}
		// The person wins on conflict, and this person is new.
		id, err := s.ResolveIdentity(ctx, "digest-b", "dev-shared", "B", 200)
		if err != nil {
			t.Fatalf("rebind: %v", err)
		}
		if !id.Created {
			t.Fatal("re-binding a known device to a person who did not exist must report Created")
		}
	})
}
