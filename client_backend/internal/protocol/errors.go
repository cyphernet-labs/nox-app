package protocol

// Error codes of the stage-1 slice (contract §2.1). Stage-2 codes
// (invalid_token, token_expired) arrive with pairing, not before.
const (
	ErrInvalidRequest    = "invalid_request"
	ErrNotFound          = "not_found"
	ErrNameTaken         = "name_taken"
	ErrPayloadTooLarge   = "payload_too_large"
	ErrAttachmentGone    = "attachment_gone"
	ErrInternal          = "internal"
	ErrUnsupportedSchema = "unsupported_schema"
)
