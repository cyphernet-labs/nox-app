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
	fileID  string
	op      tokenOp
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

// issue mints an unpredictable one-shot token for the file and operation.
func (t *tokenStore) issue(fileID string, op tokenOp) string {
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
		if now.After(e.expires) {
			delete(t.tokens, k)
		}
	}
	t.tokens[token] = tokenEntry{fileID: fileID, op: op, expires: now.Add(tokenTTL)}
	return token
}

// consume redeems a token for the given operation. The first call removes
// it regardless of the transfer's outcome - after a failure the client
// requests a fresh token.
func (t *tokenStore) consume(token string, op tokenOp) (string, bool) {
	t.mu.Lock()
	defer t.mu.Unlock()
	e, ok := t.tokens[token]
	if !ok {
		return "", false
	}
	delete(t.tokens, token)
	if e.op != op || t.now().After(e.expires) {
		return "", false
	}
	return e.fileID, true
}
