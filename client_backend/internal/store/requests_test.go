package store

import (
	"context"
	"errors"
	"regexp"
	"testing"
	"testing/synctest"
)

// Requests to join through an invite (046). The property everything here
// serves is SC-002: no device comes into being from an invite without Allow on
// the device that issued it.

// withIssuer pairs dev-issuer through the machine link and has it issue an
// invite at now. It returns the person and the invite's token.
func withIssuer(t *testing.T, s *Store, now int64) (Identity, string) {
	t.Helper()
	person := pairFirst(t, s, "dev-issuer")
	token, err := s.IssueDeviceInvite(context.Background(), "dev-issuer", now)
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	return person, token
}

// openRequest presents token as deviceKey and returns the request it opened.
func openRequest(t *testing.T, s *Store, token, deviceKey string, now int64) PairRequest {
	t.Helper()
	res, err := s.Pair(context.Background(), token, deviceKey, "windows", now)
	if err != nil {
		t.Fatalf("Pair with an invite: %v", err)
	}
	if res.Paired || res.Request == nil {
		t.Fatalf("an invite answered %+v, want a request and no pairing", res)
	}
	return *res.Request
}

// isPaired reports whether a device row exists for the key.
func isPaired(t *testing.T, s *Store, deviceKey string) bool {
	t.Helper()
	_, found, err := s.DeviceOwner(context.Background(), deviceKey)
	if err != nil {
		t.Fatalf("DeviceOwner: %v", err)
	}
	return found
}

// tokenSpent reports whether the token can no longer be presented afresh.
func tokenSpent(t *testing.T, s *Store, token string) bool {
	t.Helper()
	var used int
	if err := s.read.QueryRowContext(context.Background(),
		"SELECT used_at IS NOT NULL FROM pair_tokens WHERE token = ?", token).Scan(&used); err != nil {
		t.Fatalf("read the token: %v", err)
	}
	return used == 1
}

// An invite pairs nothing by itself: it opens a request, addressed to the
// device that issued it, carrying the new device's OS family and the invite's
// own deadline - and the token is not spent while the request waits.
func TestAnInviteOpensARequestAndPairsNothing(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	_, token := withIssuer(t, s, 200)

	res, err := s.Pair(ctx, token, "dev-new", "windows", 210)
	if err != nil {
		t.Fatalf("Pair: %v", err)
	}
	if res.Paired || !res.Opened || res.Closed || res.Request == nil {
		t.Fatalf("result = %+v, want a request opened and nothing paired", res)
	}
	r := *res.Request
	if !regexp.MustCompile(`^r_[0-9a-f]{16}$`).MatchString(r.RequestID) {
		t.Fatalf("request id %q, want r_ and 16 hex digits", r.RequestID)
	}
	if r.IssuerKey != "dev-issuer" || r.DeviceKey != "dev-new" || r.Platform != "windows" || r.Outcome != "" {
		t.Fatalf("request = %+v", r)
	}
	if r.ExpiresAt != 200+TokenTTLSeconds {
		t.Fatalf("expires_at = %d, want the invite's own deadline %d", r.ExpiresAt, 200+TokenTTLSeconds)
	}
	if isPaired(t, s, "dev-new") {
		t.Fatal("SC-002: the new device was paired without Allow")
	}
	if tokenSpent(t, s, token) {
		t.Fatal("the invite was spent while its request still waits")
	}
}

// FR-011: the device that opened the request gets the same one back on every
// presentation inside the ten minutes - after a dropped connection, after a
// restart - and the issuer is not asked twice.
func TestARepeatFromTheSameKeyFindsTheSameRequest(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	_, token := withIssuer(t, s, 200)
	first := openRequest(t, s, token, "dev-new", 210)

	res, err := s.Pair(ctx, token, "dev-new", "linux", 400)
	if err != nil {
		t.Fatalf("repeat: %v", err)
	}
	if res.Opened || res.Paired || res.Request == nil || res.Request.RequestID != first.RequestID {
		t.Fatalf("repeat = %+v, want the request %s back, not a new one", res, first.RequestID)
	}
	if res.Request.Platform != "windows" {
		t.Fatalf("platform = %q: a repeat does not rewrite what the issuer was shown", res.Request.Platform)
	}
}

