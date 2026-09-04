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

// `pair` commits and then replies, so a connection that drops in that window
// leaves the device paired and the client believing nothing happened. With a
// one-shot claim and a single device, refusing the retry locks the machine.
func TestARetryFromTheSameDeviceGetsTheSameAnswer(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	if _, err := s.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	token, err := s.IssueClaimToken(ctx, 100)
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}

	first, err := s.Pair(ctx, token, "dev-phone", "ios", 100)
	if err != nil {
		t.Fatalf("first pair: %v", err)
	}

	again, err := s.Pair(ctx, token, "dev-phone", "ios", 200)
	if err != nil {
		t.Fatalf("retry from the same device: %v", err)
	}
	if again.UserID != first.UserID {
		t.Fatalf("retry resolved to %q, want %q", again.UserID, first.UserID)
	}
	// The SAME answer the lost reply carried, `created` included. Saying false
	// here would walk the owner of a brand-new server past the naming step and
	// into the chats list under an auto-assigned User<random>.
	if again.Created != first.Created {
		t.Fatalf("retry reported created=%v, want %v - a replay must repeat the answer, not invent one", again.Created, first.Created)
	}

	// A DIFFERENT key presenting the same spent token is an ordinary replay.
	if _, err := s.Pair(ctx, token, "dev-stranger", "linux", 300); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("stranger replay err = %v, want ErrTokenInvalid", err)
	}
}

// Revoking the last device used to lock the machine forever: the claim was
// spent, no device remained to issue an invite from, and recovery is Q16.
func TestAServerWithNoDevicesBecomesClaimableAgain(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	owner := claimPerson(t, s, "dev-phone")

	if err := s.RevokeDevice(ctx, "dev-phone"); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}
	devices, err := s.CountDevices(ctx)
	if err != nil {
		t.Fatalf("CountDevices: %v", err)
	}
	if devices != 0 {
		t.Fatalf("devices = %d, want 0", devices)
	}

	// The machine is the root of trust: whoever can read its output takes it
	// back. The person survives - a new device attaches to the same server.
	token, err := s.IssueClaimToken(ctx, 400)
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	back, err := s.Pair(ctx, token, "dev-new", "macos", 400)
	if err != nil {
		t.Fatalf("re-claim: %v", err)
	}
	// The SAME person, not a second one. A new identity would orphan the old:
	// their messages keep an author_id nobody can sign in as, and "the identity
	// survives its devices" would be true on paper and worthless in practice.
	if back.UserID != owner.UserID {
		t.Fatalf("re-claim minted %q, want the existing person %q", back.UserID, owner.UserID)
	}
	if back.Created {
		t.Fatal("reattaching to an existing person must not report created - they already have a name")
	}
	people, err := s.CountUsers(ctx)
	if err != nil {
		t.Fatalf("CountUsers: %v", err)
	}
	if people != 1 {
		t.Fatalf("users = %d, want 1: a re-claim must not leave an orphan behind", people)
	}

	// And with a device present again, a further claim is refused as before.
	second, err := s.IssueClaimToken(ctx, 500)
	if err != nil {
		t.Fatalf("IssueClaimToken again: %v", err)
	}
	if _, err := s.Pair(ctx, second, "dev-other", "linux", 500); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("claim on a reachable server err = %v, want ErrTokenInvalid", err)
	}
}

// A claim link is printed to the server log, and a log is not a secret store.
// Every unused one has to die with the claim that succeeded, or the oldest
// scrap of terminal scrollback becomes a way in the next time the device count
// reaches zero.
func TestASuccessfulClaimRetiresEveryOtherClaimToken(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	if _, err := s.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	stale, err := s.IssueClaimToken(ctx, 100)
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	used, err := s.IssueClaimToken(ctx, 100)
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	if _, err := s.Pair(ctx, used, "dev-phone", "ios", 100); err != nil {
		t.Fatalf("claim: %v", err)
	}

	// Every device revoked: the server is claimable again.
	if err := s.RevokeDevice(ctx, "dev-phone"); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}
	if _, err := s.Pair(ctx, stale, "dev-attacker", "linux", 200); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("an old printed claim token still works: %v", err)
	}
}

// A revoked device may have issued an invite minutes ago. Leaving it usable
// removes the key and leaves the door it opened.
func TestRevokingADeviceRetiresTheInvitesItCouldHaveIssued(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	owner := claimPerson(t, s, "dev-phone")

	invite, err := s.IssueDeviceInvite(ctx, owner.UserID, 200)
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	if err := s.RevokeDevice(ctx, "dev-phone"); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}

	if _, err := s.Pair(ctx, invite, "dev-new", "linux", 300); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("an invite from a revoked device still works: %v", err)
	}
}
