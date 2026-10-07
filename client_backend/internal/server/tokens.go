package server

import (
	"crypto/rand"
	"encoding/base64"
	"sync"
	"time"
)

// tokenTTL is the lifetime of one-shot upload/download tokens (owner
// decision, 024 clarifications). A client whose transfer outlives the token
// simply requests a new one with the same command.
const tokenTTL = 10 * time.Minute

// tokenOp separates upload tokens from download tokens: a token is valid for
// exactly the operation it was issued for.
type tokenOp string

const (
	opUpload   tokenOp = "upload"
	opDownload tokenOp = "download"
)

type tokenEntry struct {
	fileID string
	op     tokenOp
	// offset is where the bytes an upload token admits begin (043): the
	// continuation that issued it told the client how much the server holds,
	// and the PUT carries the rest from there. Download tokens carry 0.
	offset  int64
	expires time.Time
}

// tokenStore holds the process's one-shot transfer tokens. Ephemeral by
// design: a restart invalidates them and clients re-request. The mutex is
// infrastructure-only synchronization (same class as the connection
// registry, ws-rest-patterns §5) - no business state lives here.
type tokenStore struct {
	mu     sync.Mutex
	tokens map[string]tokenEntry
	now    func() time.Time
}

func newTokenStore() *tokenStore {
	return &tokenStore{tokens: make(map[string]tokenEntry), now: time.Now}
}

// issue mints an unpredictable one-shot token for the file and operation,
// remembering the offset an upload starts at.
//
// An upload token revokes the upload tokens issued for the same file before
// it (043). The client asks again only once it has given up on the previous
// attempt, and a PUT on the older token that turns up late - held up through
// Tor, say - would cut the part back to its older offset, past bytes the
// newer attempt has written since.
func (t *tokenStore) issue(fileID string, op tokenOp, offset int64) string {
	var buf [32]byte
	if _, err := rand.Read(buf[:]); err != nil {
		// The platform RNG failing is fatal-grade; mirrors store.randomID.
		panic("crypto/rand: " + err.Error())
	}
	token := base64.RawURLEncoding.EncodeToString(buf[:])

	t.mu.Lock()
	defer t.mu.Unlock()
	// Lazy expiry sweep keeps the map bounded without a background timer.
	now := t.now()
	for k, e := range t.tokens {
		superseded := op == opUpload && e.op == opUpload && e.fileID == fileID
		if superseded || now.After(e.expires) {
			delete(t.tokens, k)
		}
	}
	t.tokens[token] = tokenEntry{fileID: fileID, op: op, offset: offset, expires: now.Add(tokenTTL)}
	return token
}

// consume redeems a token for the given operation and returns the file and
// the offset it was issued for. The first call removes it regardless of the
// transfer's outcome - after a failure the client requests a fresh token.
//
// The lifetime is checked HERE, at the start of the request, and nowhere
// else: a transfer that began in time runs as long as its bytes keep moving.
func (t *tokenStore) consume(token string, op tokenOp) (fileID string, offset int64, ok bool) {
	t.mu.Lock()
	defer t.mu.Unlock()
	e, found := t.tokens[token]
	if !found {
		return "", 0, false
	}
	delete(t.tokens, token)
	if e.op != op || t.now().After(e.expires) {
		return "", 0, false
	}
	return e.fileID, e.offset, true
}
