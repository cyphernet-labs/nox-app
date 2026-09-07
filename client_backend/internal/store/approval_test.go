package store

import (
	"context"
	"errors"
	"path/filepath"
	"testing"

	"nox.app/client-backend/internal/db"
)

// claimOwner claims a fresh server and returns the owner's identity.
func claimOwner(t *testing.T, s *Store, deviceKey string) Identity {
	t.Helper()
	ctx := context.Background()
	if _, err := s.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	token, err := s.IssueClaimToken(ctx, 100)
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	id, err := pairID(ctx, s, token, deviceKey, "test", 100)
	if err != nil {
		t.Fatalf("claim: %v", err)
	}
	return id
}

// present offers a person invite and returns the pending result.
func present(t *testing.T, s *Store, token, deviceKey string, now int64) PairResult {
	t.Helper()
	res, err := s.Pair(context.Background(), token, deviceKey, "ios", now)
	if err != nil {
		t.Fatalf("Pair: %v", err)
	}
	if !res.Pending || res.RequestID == "" {
		t.Fatalf("Pair = %+v, want a pending request", res)
	}
	return res
}

func TestApprovedPersonInviteCreatesANewPersonWhoOwnsNothing(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	owner := claimOwner(t, s, "dev-owner")

	token, err := s.IssuePersonInvite(ctx, owner.UserID, 200)
	if err != nil {
		t.Fatalf("IssuePersonInvite: %v", err)
	}
	req := present(t, s, token, "dev-guest", 300)
	if req.ExpiresAt != 300+ApprovalWindowSeconds {
		t.Fatalf("ExpiresAt = %d, want %d", req.ExpiresAt, 300+ApprovalWindowSeconds)
	}
	// Nobody is in yet: a presented invite is a question, not an entry.
	people, err := s.ListPeople(ctx)
	if err != nil {
		t.Fatalf("ListPeople: %v", err)
	}
	if len(people) != 1 {
		t.Fatalf("people before the answer = %d, want 1", len(people))
	}

	out, err := s.ConfirmPair(ctx, req.RequestID, owner.UserID, true, 320)
	if err != nil {
		t.Fatalf("ConfirmPair: %v", err)
	}
	if out.Outcome != OutcomeApproved {
		t.Fatalf("outcome = %q, want %q", out.Outcome, OutcomeApproved)
	}
	if out.Identity.UserID == owner.UserID {
		t.Fatal("the invited person got the owner's identity")
	}
	if !out.Identity.Created {
		t.Fatal("created = false, want true: a person invite always brings somebody into being")
	}
	if out.Identity.Owner {
		t.Fatal("the invited person owns the server")
	}

	// The invitee has their own device and nobody else's.
	devices, err := s.ListDevices(ctx, out.Identity.UserID)
	if err != nil {
		t.Fatalf("ListDevices: %v", err)
	}
	if len(devices) != 1 || devices[0].DeviceKey != "dev-guest" {
		t.Fatalf("devices = %+v, want only dev-guest", devices)
	}

	// And the recorded outcome answers a repeat presentation, which is what
	// makes a dropped reply survivable.
	again, err := s.Pair(ctx, token, "dev-guest", "ios", 400)
	if err != nil {
		t.Fatalf("re-present after approval: %v", err)
	}
	if again.Identity.UserID != out.Identity.UserID || !again.Identity.Created {
		t.Fatalf("replay = %+v, want the recorded person with created=true", again.Identity)
	}
}

func TestAPersonInviteIsRefusedForADeviceThatAlreadyBelongsToSomebody(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	owner := claimOwner(t, s, "dev-owner")

	token, err := s.IssuePersonInvite(ctx, owner.UserID, 200)
	if err != nil {
		t.Fatalf("IssuePersonInvite: %v", err)
	}
	// The owner's own device presenting a person invite. Approving it could
	// never work - a key does not change hands - so the refusal has to happen
	// here rather than after the owner has been woken up and said yes.
	if _, err := s.Pair(ctx, token, "dev-owner", "ios", 300); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("err = %v, want ErrTokenInvalid", err)
	}
	pending, err := s.PendingRequests(ctx, 300)
	if err != nil {
		t.Fatalf("PendingRequests: %v", err)
	}
	if len(pending) != 0 {
		t.Fatalf("pending = %+v, want none: the owner must not be asked a question whose yes does nothing", pending)
	}
}