// An invite has ONE request. A second device presenting the same QR code is
// told the link was used, and the request it would have taken over is left
// exactly as it was.
func TestASecondKeyIsRefusedAndChangesNothing(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	_, token := withIssuer(t, s, 200)
	first := openRequest(t, s, token, "dev-new", 210)

	if _, err := s.Pair(ctx, token, "dev-other", "ios", 220); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("a second key = %v, want ErrTokenInvalid", err)
	}
	waiting, err := s.WaitingPairRequests(ctx, "dev-issuer", 230)
	if err != nil || len(waiting) != 1 || waiting[0].DeviceKey != "dev-new" || waiting[0].RequestID != first.RequestID {
		t.Fatalf("waiting = %+v (%v), want the first device's request untouched", waiting, err)
	}
}

// FR-009: Allow writes the device, spends the token and closes the request in
// one transaction, and the device joins the person with no naming step. A
// repeat of `pair` after it answers with that identity, like a machine link.
func TestAllowPairsTheDeviceAndARepeatAnswersWithTheIdentity(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	person, token := withIssuer(t, s, 200)
	r := openRequest(t, s, token, "dev-new", 210)

	dec, err := s.DecidePairRequest(ctx, r.RequestID, "dev-issuer", true, 220)
	if err != nil {
		t.Fatalf("Allow: %v", err)
	}
	if dec.Request.Outcome != OutcomeAllowed || dec.Identity.UserID != person.UserID || dec.Identity.Created {
		t.Fatalf("decision = %+v, want allowed into %q with created=false", dec, person.UserID)
	}
	owner, found, err := s.DeviceOwner(ctx, "dev-new")
	if err != nil || !found || owner != person.UserID {
		t.Fatalf("the allowed device belongs to %q (found=%v, %v), want %q", owner, found, err, person.UserID)
	}
	if !tokenSpent(t, s, token) {
		t.Fatal("Allow left the invite usable")
	}
	devices, err := s.ListDevices(ctx, person.UserID)
	if err != nil || len(devices) != 2 || devices[1].Platform != "windows" {
		t.Fatalf("devices = %+v (%v), want the new one with the platform it reported", devices, err)
	}

	res, err := s.Pair(ctx, token, "dev-new", "windows", 230)
	if err != nil {
		t.Fatalf("repeat after Allow: %v", err)
	}
	if !res.Paired || res.Identity.UserID != person.UserID || res.Identity.Created || res.Request == nil || res.Request.Outcome != OutcomeAllowed {
		t.Fatalf("repeat after Allow = %+v, want the identity and the allowed request", res)
	}
	// And the device greets as the person.
	if id, err := s.ResolveIdentity(ctx, "dev-new", "", 240); err != nil || id.UserID != person.UserID {
		t.Fatalf("the allowed device greets as %+v (%v)", id, err)
	}
}

// FR-009: Deny closes the request and spends the token; nothing is paired, and
// a repeat answers with the outcome so the device can say so.
func TestDenyClosesTheRequestAndPairsNothing(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	_, token := withIssuer(t, s, 200)
	r := openRequest(t, s, token, "dev-new", 210)

	dec, err := s.DecidePairRequest(ctx, r.RequestID, "dev-issuer", false, 220)
	if err != nil {
		t.Fatalf("Deny: %v", err)
	}
	if dec.Request.Outcome != OutcomeDenied || dec.Identity.UserID != "" {
		t.Fatalf("decision = %+v, want denied and nobody", dec)
	}
	if isPaired(t, s, "dev-new") {
		t.Fatal("SC-002: a denied device was paired")
	}
	if !tokenSpent(t, s, token) {
		t.Fatal("Deny left the invite usable")
	}
	res, err := s.Pair(ctx, token, "dev-new", "windows", 230)
	if err != nil || res.Paired || res.Request == nil || res.Request.Outcome != OutcomeDenied || res.Opened {
		t.Fatalf("repeat after Deny = %+v (%v), want the denied request back", res, err)
	}
	if _, err := s.Pair(ctx, token, "dev-other", "ios", 230); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("another key after Deny = %v, want ErrTokenInvalid", err)
	}
}

