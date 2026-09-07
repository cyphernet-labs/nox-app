package store

import (
	"context"
	"errors"
	"path/filepath"
	"strings"
	"testing"
	"testing/synctest"

	"nox.app/client-backend/internal/db"
)

// pairID presents a token and flattens the result to the identity, for the
// many tests that expect a pairing to COMPLETE. Person invites do not complete
// here - they wait for the owner - so tests about those call Pair directly and
// read PairResult.Pending.
func pairID(ctx context.Context, s *Store, token, deviceKey, platform string, now int64) (Identity, error) {
	res, err := s.Pair(ctx, token, deviceKey, platform, now)
	return res.Identity, err
}

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
	if _, err := pairID(ctx, s, first, "dev-a", "test", 100); err != nil {
		t.Fatalf("first claim: %v", err)
	}

	// A brand-new claim token on an owned server is refused just the same:
	// ownership is not something a later token may hand over again.
	second, err := s.IssueClaimToken(ctx, 200)
	if err != nil {
		t.Fatalf("IssueClaimToken again: %v", err)
	}
	if _, err := pairID(ctx, s, second, "dev-b", "test", 200); !errors.Is(err, ErrTokenInvalid) {
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
	if _, err := pairID(ctx, s, token, "dev-a", "test", 100+365*24*3600); err != nil {
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
	_, err = pairID(ctx, s, expired, "dev-late", "test", 100+InviteTTLSeconds+1)
	if !errors.Is(err, ErrTokenExpired) {
		t.Fatalf("expired invite err = %v, want ErrTokenExpired", err)
	}

	spent, err := s.IssueDeviceInvite(ctx, owner.UserID, 200)
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	if _, err := pairID(ctx, s, spent, "dev-desktop", "test", 200); err != nil {
		t.Fatalf("first use: %v", err)
	}
	// The two refusals are separate because the person's next action differs:
	// an expired invite means "issue a new one", a spent one means "you already
	// used this".
	if _, err := pairID(ctx, s, spent, "dev-tablet", "test", 300); !errors.Is(err, ErrTokenInvalid) {
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
	if _, err := pairID(ctx, s2, token, "dev-a", "test", 200); err != nil {
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
				_, err := pairID(ctx, s, token, key, "test", 200+int64(i))
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

	first, err := pairID(ctx, s, token, "dev-phone", "ios", 100)
	if err != nil {
		t.Fatalf("first pair: %v", err)
	}

	again, err := pairID(ctx, s, token, "dev-phone", "ios", 200)
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
	if _, err := pairID(ctx, s, token, "dev-stranger", "linux", 300); !errors.Is(err, ErrTokenInvalid) {
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
	devices, err := countAllDevices(ctx, s.read)
	if err != nil {
		t.Fatalf("count devices: %v", err)
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
	back, err := pairID(ctx, s, token, "dev-new", "macos", 400)
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
	people, err := countPeople(ctx, s.read)
	if err != nil {
		t.Fatalf("count people: %v", err)
	}
	if people != 1 {
		t.Fatalf("users = %d, want 1: a re-claim must not leave an orphan behind", people)
	}

	// And with a device present again, a further claim is refused as before.
	second, err := s.IssueClaimToken(ctx, 500)
	if err != nil {
		t.Fatalf("IssueClaimToken again: %v", err)
	}
	if _, err := pairID(ctx, s, second, "dev-other", "linux", 500); !errors.Is(err, ErrTokenInvalid) {
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
	if _, err := pairID(ctx, s, used, "dev-phone", "ios", 100); err != nil {
		t.Fatalf("claim: %v", err)
	}

	// Every device revoked: the server is claimable again.
	if err := s.RevokeDevice(ctx, "dev-phone"); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}
	if _, err := pairID(ctx, s, stale, "dev-attacker", "linux", 200); !errors.Is(err, ErrTokenInvalid) {
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

	if _, err := pairID(ctx, s, invite, "dev-new", "linux", 300); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("an invite from a revoked device still works: %v", err)
	}
}

// Ownership arrives with the claim, in the transaction that creates the person.
// The whole point of the phase: before it, "who owns this machine" could only
// be guessed from row order, which stops being even a proxy in feature 034.
func TestClaimMakesThePersonTheOwner(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	if _, err := s.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	token, err := s.IssueClaimToken(ctx, 100)
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}

	id, err := pairID(ctx, s, token, "dev-phone", "test", 100)
	if err != nil {
		t.Fatalf("Pair: %v", err)
	}
	if !id.Owner {
		t.Fatal("the person who claimed the server does not own it")
	}

	machine, err := s.ServerIdentity(ctx)
	if err != nil {
		t.Fatalf("ServerIdentity: %v", err)
	}
	if machine.OwnerUserID != id.UserID {
		t.Fatalf("owner = %q, want %q", machine.OwnerUserID, id.UserID)
	}
	// The moment survives too. Nothing decides by it, but it is unrecoverable,
	// and it is written by the very statement this feature rewrote.
	if machine.ClaimedAt != 100 {
		t.Fatalf("claimed_at = %d, want 100: the timestamp must survive the switch to owner-based decisions", machine.ClaimedAt)
	}
}

// Ownership belongs to the PERSON, so their second device owns exactly what
// their first one does. A flag that described the connection would answer
// differently here, and the badge would flicker between devices.
func TestAnInvitedDeviceOfTheOwnerAlsoReportsOwnership(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	owner := claimPerson(t, s, "dev-phone")

	token, err := s.IssueDeviceInvite(ctx, owner.UserID, 200)
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	second, err := pairID(ctx, s, token, "dev-desktop", "test", 200)
	if err != nil {
		t.Fatalf("Pair second device: %v", err)
	}
	if !second.Owner {
		t.Fatal("the owner's second device does not report ownership")
	}
	if second.Created {
		t.Fatal("adding a device must not report having created a person")
	}
}

// The replay path answers about the same person, so it must answer the same
// way about ownership. It reads the owner rather than inferring it from the
// token kind - an invite replay is about a person who may or may not own.
func TestAReplayedClaimStillReportsOwnership(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	if _, err := s.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	token, err := s.IssueClaimToken(ctx, 100)
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	first, err := pairID(ctx, s, token, "dev-phone", "test", 100)
	if err != nil {
		t.Fatalf("Pair: %v", err)
	}

	replay, err := pairID(ctx, s, token, "dev-phone", "test", 150)
	if err != nil {
		t.Fatalf("replayed Pair: %v", err)
	}
	if replay.UserID != first.UserID || !replay.Owner {
		t.Fatalf("replay = %+v, want the same person still owning the server", replay)
	}
}

// Re-claiming a server that lost every device gives the SAME person their
// machine back. A second owner here would strand the first one's history under
// an author_id nobody can sign in as.
func TestReClaimKeepsOwnershipWithTheExistingPerson(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	owner := claimPerson(t, s, "dev-phone")

	if err := s.RevokeDevice(ctx, "dev-phone"); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}

	token, err := s.IssueClaimToken(ctx, 300)
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	back, err := pairID(ctx, s, token, "dev-new", "test", 300)
	if err != nil {
		t.Fatalf("re-claim: %v", err)
	}
	if back.UserID != owner.UserID {
		t.Fatalf("re-claim landed on %q, want the existing person %q", back.UserID, owner.UserID)
	}
	if !back.Owner {
		t.Fatal("the person who came back is no longer the owner")
	}
	if back.Created {
		t.Fatal("re-claim reported creating a person who already existed")
	}

	var people int
	if err := s.read.QueryRowContext(ctx, "SELECT COUNT(1) FROM users").Scan(&people); err != nil {
		t.Fatalf("count users: %v", err)
	}
	if people != 1 {
		t.Fatalf("users = %d, want 1: a re-claim must not mint a second person", people)
	}
}

// "Claimed" is read from the owner and nothing else. A store carrying the old
// timestamp but no owner is NOT claimed - which is what makes the two records
// impossible to disagree about.
func TestClaimedIsReadFromTheOwnerAndNotFromTheTimestamp(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	claimPerson(t, s, "dev-phone")

	if _, err := s.write.ExecContext(ctx, "UPDATE server_identity SET owner_user_id = NULL WHERE id = 1"); err != nil {
		t.Fatalf("clear owner: %v", err)
	}
	machine, err := s.ServerIdentity(ctx)
	if err != nil {
		t.Fatalf("ServerIdentity: %v", err)
	}
	if machine.ClaimedAt == 0 {
		t.Fatal("precondition: the timestamp should still be there")
	}
	if machine.OwnerUserID != "" {
		t.Fatal("a store with a timestamp but no owner reports itself claimed")
	}
}

// The re-claim follows the OWNER, not the oldest row. Once a second person can
// exist - which is what 034 brings - picking by row order would hand a fresh
// device somebody else's identity together with all of their history.
func TestReClaimFollowsTheOwnerAndNotTheOldestPerson(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	if _, err := s.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	owner := claimPerson(t, s, "dev-owner")
	// A guest whose row sorts BEFORE the owner's. Written directly, because a
	// server holds one person until invite-user (Q15) - this is the shape 034
	// produces, and the ordering is what makes the old `onlyUser` inference
	// pick the wrong one.
	if _, err := s.write.ExecContext(ctx,
		"INSERT INTO users (user_id, label, created_at) VALUES ('u_guest', 'Guest', 1)"); err != nil {
		t.Fatalf("insert guest: %v", err)
	}
	if err := s.RevokeDevice(ctx, "dev-owner"); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}

	token, err := s.IssueClaimToken(ctx, 300)
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	back, err := pairID(ctx, s, token, "dev-new", "test", 300)
	if err != nil {
		t.Fatalf("re-claim: %v", err)
	}
	if back.UserID != owner.UserID {
		t.Fatalf("re-claim landed on %q, want the OWNER %q - not the oldest row", back.UserID, owner.UserID)
	}
	if !back.Owner {
		t.Fatal("the owner came back without their ownership")
	}
}

// A store holding people but no owner is reachable only by hand-editing the
// database. Both available guesses are worse than a refusal and neither is
// undoable: attaching by row order hands a stranger somebody's history, and
// minting a new person orphans it.
func TestClaimIsRefusedOnAStoreWithPeopleButNoOwner(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	claimPerson(t, s, "dev-phone")
	if err := s.RevokeDevice(ctx, "dev-phone"); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}
	if _, err := s.write.ExecContext(ctx, "UPDATE server_identity SET owner_user_id = NULL WHERE id = 1"); err != nil {
		t.Fatalf("clear owner: %v", err)
	}

	token, err := s.IssueClaimToken(ctx, 400)
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	if _, err := pairID(ctx, s, token, "dev-stranger", "test", 400); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("err = %v, want ErrTokenInvalid: an ownerless store must not let a stranger into somebody's history", err)
	}
}

