package store

import (
	"context"
	"errors"
	"path/filepath"
	"strings"
	"testing"

	"nox.app/client-backend/internal/db"
)

// issueLink mints a machine link at now and returns its token.
func issueLink(t *testing.T, s *Store, now int64) string {
	t.Helper()
	link, err := s.IssueMachineLink(context.Background(), now)
	if err != nil {
		t.Fatalf("IssueMachineLink: %v", err)
	}
	return link.Token
}

// pairID presents a token and returns the identity it paired the device as,
// failing the test when the presentation paired nothing.
func pairID(ctx context.Context, s *Store, token, deviceKey, platform string, now int64) (Identity, error) {
	res, err := s.Pair(ctx, token, deviceKey, platform, now)
	if err != nil {
		return Identity{}, err
	}
	if !res.Paired {
		return Identity{}, errors.New("the token opened a request instead of pairing")
	}
	return res.Identity, nil
}

// pairFirst pairs a device through the machine link the way the first device
// of a fresh install does, and returns who it now speaks as.
func pairFirst(t *testing.T, s *Store, deviceKey string) Identity {
	t.Helper()
	ctx := context.Background()
	if _, err := s.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	id, err := pairID(ctx, s, issueLink(t, s, 100), deviceKey, "test", 100)
	if err != nil {
		t.Fatalf("pair through the machine link: %v", err)
	}
	return id
}

// unspentMachineLinks counts the machine links that could still be presented
// or shown - the property SC-004 is about.
func unspentMachineLinks(t *testing.T, s *Store) int {
	t.Helper()
	var n int
	if err := s.read.QueryRowContext(context.Background(),
		"SELECT COUNT(1) FROM pair_tokens WHERE kind = 'machine' AND used_at IS NULL").Scan(&n); err != nil {
		t.Fatalf("count machine links: %v", err)
	}
	return n
}

func TestServerKeyIsMintedOnceAndSurvivesRestart(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "key.db")

	open := func() (*Store, func()) {
		d, err := db.Open(path, testKey)
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
	if !again.PublicKey.Equal(first.PublicKey) {
		t.Fatalf("key changed within one process: %x then %x", first.PublicKey, again.PublicKey)
	}
	closeFirst()

	// A restart must not hand out a different key: every paired device expects
	// the old one, and rotating it silently would lock all of them out.
	s2, closeSecond := open()
	defer closeSecond()
	restarted, err := s2.EnsureServerIdentity(ctx)
	if err != nil {
		t.Fatalf("EnsureServerIdentity after restart: %v", err)
	}
	if !restarted.PublicKey.Equal(first.PublicKey) {
		t.Fatalf("key changed across restart: %x then %x", first.PublicKey, restarted.PublicKey)
	}
}

// FR-002: ten minutes, and not a second more. A link presented at its expiry
// second is already late - the same boundary MachineLink.Live draws for the
// page.
func TestAMachineLinkLivesTenMinutes(t *testing.T) {
	ctx := context.Background()
	for _, tc := range []struct {
		name string
		at   int64
		want error
	}{
		{"a second before the deadline", 100 + TokenTTLSeconds - 1, nil},
		{"at the deadline", 100 + TokenTTLSeconds, ErrTokenExpired},
		{"a day later", 100 + 24*3600, ErrTokenExpired},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s := newStore(t)
			link, err := s.IssueMachineLink(ctx, 100)
			if err != nil {
				t.Fatalf("IssueMachineLink: %v", err)
			}
			if link.ExpiresAt != 100+TokenTTLSeconds {
				t.Fatalf("expires_at = %d, want ten minutes after issue", link.ExpiresAt)
			}
			if got := link.Live(tc.at); got != (tc.want == nil) {
				t.Fatalf("Live(%d) = %v", tc.at, got)
			}
			_, err = pairID(ctx, s, link.Token, "dev-a", "test", tc.at)
			if !errors.Is(err, tc.want) {
				t.Fatalf("pair at %d = %v, want %v", tc.at, err, tc.want)
			}
		})
	}
}