// Only the device that issued the invite may answer it, only once, and only
// while it waits. Each refusal is the same not-found, and none of them pairs
// anything.
func TestOnlyTheIssuerMayAnswerAndOnlyWhileTheRequestWaits(t *testing.T) {
	ctx := context.Background()
	for _, tc := range []struct {
		name    string
		arrange func(t *testing.T, s *Store, r PairRequest) (requestID, issuer string, now int64)
		want    error
	}{
		{
			name: "a request nobody opened",
			arrange: func(*testing.T, *Store, PairRequest) (string, string, int64) {
				return "r_0000000000000000", "dev-issuer", 220
			},
			want: ErrRequestNotFound,
		},
		{
			name: "another device of the same person",
			arrange: func(t *testing.T, s *Store, r PairRequest) (string, string, int64) {
				if _, err := pairID(ctx, s, issueLink(t, s, 215), "dev-tablet", "test", 215); err != nil {
					t.Fatalf("pair the tablet: %v", err)
				}
				return r.RequestID, "dev-tablet", 220
			},
			want: ErrRequestNotFound,
		},
		{
			name: "a request already answered",
			arrange: func(t *testing.T, s *Store, r PairRequest) (string, string, int64) {
				if _, err := s.DecidePairRequest(ctx, r.RequestID, "dev-issuer", false, 215); err != nil {
					t.Fatalf("first answer: %v", err)
				}
				return r.RequestID, "dev-issuer", 220
			},
			want: ErrRequestNotFound,
		},
		{
			name: "a request whose time ran out a moment ago",
			arrange: func(_ *testing.T, _ *Store, r PairRequest) (string, string, int64) {
				return r.RequestID, "dev-issuer", r.ExpiresAt
			},
			want: ErrRequestNotFound,
		},
		{
			name: "an issuer revoked while its answer was on the way",
			arrange: func(t *testing.T, s *Store, r PairRequest) (string, string, int64) {
				if _, err := s.RevokeDevice(ctx, "dev-issuer", 215); err != nil {
					t.Fatalf("RevokeDevice: %v", err)
				}
				return r.RequestID, "dev-issuer", 220
			},
			want: ErrDeviceUnknown,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s := newStore(t)
			_, token := withIssuer(t, s, 200)
			r := openRequest(t, s, token, "dev-new", 210)
			requestID, issuer, now := tc.arrange(t, s, r)
			if _, err := s.DecidePairRequest(ctx, requestID, issuer, true, now); !errors.Is(err, tc.want) {
				t.Fatalf("Allow = %v, want %v", err, tc.want)
			}
			if isPaired(t, s, "dev-new") {
				t.Fatal("SC-002: a refused Allow paired the device")
			}
		})
	}
}

// FR-007: the server closes a request whose time ran out without anybody
// acting, spends its token, and leaves the ones still inside their time alone.
func TestTheSweepClosesWhatRanOutAndNothingElse(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	pairFirst(t, s, "dev-issuer")
	early, err := s.IssueDeviceInvite(ctx, "dev-issuer", 200)
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	late, err := s.IssueDeviceInvite(ctx, "dev-issuer", 400)
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	gone := openRequest(t, s, early, "dev-a", 210)
	stays := openRequest(t, s, late, "dev-b", 410)

	if closed, err := s.ExpirePairRequests(ctx, gone.ExpiresAt-1); err != nil || len(closed) != 0 {
		t.Fatalf("a sweep before the deadline closed %+v (%v)", closed, err)
	}
	closed, err := s.ExpirePairRequests(ctx, gone.ExpiresAt)
	if err != nil {
		t.Fatalf("ExpirePairRequests: %v", err)
	}
	if len(closed) != 1 || closed[0].RequestID != gone.RequestID || closed[0].Outcome != OutcomeExpired || closed[0].DeviceKey != "dev-a" {
		t.Fatalf("closed = %+v, want exactly the request that ran out, as expired", closed)
	}
	if !tokenSpent(t, s, early) || tokenSpent(t, s, late) {
		t.Fatal("the sweep spent the wrong token")
	}
	waiting, err := s.WaitingPairRequests(ctx, "dev-issuer", gone.ExpiresAt)
	if err != nil || len(waiting) != 1 || waiting[0].RequestID != stays.RequestID {
		t.Fatalf("waiting = %+v (%v), want the request still inside its time", waiting, err)
	}
	if again, err := s.ExpirePairRequests(ctx, gone.ExpiresAt+5); err != nil || len(again) != 0 {
		t.Fatalf("a second sweep closed %+v (%v): a closed request never closes again", again, err)
	}

	res, err := s.Pair(ctx, early, "dev-a", "windows", gone.ExpiresAt+10)
	if err != nil || res.Request == nil || res.Request.Outcome != OutcomeExpired || res.Paired {
		t.Fatalf("repeat after expiry = %+v (%v), want the expired request back", res, err)
	}
	if isPaired(t, s, "dev-a") {
		t.Fatal("SC-002: an expired request paired the device")
	}
}

