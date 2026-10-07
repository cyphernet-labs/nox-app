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

func TestIssuingAnUploadTokenRevokesTheEarlierOnesForThatFile(t *testing.T) {
	ts := newTokenStore()
	earlier := ts.issue("f_1", opUpload, 100)
	other := ts.issue("f_2", opUpload, 0)
	download := ts.issue("f_1", opDownload, 0)
	later := ts.issue("f_1", opUpload, 200)

	// A PUT held up on its way and arriving after the client asked again
	// would cut the part back to its older offset, past bytes the newer one
	// has written since.
	if _, _, ok := ts.consume(earlier, opUpload); ok {
		t.Fatal("an upload token outlived the next one issued for its file")
	}
	if _, offset, ok := ts.consume(later, opUpload); !ok || offset != 200 {
		t.Fatalf("the newest upload token = %d, %v; want it valid at 200", offset, ok)
	}
	if _, _, ok := ts.consume(other, opUpload); !ok {
		t.Fatal("another file's upload token was revoked")
	}
	if _, _, ok := ts.consume(download, opDownload); !ok {
		t.Fatal("a download token was revoked by an upload's")
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