// SC-004: at most one live machine link. A new one voids the one before it -
// whatever the page showed a moment ago, or the terminal printed, stops
// working - and the count of links that could still be presented stays one.
func TestIssuingAMachineLinkVoidsTheEarlierOne(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	first := issueLink(t, s, 100)
	second := issueLink(t, s, 160)
	if got := unspentMachineLinks(t, s); got != 1 {
		t.Fatalf("unspent machine links = %d, want 1", got)
	}
	if _, err := pairID(ctx, s, first, "dev-a", "test", 170); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("the voided link answered %v, want ErrTokenInvalid", err)
	}
	if _, err := pairID(ctx, s, second, "dev-a", "test", 170); err != nil {
		t.Fatalf("the live link: %v", err)
	}
	if got := unspentMachineLinks(t, s); got != 0 {
		t.Fatalf("unspent machine links after the pairing = %d, want 0", got)
	}
}

// FR-004: the machine link creates the person when there is nobody, and joins
// them - with no naming step - when there is. It works while devices exist: it
// is how a person adds a device with none in hand, and the refusal the claim
// once carried is gone with the claim.
func TestTheMachineLinkCreatesThePersonOnceAndJoinsAfter(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	first, err := pairID(ctx, s, issueLink(t, s, 100), "dev-a", "ios", 100)
	if err != nil {
		t.Fatalf("first device: %v", err)
	}
	if !first.Created {
		t.Fatal("the first device on an empty machine must bring the person into being")
	}
	second, err := pairID(ctx, s, issueLink(t, s, 200), "dev-b", "macos", 200)
	if err != nil {
		t.Fatalf("second device while the first is still paired: %v", err)
	}
	if second.UserID != first.UserID || second.Created {
		t.Fatalf("second device = %+v, want the same person %q and created=false", second, first.UserID)
	}
	if people, err := countPeople(ctx, s.read); err != nil || people != 1 {
		t.Fatalf("people = %d (%v), want 1", people, err)
	}
	devices, err := s.ListDevices(ctx, first.UserID)
	if err != nil || len(devices) != 2 {
		t.Fatalf("devices = %d (%v), want 2", len(devices), err)
	}
}

func TestTokenSurvivesRestart(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "tokens.db")

	open := func() (*Store, func()) {
		d, err := db.Open(path, testKey)
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
	token := issueLink(t, s, 100)
	closeFirst()

	// A link has to outlive a restart inside its ten minutes, or it could not
	// be carried to a phone in the next room while the service restarts.
	s2, closeSecond := open()
	defer closeSecond()
	if _, err := pairID(ctx, s2, token, "dev-a", "test", 200); err != nil {
		t.Fatalf("pair after restart: %v", err)
	}
}

func TestRevokingAnAbsentKeyIsSuccess(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	// The caller asked for a state, and that state already holds. Reporting an
	// error would make a retry after a dropped connection look like a failure.
	if _, err := s.RevokeDevice(ctx, "dev-never-existed", 100); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}
}

func TestIdentitySurvivesTheRevocationOfItsLastDevice(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	person := pairFirst(t, s, "dev-phone")

	if _, err := s.RevokeDevice(ctx, "dev-phone", 200); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}

	devices, err := s.ListDevices(ctx, person.UserID)
	if err != nil {
		t.Fatalf("ListDevices: %v", err)
	}
	if len(devices) != 0 {
		t.Fatalf("devices = %d, want 0", len(devices))
	}

	// The person has to outlive their devices, or the machine link would have
	// nobody to join the next device to.
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
	person := pairFirst(t, s, "dev-phone")

	devices, err := s.ListDevices(ctx, person.UserID)
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
// leaves the device paired and the client believing nothing happened. Refusing
// the retry would leave it without the identity it was just given.
func TestARetryFromTheSameDeviceGetsTheSameAnswer(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	token := issueLink(t, s, 100)

	first, err := pairID(ctx, s, token, "dev-phone", "ios", 100)
	if err != nil {
		t.Fatalf("first pair: %v", err)
	}
	// After the deadline too: the deadline was met by the spending, and the
	// retry is about an answer that got lost, not about the link.
	again, err := pairID(ctx, s, token, "dev-phone", "ios", 100+TokenTTLSeconds+5)
	if err != nil {
		t.Fatalf("retry from the same device: %v", err)
	}
	if again.UserID != first.UserID {
		t.Fatalf("retry resolved to %q, want %q", again.UserID, first.UserID)
	}
	// The SAME answer the lost reply carried, `created` included. Saying false
	// here would walk the person of a brand-new server past the naming step and
	// into the chats list under an auto-assigned User<random>.
	if again.Created != first.Created {
		t.Fatalf("retry reported created=%v, want %v - a replay must repeat the answer, not invent one", again.Created, first.Created)
	}

	// A DIFFERENT key presenting the same spent token is an ordinary replay.
	if _, err := pairID(ctx, s, token, "dev-stranger", "linux", 300); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("stranger replay err = %v, want ErrTokenInvalid", err)
	}
}