// A repeat that arrives after the deadline but before the sweep closes the
// request itself, and says so - the answer is the truth, not a "still waiting"
// nobody can end.
func TestARepeatAfterTheDeadlineClosesTheRequestAsExpired(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	_, token := withIssuer(t, s, 200)
	r := openRequest(t, s, token, "dev-new", 210)

	res, err := s.Pair(ctx, token, "dev-new", "windows", r.ExpiresAt)
	if err != nil {
		t.Fatalf("repeat at the deadline: %v", err)
	}
	if !res.Closed || res.Request == nil || res.Request.Outcome != OutcomeExpired {
		t.Fatalf("repeat at the deadline = %+v, want the request closed here, as expired", res)
	}
	if !tokenSpent(t, s, token) {
		t.Fatal("the invite outlived its request")
	}
	if closed, err := s.ExpirePairRequests(ctx, r.ExpiresAt+1); err != nil || len(closed) != 0 {
		t.Fatalf("the sweep closed %+v again (%v)", closed, err)
	}
}

// An invite nobody presented in time is refused as expired - the same answer as
// a machine link that ran out, which is what the new device shows (FR-010).
func TestAnInviteNobodyPresentedInTimeIsRefusedAsExpired(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	_, token := withIssuer(t, s, 200)
	if _, err := s.Pair(ctx, token, "dev-new", "windows", 200+TokenTTLSeconds); !errors.Is(err, ErrTokenExpired) {
		t.Fatalf("a late invite = %v, want ErrTokenExpired", err)
	}
	if waiting, err := s.WaitingPairRequests(ctx, "dev-issuer", 0); err != nil || len(waiting) != 0 {
		t.Fatalf("a late invite opened %+v (%v)", waiting, err)
	}
}

// FR-010: Cancel withdraws the request of the key that opened it, spends the
// token, and is idempotent: nothing waiting for this key is not an error.
func TestCancelClosesOnlyTheRequestOfTheKeyThatOpenedIt(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	_, token := withIssuer(t, s, 200)
	r := openRequest(t, s, token, "dev-new", 210)

	if _, found, err := s.CancelPairRequest(ctx, token, "dev-other", 215); err != nil || found {
		t.Fatalf("another key's cancel found=%v (%v), want nothing", found, err)
	}
	cancelled, found, err := s.CancelPairRequest(ctx, token, "dev-new", 220)
	if err != nil || !found || cancelled.RequestID != r.RequestID || cancelled.Outcome != OutcomeCancelled {
		t.Fatalf("cancel = %+v found=%v (%v), want the request cancelled", cancelled, found, err)
	}
	if !tokenSpent(t, s, token) {
		t.Fatal("Cancel left the invite usable")
	}
	if _, found, err := s.CancelPairRequest(ctx, token, "dev-new", 230); err != nil || found {
		t.Fatalf("a second cancel found=%v (%v), want nothing to do", found, err)
	}
	if _, found, err := s.CancelPairRequest(ctx, "no-such-token", "dev-new", 230); err != nil || found {
		t.Fatalf("a cancel of nothing found=%v (%v)", found, err)
	}
	// Allow pressed after the cancel does nothing.
	if _, err := s.DecidePairRequest(ctx, r.RequestID, "dev-issuer", true, 240); !errors.Is(err, ErrRequestNotFound) {
		t.Fatalf("Allow after Cancel = %v, want ErrRequestNotFound", err)
	}
	if isPaired(t, s, "dev-new") {
		t.Fatal("SC-002: a cancelled request paired the device")
	}
	res, err := s.Pair(ctx, token, "dev-new", "windows", 250)
	if err != nil || res.Request == nil || res.Request.Outcome != OutcomeCancelled {
		t.Fatalf("repeat after Cancel = %+v (%v), want the cancelled request back", res, err)
	}

	// A cancel that arrives after the deadline says what happened instead.
	_, late := withIssuerAgain(t, s, 300)
	lr := openRequest(t, s, late, "dev-late", 310)
	got, found, err := s.CancelPairRequest(ctx, late, "dev-late", lr.ExpiresAt)
	if err != nil || !found || got.Outcome != OutcomeExpired {
		t.Fatalf("a cancel after the deadline = %+v found=%v (%v), want it closed as expired", got, found, err)
	}
}