func TestOnlyTheOwnerMayIssueOrAnswerAPersonInvite(t *testing.T) {
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

	// The person who just joined tries to invite the next one.
	if _, err := s.IssuePersonInvite(ctx, guest.Identity.UserID, 400); !errors.Is(err, ErrNotOwner) {
		t.Fatalf("err = %v, want ErrNotOwner", err)
	}
	// ...and to answer a question that is not theirs.
	second, err := s.IssuePersonInvite(ctx, owner.UserID, 500)
	if err != nil {
		t.Fatalf("IssuePersonInvite: %v", err)
	}
	req2 := present(t, s, second, "dev-third", 600)
	if _, err := s.ConfirmPair(ctx, req2.RequestID, guest.Identity.UserID, true, 610); !errors.Is(err, ErrNotOwner) {
		t.Fatalf("err = %v, want ErrNotOwner", err)
	}
}

func TestADeclinedInviteLetsNobodyInAndStaysDead(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	owner := claimOwner(t, s, "dev-owner")

	token, err := s.IssuePersonInvite(ctx, owner.UserID, 200)
	if err != nil {
		t.Fatalf("IssuePersonInvite: %v", err)
	}
	req := present(t, s, token, "dev-guest", 300)

	out, err := s.ConfirmPair(ctx, req.RequestID, owner.UserID, false, 310)
	if err != nil {
		t.Fatalf("ConfirmPair: %v", err)
	}
	if out.Outcome != OutcomeDeclined {
		t.Fatalf("outcome = %q, want %q", out.Outcome, OutcomeDeclined)
	}
	people, err := s.ListPeople(ctx)
	if err != nil {
		t.Fatalf("ListPeople: %v", err)
	}
	if len(people) != 1 {
		t.Fatalf("people = %d, want 1: a decline creates nobody", len(people))
	}

	// The link is dead, and it says so in a way that means "do not insist"
	// rather than "try again".
	if _, err := s.Pair(ctx, token, "dev-guest", "ios", 320); !errors.Is(err, ErrPairDeclined) {
		t.Fatalf("err = %v, want ErrPairDeclined", err)
	}
	// A second answer cannot overwrite the first: the person on the other side
	// has already been told what it was.
	if _, err := s.ConfirmPair(ctx, req.RequestID, owner.UserID, true, 330); !errors.Is(err, ErrRequestNotFound) {
		t.Fatalf("err = %v, want ErrRequestNotFound", err)
	}
}

func TestAnUnansweredInviteExpiresAndSaysSo(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	owner := claimOwner(t, s, "dev-owner")

	token, err := s.IssuePersonInvite(ctx, owner.UserID, 200)
	if err != nil {
		t.Fatalf("IssuePersonInvite: %v", err)
	}
	req := present(t, s, token, "dev-guest", 300)

	deadline := 300 + ApprovalWindowSeconds
	if got, err := s.ExpirePendingPairs(ctx, deadline-1); err != nil || len(got) != 0 {
		t.Fatalf("ExpirePendingPairs before the deadline = %+v, %v; want nothing swept", got, err)
	}
	expired, err := s.ExpirePendingPairs(ctx, deadline)
	if err != nil {
		t.Fatalf("ExpirePendingPairs: %v", err)
	}
	if len(expired) != 1 || expired[0].RequestID != req.RequestID {
		t.Fatalf("expired = %+v, want the one waiting request", expired)
	}
	if expired[0].AwaitingDevice != "dev-guest" {
		t.Fatalf("AwaitingDevice = %q, want dev-guest", expired[0].AwaitingDevice)
	}
	// "Ask again", not "do not insist".
	if _, err := s.Pair(ctx, token, "dev-guest", "ios", deadline+1); !errors.Is(err, ErrPairTimeout) {
		t.Fatalf("err = %v, want ErrPairTimeout", err)
	}
	// A decision arriving after the deadline is refused rather than applied.
	if _, err := s.ConfirmPair(ctx, req.RequestID, owner.UserID, true, deadline+2); !errors.Is(err, ErrRequestNotFound) {
		t.Fatalf("late confirm err = %v, want ErrRequestNotFound", err)
	}
}

// The deadline is enforced even when nothing swept it: whichever gets there
// first has to give the same answer.
func TestAPastDeadlineIsSettledByThePresentingDeviceToo(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	owner := claimOwner(t, s, "dev-owner")

	token, err := s.IssuePersonInvite(ctx, owner.UserID, 200)
	if err != nil {
		t.Fatalf("IssuePersonInvite: %v", err)
	}
	req := present(t, s, token, "dev-guest", 300)

	if _, err := s.Pair(ctx, token, "dev-guest", "ios", 300+ApprovalWindowSeconds+1); !errors.Is(err, ErrPairTimeout) {
		t.Fatalf("err = %v, want ErrPairTimeout", err)
	}
	if _, err := s.ConfirmPair(ctx, req.RequestID, owner.UserID, true, 300+ApprovalWindowSeconds+2); !errors.Is(err, ErrRequestNotFound) {
		t.Fatalf("the request survived its own expiry: %v", err)
	}
}