// SC-003 at the store: every device gone, the person and the conversation stay,
// and the machine link joins the next device to the SAME person - not a second
// one, whose messages would carry an author_id nobody can sign in as.
func TestTheMachineLinkJoinsThePersonWhoLostEveryDevice(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	person := pairFirst(t, s, "dev-phone")
	chat, _, _, err := s.CreateChat(ctx, "", "Kitchen", person.Label, 150)
	if err != nil {
		t.Fatalf("CreateChat: %v", err)
	}
	if _, _, _, err := s.SendMessage(ctx, chat.ChatID, "m1", person, textBody("the boiler"), "", 160); err != nil {
		t.Fatalf("SendMessage: %v", err)
	}
	if _, err := s.RevokeDevice(ctx, "dev-phone", 200); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}

	back, err := pairID(ctx, s, issueLink(t, s, 300), "dev-new", "macos", 300)
	if err != nil {
		t.Fatalf("pair after losing every device: %v", err)
	}
	if back.UserID != person.UserID || back.Created {
		t.Fatalf("came back as %+v, want %q with no naming step", back, person.UserID)
	}
	messages, _, err := s.ListMessages(ctx, chat.ChatID, 0, 10)
	if err != nil || len(messages) != 1 || messages[0].AuthorID != back.UserID {
		t.Fatalf("history after coming back = %+v (%v), want the message, authored by the person who came back", messages, err)
	}
}

// A revoked device may have issued an invite minutes ago. Leaving it usable
// would let whoever holds that link ask the person's other devices to let them
// in on the authority of a device that was just told to leave. The invites of
// the person's OTHER devices are theirs and survive.
func TestRevokingADeviceVoidsTheInvitesItIssuedAndOnlyThose(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	pairFirst(t, s, "dev-phone")
	if _, err := pairID(ctx, s, issueLink(t, s, 150), "dev-laptop", "macos", 150); err != nil {
		t.Fatalf("second device: %v", err)
	}

	fromPhone, err := s.IssueDeviceInvite(ctx, "dev-phone", 200)
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	fromLaptop, err := s.IssueDeviceInvite(ctx, "dev-laptop", 200)
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	if _, err := s.RevokeDevice(ctx, "dev-phone", 250); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}

	if _, err := s.Pair(ctx, fromPhone, "dev-new", "linux", 300); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("an invite from a revoked device still opened a request: %v", err)
	}
	res, err := s.Pair(ctx, fromLaptop, "dev-new", "linux", 300)
	if err != nil || res.Request == nil || res.Request.Outcome != "" {
		t.Fatalf("the laptop's invite = %+v (%v), want a waiting request", res, err)
	}
}

// Re-pairing a device to the SAME person stays allowed: that is an ordinary
// repeat, not a takeover.
func TestPairingYourOwnDeviceKeyAgainIsAccepted(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	person := pairFirst(t, s, "dev-mine")

	again, err := pairID(ctx, s, issueLink(t, s, 200), "dev-mine", "test", 200)
	if err != nil {
		t.Fatalf("re-pairing my own device: %v", err)
	}
	if again.UserID != person.UserID || again.Created {
		t.Fatalf("answered %+v, want the same person and no naming step", again)
	}
	devices, err := s.ListDevices(ctx, person.UserID)
	if err != nil || len(devices) != 1 {
		t.Fatalf("devices = %d (%v), want the one row refreshed, not a second", len(devices), err)
	}
}

// A spent token answers only the device that spent it. `pair` is the one
// command a key the server does not know may send, and the person's id and
// label are what it would learn.
func TestASpentTokenAnswersOnlyTheDeviceThatSpentIt(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	first := issueLink(t, s, 100)
	person, err := pairID(ctx, s, first, "dev-a", "test", 100)
	if err != nil {
		t.Fatalf("Pair: %v", err)
	}
	if _, err := pairID(ctx, s, issueLink(t, s, 200), "dev-b", "test", 200); err != nil {
		t.Fatalf("Pair second device: %v", err)
	}

	// dev-b presenting the spent first link must learn nothing.
	if _, err := pairID(ctx, s, first, "dev-b", "test", 300); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("err = %v, want ErrTokenInvalid: a spent token must not answer a device that never used it", err)
	}
	// A key nobody knows either.
	if _, err := pairID(ctx, s, first, "dev-stranger", "test", 300); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("err = %v, want ErrTokenInvalid", err)
	}
	// And the device that DID spend it still gets its answer.
	replay, err := pairID(ctx, s, first, "dev-a", "test", 300)
	if err != nil {
		t.Fatalf("replay by the spender: %v", err)
	}
	if replay.UserID != person.UserID || !replay.Created {
		t.Fatalf("replay = %+v, want the original answer back", replay)
	}
}

