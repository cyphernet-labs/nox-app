package protocol

// Error codes of contract §2.1.
const (
	ErrInvalidRequest    = "invalid_request"
	ErrNotFound          = "not_found"
	ErrNameTaken         = "name_taken"
	ErrPayloadTooLarge   = "payload_too_large"
	ErrAttachmentGone    = "attachment_gone"
	ErrInternal          = "internal"
	ErrUnsupportedSchema = "unsupported_schema"

	// Pairing (§8A). invalid_token covers "no such token", "already spent" and
	// "claim on a server that already has an owner" - one answer on purpose,
	// because telling them apart would say whether a guessed token exists.
	// token_expired is separated from it because the person's next action
	// differs, and unauthenticated means the connection itself is not
	// recognised: the key is not in the allowed list, or the signature did not
	// verify. A device treats it exactly as a revocation.
	ErrInvalidToken    = "invalid_token"
	ErrTokenExpired    = "token_expired"
	ErrUnauthenticated = "unauthenticated"

	// Person invites (§8B). Three codes rather than one because each leads a
	// person to a different action: not_owner means "this is not about the
	// link and not about the network, and repeating will not help",
	// pair_declined means "do not insist", pair_timeout means "ask again".
	// One shared refusal would force the app to invent wording it does not
	// know.
	ErrNotOwner     = "not_owner"
	ErrPairDeclined = "pair_declined"
	ErrPairTimeout  = "pair_timeout"
)