// The pair reply may not promise ownership the row does not hold. setOwner is
// conditional, so a claim that loses the race must answer honestly - otherwise
// the badge appears and the next greeting takes it away.
func TestPairNeverReportsOwnershipTheRowDoesNotHold(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	if _, err := s.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	// Somebody already owns the machine, and has no device left - so a claim is
	// still accepted, and it must land on THEM.
	if _, err := s.write.ExecContext(ctx,
		"INSERT INTO users (user_id, label, created_at) VALUES ('u_owner', 'Owner', 1)"); err != nil {
		t.Fatalf("insert owner: %v", err)
	}
	if _, err := s.write.ExecContext(ctx,
		"UPDATE server_identity SET owner_user_id = 'u_owner', claimed_at = 1 WHERE id = 1"); err != nil {
		t.Fatalf("set owner: %v", err)
	}

	token, err := s.IssueClaimToken(ctx, 500)
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	id, err := pairID(ctx, s, token, "dev-new", "test", 500)
	if err != nil {
		t.Fatalf("Pair: %v", err)
	}
	if id.UserID != "u_owner" || !id.Owner {
		t.Fatalf("pair answered %+v, want the existing owner still owning", id)
	}
}

// A device key already belonging to somebody is not up for grabs. The key is
// public - it rides every greeting and device.list prints it - so rebinding on
// conflict would let anyone who can issue an invite name a stranger's key and
// walk off with their device.
//
// The reply and the row still have to agree; refusing is how, not rebinding.
func TestPairingSomebodyElsesDeviceKeyIsRefused(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	owner := claimPerson(t, s, "dev-shared")

	// A second person, and an invite of theirs presented by the SAME key.
	if _, err := s.write.ExecContext(ctx,
		"INSERT INTO users (user_id, label, created_at) VALUES ('u_guest', 'Guest', 200)"); err != nil {
		t.Fatalf("insert guest: %v", err)
	}
	token, err := s.IssueDeviceInvite(ctx, "u_guest", 200)
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	if _, err := pairID(ctx, s, token, "dev-shared", "test", 200); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("err = %v, want ErrTokenInvalid: a paired device must not change hands", err)
	}

	// The device still belongs to the person who paired it, and still answers
	// as them - with their ownership.
	greeted, err := s.ResolveIdentity(ctx, "dev-shared", "", 300)
	if err != nil {
		t.Fatalf("ResolveIdentity: %v", err)
	}
	if greeted.UserID != owner.UserID {
		t.Fatalf("the device now answers as %q, want its owner %q", greeted.UserID, owner.UserID)
	}
	if !greeted.Owner {
		t.Fatal("the device lost its person's ownership")
	}
}