// A replay answers with what HAPPENED, not with what the token kind implies. A
// machine link that joined an existing person created nobody, and re-deriving
// "a machine link, so created" walks that person back through the naming
// screen and lets them overwrite their own name.
func TestAReplayOfAJoiningMachineLinkDoesNotSayCreated(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	pairFirst(t, s, "dev-phone")
	if _, err := s.RevokeDevice(ctx, "dev-phone", 150); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}

	token := issueLink(t, s, 300)
	first, err := pairID(ctx, s, token, "dev-new", "test", 300)
	if err != nil {
		t.Fatalf("pair: %v", err)
	}
	if first.Created {
		t.Fatal("joining an existing person reported creating them")
	}
	replay, err := pairID(ctx, s, token, "dev-new", "test", 350)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if replay.Created != first.Created {
		t.Fatalf("replay says created=%v, the original said %v", replay.Created, first.Created)
	}
}

// A restore that brings back people without the machine's own row must not be
// handed a fresh keypair: that locks out every device paired against the old
// one, silently, and the right answer is to finish the restore.
func TestAStoreWithPeopleAndNoServerIdentityRefusesToMintANewKey(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	pairFirst(t, s, "dev-phone")

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

// A replay reproduces the recorded answer, not the device's current binding.
// After a logout and a re-pair the same key belongs to a different moment in
// this person's life, and the token has to keep answering with the one it
// settled.
func TestAReplayAnswersWithWhatTheTokenProducedNotWhoHoldsTheKeyNow(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	original := issueLink(t, s, 100)
	first, err := pairID(ctx, s, original, "dev-x", "test", 100)
	if err != nil {
		t.Fatalf("Pair: %v", err)
	}
	if !first.Created {
		t.Fatal("the first link should have created the person")
	}

	// Sign out, come back with a new device, then bring dev-x back too.
	if _, err := s.RevokeDevice(ctx, "dev-x", 150); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}
	if back, err := pairID(ctx, s, issueLink(t, s, 200), "dev-new", "test", 200); err != nil || back.Created {
		t.Fatalf("coming back = %+v (%v), want the existing person", back, err)
	}
	if _, err := pairID(ctx, s, issueLink(t, s, 300), "dev-x", "test", 300); err != nil {
		t.Fatalf("re-adding dev-x: %v", err)
	}

	// The ORIGINAL link replayed by dev-x answers what it produced then.
	replay, err := pairID(ctx, s, original, "dev-x", "test", 400)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if replay.UserID != first.UserID || replay.Created != first.Created {
		t.Fatalf("replay = %+v, want the original answer %+v", replay, first)
	}
}

// The three tests this replaced each began by inserting a second person by
// hand, to check that one person's device could not be taken over by another.
// That situation is unrepresentable rather than merely refused, so the schema
// is what gets tested. The takeover guard in bindDevice stays where it is: it
// is two lines on an authentication path, and it should hold the invariant
// rather than assume it.
func TestASecondPersonCannotBeCreatedByAnyMeans(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	pairFirst(t, s, "dev-first")

	_, err := s.write.ExecContext(ctx,
		"INSERT INTO users (user_id, label, created_at) VALUES (?, ?, ?)", "u_second", "Second", 500)
	if err == nil {
		t.Fatal("a second person was inserted; this machine belongs to one human being")
	}
	if !strings.Contains(err.Error(), "idx_users_singleton") {
		t.Fatalf("refused by %v, want the singleton index", err)
	}

	// The one person is untouched by the attempt.
	people, err := countPeople(ctx, s.read)
	if err != nil {
		t.Fatalf("countPeople: %v", err)
	}
	if people != 1 {
		t.Fatalf("people = %d, want 1", people)
	}
	if _, err := s.ResolveIdentity(ctx, "dev-first", "", 600); err != nil {
		t.Fatalf("the person stopped resolving: %v", err)
	}
}