// withIssuerAgain issues another invite from the issuer withIssuer paired.
func withIssuerAgain(t *testing.T, s *Store, now int64) (string, string) {
	t.Helper()
	token, err := s.IssueDeviceInvite(context.Background(), "dev-issuer", now)
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	return "dev-issuer", token
}

// A revoked issuer can answer nothing: its waiting requests close as denied,
// and the revocation hands them back so the devices waiting on them are told.
// Its unspent invites die with it.
func TestRevokingTheIssuerDeniesWhatWaitsForIt(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	_, token := withIssuer(t, s, 200)
	r := openRequest(t, s, token, "dev-new", 210)
	_, unpresented := withIssuerAgain(t, s, 220)

	rev, err := s.RevokeDevice(ctx, "dev-issuer", 230)
	if err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}
	if len(rev.Closed) != 1 || rev.Closed[0].RequestID != r.RequestID || rev.Closed[0].Outcome != OutcomeDenied {
		t.Fatalf("closed = %+v, want the waiting request, denied", rev.Closed)
	}
	if isPaired(t, s, "dev-new") {
		t.Fatal("SC-002: revoking the issuer paired the device")
	}
	res, err := s.Pair(ctx, token, "dev-new", "windows", 240)
	if err != nil || res.Request == nil || res.Request.Outcome != OutcomeDenied {
		t.Fatalf("repeat after the issuer was revoked = %+v (%v), want denied", res, err)
	}
	if _, err := s.Pair(ctx, unpresented, "dev-other", "ios", 240); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("the revoked device's unpresented invite = %v, want ErrTokenInvalid", err)
	}
}

// A device the person revokes does not come back through an Allow pressed on a
// request it had opened before: the request closes with the revocation, and
// the issuer is told it no longer waits.
func TestRevokingTheRequestingDeviceClosesItsRequest(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	_, token := withIssuer(t, s, 200)
	// The laptop is paired already and presents an invite as well - a re-pair of
	// its own key.
	if _, err := pairID(ctx, s, issueLink(t, s, 205), "dev-laptop", "macos", 205); err != nil {
		t.Fatalf("pair the laptop: %v", err)
	}
	r := openRequest(t, s, token, "dev-laptop", 210)

	rev, err := s.RevokeDevice(ctx, "dev-laptop", 220)
	if err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}
	if len(rev.Closed) != 1 || rev.Closed[0].RequestID != r.RequestID || rev.Closed[0].IssuerKey != "dev-issuer" {
		t.Fatalf("closed = %+v, want the laptop's own request", rev.Closed)
	}
	if _, err := s.DecidePairRequest(ctx, r.RequestID, "dev-issuer", true, 230); !errors.Is(err, ErrRequestNotFound) {
		t.Fatalf("Allow after the revocation = %v, want ErrRequestNotFound", err)
	}
	if isPaired(t, s, "dev-laptop") {
		t.Fatal("the revoked device came back")
	}
}