// While the answer is outstanding the request belongs to whoever presented it.
// A second device with the same link is not a second question.
func TestAWaitingInviteAnswersOnlyTheDeviceThatPresentedIt(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	owner := claimOwner(t, s, "dev-owner")

	token, err := s.IssuePersonInvite(ctx, owner.UserID, 200)
	if err != nil {
		t.Fatalf("IssuePersonInvite: %v", err)
	}
	req := present(t, s, token, "dev-guest", 300)

	again, err := s.Pair(ctx, token, "dev-guest", "ios", 310)
	if err != nil {
		t.Fatalf("re-present while waiting: %v", err)
	}
	if !again.Pending || again.RequestID != req.RequestID {
		t.Fatalf("re-present = %+v, want the SAME pending request", again)
	}
	if _, err := s.Pair(ctx, token, "dev-other", "android", 320); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("stranger err = %v, want ErrTokenInvalid", err)
	}
	if pending, err := s.PendingRequests(ctx, 320); err != nil || len(pending) != 1 {
		t.Fatalf("pending = %+v, %v; want exactly one question", pending, err)
	}
}

// Every settled outcome refuses a stranger with the same generic answer: a
// burned token must not tell a passer-by even that it once existed.
func TestASettledInviteTellsAStrangerNothing(t *testing.T) {
	for _, tc := range []struct {
		name    string
		approve bool
	}{{"approved", true}, {"declined", false}} {
		t.Run(tc.name, func(t *testing.T) {
			s := newStore(t)
			ctx := context.Background()
			owner := claimOwner(t, s, "dev-owner")

			token, err := s.IssuePersonInvite(ctx, owner.UserID, 200)
			if err != nil {
				t.Fatalf("IssuePersonInvite: %v", err)
			}
			req := present(t, s, token, "dev-guest", 300)
			if _, err := s.ConfirmPair(ctx, req.RequestID, owner.UserID, tc.approve, 310); err != nil {
				t.Fatalf("ConfirmPair: %v", err)
			}
			if _, err := s.Pair(ctx, token, "dev-stranger", "linux", 320); !errors.Is(err, ErrTokenInvalid) {
				t.Fatalf("err = %v, want ErrTokenInvalid", err)
			}
		})
	}
}

// The wait lives in the row, not in the process, which is the whole reason it
// is written there.
func TestAWaitingInviteSurvivesAReopenOfTheStore(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "approval.db")

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
	owner := claimOwner(t, s, "dev-owner")
	token, err := s.IssuePersonInvite(ctx, owner.UserID, 200)
	if err != nil {
		t.Fatalf("IssuePersonInvite: %v", err)
	}
	req := present(t, s, token, "dev-guest", 300)
	closeFirst()

	s2, closeSecond := open()
	defer closeSecond()

	pending, err := s2.PendingRequests(ctx, 310)
	if err != nil {
		t.Fatalf("PendingRequests: %v", err)
	}
	if len(pending) != 1 || pending[0].RequestID != req.RequestID {
		t.Fatalf("pending after reopen = %+v, want the waiting request", pending)
	}
	// Neither approved nor declined by the restart itself.
	out, err := s2.ConfirmPair(ctx, req.RequestID, owner.UserID, true, 320)
	if err != nil {
		t.Fatalf("ConfirmPair after reopen: %v", err)
	}
	if out.Outcome != OutcomeApproved {
		t.Fatalf("outcome = %q, want %q", out.Outcome, OutcomeApproved)
	}
}

// The sweeper's predicate has three conditions, and the third is the one that
// is easy to forget: without it every claim and device token looks like a
// waiting request.
func TestExpiringPendingPairsLeavesOrdinaryTokensAlone(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	owner := claimOwner(t, s, "dev-owner")

	if _, err := s.IssueDeviceInvite(ctx, owner.UserID, 200); err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	if _, err := s.IssuePersonInvite(ctx, owner.UserID, 200); err != nil {
		t.Fatalf("IssuePersonInvite: %v", err)
	}
	// A far future moment: every token above is long past any deadline it has,
	// and none of them is waiting for a human.
	swept, err := s.ExpirePendingPairs(ctx, 10_000_000)
	if err != nil {
		t.Fatalf("ExpirePendingPairs: %v", err)
	}
	if len(swept) != 0 {
		t.Fatalf("swept = %+v, want nothing: none of these waits on a person", swept)
	}
}