// The replay path answers only while the device that spent the token still
// belongs to the person it produced. Without that join a revoked key would be
// handed the original person's id and label - and the client would write both
// into a device the server no longer knows.
func TestAReplayIsRefusedOnceTheDeviceIsNoLongerTheOneThatSpentIt(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	pairFirst(t, s, "dev-first")

	token := issueLink(t, s, 200)
	if _, err := pairID(ctx, s, token, "dev-second", "test", 200); err != nil {
		t.Fatalf("pair the second device: %v", err)
	}
	// The replay works while the device is still there.
	if _, err := pairID(ctx, s, token, "dev-second", "test", 210); err != nil {
		t.Fatalf("replay before revocation: %v", err)
	}

	if _, err := s.RevokeDevice(ctx, "dev-second", 215); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}

	// And stops the moment it is not. Refused as a spent token rather than
	// answered: the row says who the token produced, but the device that
	// presented it is no longer that person's.
	if _, err := pairID(ctx, s, token, "dev-second", "test", 220); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("replay answered %v, want it refused once the device was revoked", err)
	}
}

// The page mints a link for a machine nobody can reach, and only once for each
// such stretch: reloading it never mints again, and with devices present the
// page offers "Add a device" rather than a link nobody asked for.
func TestThePageMintsALinkOnlyForAMachineNobodyCanReach(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	page, err := s.PageMachineLink(ctx, 100)
	if err != nil || !page.Found || page.Devices != 0 {
		t.Fatalf("a fresh machine's page = %+v (%v), want a link at once", page, err)
	}
	minted := page.Link
	if !minted.Live(100) || minted.ExpiresAt != 100+TokenTTLSeconds {
		t.Fatalf("minted %+v, want a live ten-minute link", minted)
	}
	again, err := s.PageMachineLink(ctx, 130)
	if err != nil || !again.Found || again.Link != minted {
		t.Fatalf("a reload = %+v (%v), want the same link %+v", again, err, minted)
	}
	if got := unspentMachineLinks(t, s); got != 1 {
		t.Fatalf("unspent machine links = %d, want 1: a reload minted another", got)
	}

	// The link is used: a device exists, and the page has nothing to show.
	if _, err := pairID(ctx, s, minted.Token, "dev-a", "test", 140); err != nil {
		t.Fatalf("pair: %v", err)
	}
	if page, err := s.PageMachineLink(ctx, 150); err != nil || page.Found || page.Devices != 1 {
		t.Fatalf("with a device paired the page = %+v (%v), want nothing until Add a device", page, err)
	}
	if got := unspentMachineLinks(t, s); got != 0 {
		t.Fatalf("the page minted a link while a device can reach the machine")
	}

	// A link asked for is shown, live and then run out, with devices present.
	asked := issueLink(t, s, 200)
	if page, err := s.PageMachineLink(ctx, 210); err != nil || !page.Found || page.Link.Token != asked {
		t.Fatalf("the page = %+v (%v), want the link just asked for", page, err)
	}
	late := 200 + TokenTTLSeconds
	if page, err := s.PageMachineLink(ctx, late); err != nil || !page.Found || page.Link.Token != asked || page.Link.Live(late) {
		t.Fatalf("after the deadline the page = %+v (%v), want the same link, run out", page, err)
	}
}

// FR-002: a link that ran out is not replaced behind anybody's back. The page
// keeps showing it as expired until a new one is asked for - a reload must not
// mint, or an open page would hold a live link for ever.
func TestALinkThatRanOutStaysUntilANewOneIsAskedFor(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	first, err := s.PageMachineLink(ctx, 100)
	if err != nil {
		t.Fatalf("PageMachineLink: %v", err)
	}
	late := first.Link.ExpiresAt + 3600
	for range 3 {
		page, err := s.PageMachineLink(ctx, late)
		if err != nil || !page.Found || page.Link != first.Link || page.Link.Live(late) {
			t.Fatalf("a reload after the deadline = %+v (%v), want the same link, run out", page, err)
		}
	}
	if _, err := pairID(ctx, s, first.Link.Token, "dev-a", "test", late); !errors.Is(err, ErrTokenExpired) {
		t.Fatalf("the run-out link answered %v, want ErrTokenExpired", err)
	}
	fresh := issueLink(t, s, late)
	if page, err := s.PageMachineLink(ctx, late+1); err != nil || !page.Found || page.Link.Token != fresh || !page.Link.Live(late+1) {
		t.Fatalf("after New link the page = %+v (%v), want the new live link", page, err)
	}
}

