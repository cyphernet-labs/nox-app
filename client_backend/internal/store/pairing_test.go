package store

import (
	"context"
	"errors"
	"path/filepath"
	"testing"
	"testing/synctest"

	"nox.app/client-backend/internal/db"
)

func TestServerKeyIsMintedOnceAndSurvivesRestart(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "key.db")

	open := func() (*Store, func()) {
		d, err := db.Open(path)
		if err != nil {
			t.Fatalf("db.Open: %v", err)
		}
		if _, err := db.Migrate(ctx, d.Write, migrationsFS(t)); err != nil {
			t.Fatalf("db.Migrate: %v", err)
		}
		return New(d.Read, d.Write), func() { _ = d.Close() }
	}

	s, closeFirst := open()
	first, err := s.EnsureServerIdentity(ctx)
	if err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	// Idempotent within one process.
	again, err := s.EnsureServerIdentity(ctx)
	if err != nil {
		t.Fatalf("EnsureServerIdentity again: %v", err)
	}
	if again.PublicKey != first.PublicKey {
		t.Fatalf("key changed within one process: %q then %q", first.PublicKey, again.PublicKey)
	}
	closeFirst()

	// A restart must not hand out a different key: every paired device pins
	// the old one, and rotating it silently would lock all of them out.
	s2, closeSecond := open()
	defer closeSecond()
	restarted, err := s2.EnsureServerIdentity(ctx)
	if err != nil {
		t.Fatalf("EnsureServerIdentity after restart: %v", err)
	}
	if restarted.PublicKey != first.PublicKey {
		t.Fatalf("key changed across restart: %q then %q", first.PublicKey, restarted.PublicKey)
	}
}

func TestClaimIsAcceptedOnceAndThenDeadForever(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	if _, err := s.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}

	first, err := s.IssueClaimToken(ctx, 100)
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	if _, err := s.Pair(ctx, first, "dev-a", "test", 100); err != nil {
		t.Fatalf("first claim: %v", err)
	}

	// A brand-new claim token on an owned server is refused just the same:
	// ownership is not something a later token may hand over again.
	second, err := s.IssueClaimToken(ctx, 200)
	if err != nil {
		t.Fatalf("IssueClaimToken again: %v", err)
	}
	if _, err := s.Pair(ctx, second, "dev-b", "test", 200); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("second claim err = %v, want ErrTokenInvalid", err)
	}
}

func TestClaimTokenNeverExpires(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	if _, err := s.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}

	token, err := s.IssueClaimToken(ctx, 100)
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	// A year later. An expiring claim would leave a server that was installed
	// and forgotten unclaimable, with no way to mint another.
	if _, err := s.Pair(ctx, token, "dev-a", "test", 100+365*24*3600); err != nil {
		t.Fatalf("claim after a year: %v", err)
	}
}

func TestDeviceInviteExpiresAndIsDistinguishableFromASpentOne(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	owner := claimPerson(t, s, "dev-phone")

	expired, err := s.IssueDeviceInvite(ctx, owner.UserID, 100)
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	_, err = s.Pair(ctx, expired, "dev-late", "test", 100+InviteTTLSeconds+1)
	if !errors.Is(err, ErrTokenExpired) {
		t.Fatalf("expired invite err = %v, want ErrTokenExpired", err)
	}

	spent, err := s.IssueDeviceInvite(ctx, owner.UserID, 200)
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	if _, err := s.Pair(ctx, spent, "dev-desktop", "test", 200); err != nil {
		t.Fatalf("first use: %v", err)
	}
	// The two refusals are separate because the person's next action differs:
	// an expired invite means "issue a new one", a spent one means "you already
	// used this".
	if _, err := s.Pair(ctx, spent, "dev-tablet", "test", 300); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("spent invite err = %v, want ErrTokenInvalid", err)
	}
}

