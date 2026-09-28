package tor

import "time"

// Phase is where the supervisor stands with the tor process.
type Phase string

const (
	PhaseDisabled      Phase = "disabled"
	PhaseBinaryMissing Phase = "binary-missing"
	PhaseBinaryTooOld  Phase = "binary-too-old"
	PhaseStarting      Phase = "starting"
	PhaseConnecting    Phase = "connecting"
	PhaseRunning       Phase = "running"
	PhaseWaitingRetry  Phase = "waiting-retry"
)

// Verdict is the network's own judgement of the running tor's version, from
// GETINFO status/version/current - never computed here from the number.
type Verdict string

const (
	VerdictUnknown     Verdict = "unknown"
	VerdictRecommended Verdict = "recommended"
	VerdictOutdated    Verdict = "outdated"
	VerdictObsolete    Verdict = "obsolete"
)

// Publication is where the onion service stands.
type Publication string

const (
	PublicationNoKeys     Publication = "not-published-no-keys"
	PublicationTorDown    Publication = "not-published-tor-down"
	PublicationPublishing Publication = "publishing"
	PublicationPublished  Publication = "published"
)

// Status is an immutable snapshot of the supervisor, published through an
// atomic pointer: readers - the status page, the address watcher - never wait
// for a supervisor that may be standing in a control-port timeout.
//
// Nothing in it may carry the onion address or a key. LastError has been
// through Scrub before it lands here.
type Status struct {
	Enabled     bool
	Phase       Phase
	Version     string
	Verdict     Verdict
	Bootstrap   int
	Publication Publication
	LastError   string
	// RetryIn is the pause before the next start while Phase is
	// waiting-retry.
	RetryIn time.Duration
}

// verdictOf maps tor's word for its own version to the page's four.
func verdictOf(current string) Verdict {
	switch current {
	case "recommended", "new", "new in series":
		return VerdictRecommended
	case "old", "unrecommended":
		return VerdictOutdated
	case "obsolete":
		return VerdictObsolete
	}
	return VerdictUnknown
}