// Re-pairing a device to the SAME person stays allowed: that is an ordinary
// repeat, not a takeover.
func TestPairingYourOwnDeviceKeyAgainIsAccepted(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	owner := claimPerson(t, s, "dev-mine")

	token, err := s.IssueDeviceInvite(ctx, owner.UserID, 200)
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	again, err := pairID(ctx, s, token, "dev-mine", "test", 200)
	if err != nil {
		t.Fatalf("re-pairing my own device: %v", err)
	}
	if again.UserID != owner.UserID || !again.Owner {
		t.Fatalf("answered %+v, want the same person still owning", again)
	}
}

// A replay answers about the device's person and reports the outcome computed
// from the token, so the two must belong together. Otherwise a claim token
// replayed by a device that now belongs to somebody else would report
// `created: true` about an existing, already-named person - walking them back
// through the naming screen under a stranger's identity.
func TestAReplayWhoseTokenAndDeviceDisagreeIsNotAnswered(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	owner := claimPerson(t, s, "dev-phone")

	// A second person and a spent invite of theirs, with the device still
	// belonging to the owner. Written directly: pairing refuses to produce this
	// state, and that refusal is what the test above pins - this one covers the
	// replay path if the state is ever reached another way.
	if _, err := s.write.ExecContext(ctx,
		"INSERT INTO users (user_id, label, created_at) VALUES ('u_guest', 'Guest', 200)"); err != nil {
		t.Fatalf("insert guest: %v", err)
	}
	token, err := s.IssueDeviceInvite(ctx, "u_guest", 200)
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	if _, err := s.write.ExecContext(ctx,
		"UPDATE pair_tokens SET used_at = 200 WHERE token = ?", token); err != nil {
		t.Fatalf("burn token: %v", err)
	}

	// The replay must not answer about the owner using the guest's token.
	if _, err := pairID(ctx, s, token, "dev-phone", "test", 300); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("err = %v, want ErrTokenInvalid: the token names one person and the device another", err)
	}
	_ = owner
}