// What a greeting re-sends: the issuer's own requests, still waiting, still
// inside their time - nobody else's, nothing closed, nothing run out.
func TestWaitingRequestsAreTheIssuersOwnAndStillLive(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	_, token := withIssuer(t, s, 200)
	mine := openRequest(t, s, token, "dev-a", 210)
	if _, err := pairID(ctx, s, issueLink(t, s, 215), "dev-tablet", "test", 215); err != nil {
		t.Fatalf("pair the tablet: %v", err)
	}
	tabletInvite, err := s.IssueDeviceInvite(ctx, "dev-tablet", 220)
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	openRequest(t, s, tabletInvite, "dev-b", 225)
	_, answered := withIssuerAgain(t, s, 230)
	closed := openRequest(t, s, answered, "dev-c", 235)
	if _, err := s.DecidePairRequest(ctx, closed.RequestID, "dev-issuer", false, 240); err != nil {
		t.Fatalf("Deny: %v", err)
	}

	waiting, err := s.WaitingPairRequests(ctx, "dev-issuer", 250)
	if err != nil || len(waiting) != 1 || waiting[0].RequestID != mine.RequestID {
		t.Fatalf("waiting = %+v (%v), want only the issuer's own live request", waiting, err)
	}
	if waiting, err := s.WaitingPairRequests(ctx, "dev-issuer", mine.ExpiresAt); err != nil || len(waiting) != 0 {
		t.Fatalf("waiting at the deadline = %+v (%v), want nothing", waiting, err)
	}
}

// The race the UNIQUE token and the single writer settle: two devices present
// one invite at the same moment, and exactly one request comes into being.
func TestOneInviteOpensExactlyOneRequest(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		s := newStore(t)
		ctx := context.Background()
		_, token := withIssuer(t, s, 200)

		results := make(chan error, 2)
		for i, key := range []string{"dev-x", "dev-y"} {
			go func() {
				_, err := s.Pair(ctx, token, key, "test", 210+int64(i))
				results <- err
			}()
		}
		opened := 0
		for range 2 {
			switch err := <-results; {
			case err == nil:
				opened++
			case errors.Is(err, ErrTokenInvalid):
			default:
				t.Fatalf("unexpected error: %v", err)
			}
		}
		if opened != 1 {
			t.Fatalf("%d of 2 simultaneous presentations opened a request, want exactly 1", opened)
		}
		waiting, err := s.WaitingPairRequests(ctx, "dev-issuer", 220)
		if err != nil || len(waiting) != 1 {
			t.Fatalf("waiting = %+v (%v), want one request", waiting, err)
		}
	})
}

// A device revoked from another one may still have an invite command on the
// way; the store issues nothing for a device that is gone.
func TestARevokedDeviceCannotIssueAnInvite(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	pairFirst(t, s, "dev-issuer")
	if _, err := s.RevokeDevice(ctx, "dev-issuer", 150); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}
	if _, err := s.IssueDeviceInvite(ctx, "dev-issuer", 200); !errors.Is(err, ErrDeviceUnknown) {
		t.Fatalf("IssueDeviceInvite = %v, want ErrDeviceUnknown", err)
	}
}

// The schema holds a request to the outcomes it can have, and a closed one to
// the moment it was closed.
func TestTheSchemaKeepsARequestHonest(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	_, token := withIssuer(t, s, 200)
	r := openRequest(t, s, token, "dev-new", 210)
	for _, stmt := range []string{
		"UPDATE pair_requests SET outcome = 'maybe', decided_at = 1 WHERE request_id = ?",
		"UPDATE pair_requests SET outcome = 'allowed' WHERE request_id = ?",
		"UPDATE pair_requests SET decided_at = 5 WHERE request_id = ?",
	} {
		if _, err := s.write.ExecContext(ctx, stmt, r.RequestID); err == nil {
			t.Fatalf("the schema accepted %q", stmt)
		}
	}
	if _, err := s.write.ExecContext(ctx,
		"INSERT INTO pair_requests (request_id, token, device_key, platform, issuer_key, expires_at) VALUES ('r_2', ?, 'dev-b', 'ios', 'dev-issuer', 999)",
		token); err == nil {
		t.Fatal("a second request for one invite was written")
	}
}
