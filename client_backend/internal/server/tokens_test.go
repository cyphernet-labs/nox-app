package server

import (
	"testing"
	"time"
)

func TestTokenSingleUse(t *testing.T) {
	ts := newTokenStore()
	tok := ts.issue("f_1", opUpload, 0)

	fileID, _, ok := ts.consume(tok, opUpload)
	if !ok || fileID != "f_1" {
		t.Fatalf("first consume = %q,%v", fileID, ok)
	}
	if _, _, ok := ts.consume(tok, opUpload); ok {
		t.Fatal("token consumed twice")
	}
}

func TestAnUploadTokenCarriesTheOffsetItWasIssuedFor(t *testing.T) {
	ts := newTokenStore()
	tok := ts.issue("f_1", opUpload, 37748736)

	fileID, offset, ok := ts.consume(tok, opUpload)
	if !ok || fileID != "f_1" || offset != 37748736 {
		t.Fatalf("consume = %q, %d, %v; want f_1 at 37748736", fileID, offset, ok)
	}

	dl := ts.issue("f_1", opDownload, 0)
	if _, offset, ok := ts.consume(dl, opDownload); !ok || offset != 0 {
		t.Fatalf("download token = %d, %v; want offset 0", offset, ok)
	}
}

func TestTokenWrongOpIsRejectedAndBurned(t *testing.T) {
	ts := newTokenStore()
	tok := ts.issue("f_1", opDownload, 0)

	if _, _, ok := ts.consume(tok, opUpload); ok {
		t.Fatal("download token accepted for upload")
	}
	// The failed attempt burned it (one-shot means one attempt).
	if _, _, ok := ts.consume(tok, opDownload); ok {
		t.Fatal("token survived a wrong-op attempt")
	}
}

func TestTokenExpiry(t *testing.T) {
	ts := newTokenStore()
	base := time.Now()
	ts.now = func() time.Time { return base }
	tok := ts.issue("f_1", opUpload, 0)

	ts.now = func() time.Time { return base.Add(tokenTTL + time.Second) }
	if _, _, ok := ts.consume(tok, opUpload); ok {
		t.Fatal("expired token accepted")
	}

	// The lazy sweep drops expired entries on the next issue.
	_ = ts.issue("f_2", opUpload, 0)
	ts.mu.Lock()
	n := len(ts.tokens)
	ts.mu.Unlock()
	if n != 1 {
		t.Fatalf("token map holds %d entries, want 1 after sweep", n)
	}
}

func TestUnknownTokenRejected(t *testing.T) {
	ts := newTokenStore()
	if _, _, ok := ts.consume("nope", opUpload); ok {
		t.Fatal("unknown token accepted")
	}
}