// A spent token answers only the device that spent it. Before used_by existed,
// a claim token named nobody, so any KNOWN device key - and the key is public,
// it rides every greeting and device.list prints it - could present a spent
// claim from the server log and be told that person's id, label and ownership.
// `pair` is the one command that carries no signature.
func TestASpentTokenAnswersOnlyTheDeviceThatSpentIt(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	if _, err := s.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	claim, err := s.IssueClaimToken(ctx, 100)
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	owner, err := pairID(ctx, s, claim, "dev-a", "test", 100)
	if err != nil {
		t.Fatalf("Pair: %v", err)
	}

	// A second device of the same person, joined the ordinary way.
	invite, err := s.IssueDeviceInvite(ctx, owner.UserID, 200)
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	if _, err := pairID(ctx, s, invite, "dev-b", "test", 200); err != nil {
		t.Fatalf("Pair second device: %v", err)
	}

	// dev-b presenting the spent claim must learn nothing.
	if _, err := pairID(ctx, s, claim, "dev-b", "test", 300); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("err = %v, want ErrTokenInvalid: a spent token must not answer a device that never used it", err)
	}
	// A key nobody knows either.
	if _, err := pairID(ctx, s, claim, "dev-stranger", "test", 300); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("err = %v, want ErrTokenInvalid", err)
	}
	// And the device that DID spend it still gets its answer.
	replay, err := pairID(ctx, s, claim, "dev-a", "test", 300)
	if err != nil {
		t.Fatalf("replay by the spender: %v", err)
	}
	if replay.UserID != owner.UserID || !replay.Created {
		t.Fatalf("replay = %+v, want the original answer back", replay)
	}
}