// FR-015: the last device going away puts the machine back to "no devices",
// where the page shows a link at once. A link that ran out unused would stand
// in the way - the page shows an unspent one as expired - so it is voided; a
// LIVE one is the link somebody may be scanning right now, and stays.
func TestTheLastDeviceGoingAwayClearsTheWayForALink(t *testing.T) {
	ctx := context.Background()

	t.Run("a link that ran out unused is voided", func(t *testing.T) {
		s := newStore(t)
		pairFirst(t, s, "dev-a")
		stale := issueLink(t, s, 200) // Add a device, never used
		gone := 200 + TokenTTLSeconds + 60
		if _, err := s.RevokeDevice(ctx, "dev-a", gone); err != nil {
			t.Fatalf("RevokeDevice: %v", err)
		}
		page, err := s.PageMachineLink(ctx, gone+1)
		if err != nil || !page.Found || page.Link.Token == stale || !page.Link.Live(gone+1) {
			t.Fatalf("the page after the last device left = %+v (%v), want a fresh live link", page, err)
		}
	})

	t.Run("a live link is kept", func(t *testing.T) {
		s := newStore(t)
		pairFirst(t, s, "dev-a")
		live := issueLink(t, s, 200)
		if _, err := s.RevokeDevice(ctx, "dev-a", 260); err != nil {
			t.Fatalf("RevokeDevice: %v", err)
		}
		page, err := s.PageMachineLink(ctx, 261)
		if err != nil || !page.Found || page.Link.Token != live {
			t.Fatalf("the page = %+v (%v), want the live link that was already there", page, err)
		}
	})

	t.Run("a device that is not the last changes nothing", func(t *testing.T) {
		s := newStore(t)
		pairFirst(t, s, "dev-a")
		if _, err := pairID(ctx, s, issueLink(t, s, 150), "dev-b", "test", 150); err != nil {
			t.Fatalf("second device: %v", err)
		}
		stale := issueLink(t, s, 200)
		gone := 200 + TokenTTLSeconds + 60
		if _, err := s.RevokeDevice(ctx, "dev-a", gone); err != nil {
			t.Fatalf("RevokeDevice: %v", err)
		}
		page, err := s.PageMachineLink(ctx, gone+1)
		if err != nil || !page.Found || page.Link.Token != stale {
			t.Fatalf("the page = %+v (%v), want the run-out link still showing as expired", page, err)
		}
	})
}

// The schema keeps the two kinds apart: a machine link has no issuer and no
// person, an invite has both, and neither may lack a deadline.
func TestTheSchemaKeepsTheTwoKindsOfTokenApart(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	pairFirst(t, s, "dev-a")
	var userID string
	if err := s.read.QueryRowContext(ctx, "SELECT user_id FROM users").Scan(&userID); err != nil {
		t.Fatalf("read the person: %v", err)
	}
	for _, tc := range []struct {
		name string
		sql  string
		args []any
	}{
		{"a machine link with an issuer", "INSERT INTO pair_tokens (token, kind, issuer_key, created_at, expires_at) VALUES ('t1', 'machine', 'dev-a', 1, 2)", nil},
		{"a machine link for a person", "INSERT INTO pair_tokens (token, kind, user_id, created_at, expires_at) VALUES ('t2', 'machine', ?, 1, 2)", []any{userID}},
		{"an invite without an issuer", "INSERT INTO pair_tokens (token, kind, user_id, created_at, expires_at) VALUES ('t3', 'invite_device', ?, 1, 2)", []any{userID}},
		{"a token without a deadline", "INSERT INTO pair_tokens (token, kind, created_at) VALUES ('t4', 'machine', 1)", nil},
		{"the claim of old", "INSERT INTO pair_tokens (token, kind, created_at, expires_at) VALUES ('t5', 'claim', 1, 2)", nil},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := s.write.ExecContext(ctx, tc.sql, tc.args...); err == nil {
				t.Fatal("the schema accepted it")
			}
		})
	}
}

// No owner survives anywhere in the schema (FR-017): the machine holds one
// person, and the marker that once named them is gone with its state machine.
func TestTheSchemaNamesNoOwner(t *testing.T) {
	s := newStore(t)
	var columns int
	if err := s.read.QueryRowContext(context.Background(),
		"SELECT COUNT(1) FROM pragma_table_info('server_identity') WHERE name IN ('owner_user_id', 'claimed_at')").Scan(&columns); err != nil {
		t.Fatalf("inspect server_identity: %v", err)
	}
	if columns != 0 {
		t.Fatal("server_identity still carries the ownership marker")
	}
}
