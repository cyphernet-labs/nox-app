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
)