// A replay answers with what HAPPENED, not with what the token kind implies. A
// re-claim that attached to an existing owner created nobody, and re-deriving
// "this was a claim, so created" walks that owner back through the naming
// screen and lets them overwrite their own name.
func TestAReplayedReClaimDoesNotClaimToHaveCreatedAnybody(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	claimPerson(t, s, "dev-phone")
	if err := s.RevokeDevice(ctx, "dev-phone"); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}

	token, err := s.IssueClaimToken(ctx, 300)
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	first, err := pairID(ctx, s, token, "dev-new", "test", 300)
	if err != nil {
		t.Fatalf("re-claim: %v", err)
	}
	if first.Created {
		t.Fatal("a re-claim reported creating a person who already existed")
	}

	replay, err := pairID(ctx, s, token, "dev-new", "test", 350)
	if err != nil {
		t.Fatalf("replayed re-claim: %v", err)
	}
	if replay.Created != first.Created {
		t.Fatalf("replay says created=%v, the original said %v", replay.Created, first.Created)
	}
}

// A restore that brings back people without the machine's own row must not be
// handed a fresh keypair: that breaks pinning for every device paired against
// the old one, silently, and the right answer is to finish the restore.
func TestAStoreWithPeopleAndNoServerIdentityRefusesToMintANewKey(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	claimPerson(t, s, "dev-phone")

	if _, err := s.write.ExecContext(ctx, "DELETE FROM server_identity"); err != nil {
		t.Fatalf("simulate a partial restore: %v", err)
	}
	_, err := s.EnsureServerIdentity(ctx)
	if err == nil {
		t.Fatal("a new server key was minted for a store that already holds people")
	}
	if !strings.Contains(err.Error(), "restore") {
		t.Fatalf("the refusal does not say what to do: %v", err)
	}
}

// The owner is not locked out of their own machine by somebody else's device.
// Counting every device on the server - rather than the owner's - would do
// exactly that once 034 puts a guest on it: the owner logs out, a guest device
// keeps running, and the owner's own claim link is refused for ever.
func TestAGuestDeviceDoesNotBlockTheOwnersReClaim(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	owner := claimPerson(t, s, "dev-owner")

	// A guest with a live device. Written directly: 034 is what produces this.
	if _, err := s.write.ExecContext(ctx,
		"INSERT INTO users (user_id, label, created_at) VALUES ('u_guest', 'Guest', 200)"); err != nil {
		t.Fatalf("insert guest: %v", err)
	}
	if _, err := s.write.ExecContext(ctx,
		"INSERT INTO devices (device_key, user_id, platform, created_at, last_seen_at) VALUES ('dev-guest', 'u_guest', 'test', 200, 200)"); err != nil {
		t.Fatalf("insert guest device: %v", err)
	}
	// The owner logs out: their last device goes, the guest's stays.
	if err := s.RevokeDevice(ctx, "dev-owner"); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}

	token, err := s.IssueClaimToken(ctx, 300)
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	back, err := pairID(ctx, s, token, "dev-owner-new", "test", 300)
	if err != nil {
		t.Fatalf("the owner cannot get back into their own machine: %v", err)
	}
	if back.UserID != owner.UserID || !back.Owner {
		t.Fatalf("re-claim answered %+v, want the owner back", back)
	}
}