func TestTokenSurvivesRestart(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "tokens.db")

	open := func() (*Store, func()) {
		d, err := db.Open(path)
		if err != nil {
			t.Fatalf("db.Open: %v", err)
		}
		if _, err := db.Migrate(ctx, d.Write, migrationsFS(t)); err != nil {
			t.Fatalf("db.Migrate: %v", err)
		}
		return New(d.Read, d.Write), func() { _ = d.Close() }
	}

	s, closeFirst := open()
	if _, err := s.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	token, err := s.IssueClaimToken(ctx, 100)
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	closeFirst()

	// An invite has to outlive a restart, or it could not be shown to somebody
	// standing in the next room.
	s2, closeSecond := open()
	defer closeSecond()
	if _, err := s2.Pair(ctx, token, "dev-a", "test", 200); err != nil {
		t.Fatalf("pair after restart: %v", err)
	}
}

// The race this guards is the reason burning is a conditional UPDATE rather
// than a read followed by a write: two devices presenting one invite at the
// same moment must not both end up paired.
func TestOneInviteProducesExactlyOneDevice(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		s := newStore(t)
		ctx := context.Background()
		owner := claimPerson(t, s, "dev-phone")

		token, err := s.IssueDeviceInvite(ctx, owner.UserID, 200)
		if err != nil {
			t.Fatalf("IssueDeviceInvite: %v", err)
		}

		results := make(chan error, 2)
		for i, key := range []string{"dev-x", "dev-y"} {
			go func() {
				_, err := s.Pair(ctx, token, key, "test", 200+int64(i))
				results <- err
			}()
		}
		first, second := <-results, <-results

		wins := 0
		for _, err := range []error{first, second} {
			switch {
			case err == nil:
				wins++
			case errors.Is(err, ErrTokenInvalid):
			default:
				t.Fatalf("unexpected error: %v", err)
			}
		}
		if wins != 1 {
			t.Fatalf("%d of 2 simultaneous presentations succeeded, want exactly 1", wins)
		}

		devices, err := s.ListDevices(ctx, owner.UserID)
		if err != nil {
			t.Fatalf("ListDevices: %v", err)
		}
		if len(devices) != 2 {
			t.Fatalf("devices = %d, want 2 (the claimed one plus exactly one invited)", len(devices))
		}
	})
}

func TestRevokingAnAbsentKeyIsSuccess(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	// The caller asked for a state, and that state already holds. Reporting an
	// error would make a retry after a dropped connection look like a failure.
	if err := s.RevokeDevice(ctx, "dev-never-existed"); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}
}

func TestIdentitySurvivesTheRevocationOfItsLastDevice(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	owner := claimPerson(t, s, "dev-phone")

	if err := s.RevokeDevice(ctx, "dev-phone"); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}

	devices, err := s.ListDevices(ctx, owner.UserID)
	if err != nil {
		t.Fatalf("ListDevices: %v", err)
	}
	if len(devices) != 0 {
		t.Fatalf("devices = %d, want 0", len(devices))
	}

	// The person has to outlive their devices, or recovery would have nothing
	// to reattach a new one to.
	var people int
	if err := s.read.QueryRowContext(ctx, "SELECT COUNT(1) FROM users").Scan(&people); err != nil {
		t.Fatalf("count users: %v", err)
	}
	if people != 1 {
		t.Fatalf("users = %d, want 1", people)
	}
}

func TestDeviceListCarriesWhatDistinguishesADevice(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	owner := claimPerson(t, s, "dev-phone")

	devices, err := s.ListDevices(ctx, owner.UserID)
	if err != nil {
		t.Fatalf("ListDevices: %v", err)
	}
	if len(devices) != 1 {
		t.Fatalf("devices = %d, want 1", len(devices))
	}
	d := devices[0]
	if d.Platform == "" || d.CreatedAt == 0 || d.LastSeenAt == 0 {
		t.Fatalf("device = %+v: a row has to let a person recognise their own", d)
	}
}