// And a claim is still refused while the owner HAS a device: that is the rule
// the count exists for.
func TestAClaimIsStillRefusedWhileTheOwnerHasADevice(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	claimPerson(t, s, "dev-owner")

	token, err := s.IssueClaimToken(ctx, 300)
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	if _, err := pairID(ctx, s, token, "dev-other", "test", 300); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("err = %v, want ErrTokenInvalid", err)
	}
}

// A replay reproduces the recorded answer, not the device's current binding.
// After a logout and a re-pair the same key can belong to a different moment in
// this person's life - and once 034 lands, to a different person entirely.
func TestAReplayAnswersWithWhatTheTokenProducedNotWhoHoldsTheKeyNow(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	if _, err := s.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	claim, err := s.IssueClaimToken(ctx, 100)
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	first, err := pairID(ctx, s, claim, "dev-x", "test", 100)
	if err != nil {
		t.Fatalf("Pair: %v", err)
	}
	if !first.Created {
		t.Fatal("the first claim should have created the person")
	}

	// Log out, come back with a new device, then bring dev-x back by invite.
	if err := s.RevokeDevice(ctx, "dev-x"); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}
	again, err := s.IssueClaimToken(ctx, 200)
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	back, err := pairID(ctx, s, again, "dev-new", "test", 200)
	if err != nil {
		t.Fatalf("re-claim: %v", err)
	}
	if back.Created {
		t.Fatal("the re-claim created a person who already existed")
	}
	invite, err := s.IssueDeviceInvite(ctx, back.UserID, 300)
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	if _, err := pairID(ctx, s, invite, "dev-x", "test", 300); err != nil {
		t.Fatalf("re-adding dev-x: %v", err)
	}

	// The ORIGINAL claim token replayed by dev-x answers what it produced then.
	replay, err := pairID(ctx, s, claim, "dev-x", "test", 400)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if replay.UserID != first.UserID || replay.Created != first.Created {
		t.Fatalf("replay = %+v, want the original answer %+v", replay, first)
	}
}

// A replay must not slip past the takeover refusal. Answering from the token's
// own record is right, but only while the device it names still belongs to the
// person it produced - otherwise a key rebound to somebody else is handed that
// person's identity, label and ownership, and the client writes all three onto
// the wrong device.
func TestAReplayIsRefusedOnceTheDeviceBelongsToSomebodyElse(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	if _, err := s.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	claim, err := s.IssueClaimToken(ctx, 100)
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	produced, err := pairID(ctx, s, claim, "dev-x", "test", 100)
	if err != nil {
		t.Fatalf("Pair: %v", err)
	}

	// dev-x ends up bound to somebody else. Written directly: Pair refuses to
	// produce this, and a restore is what reaches it today.
	if _, err := s.write.ExecContext(ctx,
		"INSERT INTO users (user_id, label, created_at) VALUES ('u_other', 'Other', 200)"); err != nil {
		t.Fatalf("insert other: %v", err)
	}
	if _, err := s.write.ExecContext(ctx,
		"UPDATE devices SET user_id = 'u_other' WHERE device_key = 'dev-x'"); err != nil {
		t.Fatalf("rebind device: %v", err)
	}

	if _, err := pairID(ctx, s, claim, "dev-x", "test", 300); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("err = %v, want ErrTokenInvalid: the replay handed over %q's identity", err, produced.UserID)
	}
}

// countAllDevices is the total this feature deliberately stopped deciding by;
// tests still assert on it, so it lives here rather than on the Store.
func countAllDevices(ctx context.Context, q rowQuerier) (int, error) {
	var n int
	if err := q.QueryRowContext(ctx, "SELECT COUNT(1) FROM devices").Scan(&n); err != nil {
		return 0, err
	}
	return n, nil
}
