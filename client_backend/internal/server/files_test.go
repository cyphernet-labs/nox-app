package server

import (
	"bytes"
	"crypto/rand"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"nox.app/client-backend/internal/protocol"
	"nox.app/client-backend/internal/store"
)

func uploadBegin(t *testing.T, c *wsClient, id int, name string, size int, mime string) (string, string) {
	t.Helper()
	data := c.expectOKAfter(id, fmt.Sprintf(
		`{"id":%d,"cmd":"file.uploadBegin","data":{"name":%q,"size":%d,"mime":%q}}`, id, name, size, mime))
	var fileID, token string
	mustUnmarshal(t, data["file_id"], &fileID)
	mustUnmarshal(t, data["upload_token"], &token)
	var limit int64
	mustUnmarshal(t, data["max_attachment_bytes"], &limit)
	if limit != 104857600 {
		t.Fatalf("max_attachment_bytes = %d", limit)
	}
	return fileID, token
}

func putBytes(t *testing.T, ts *httptest.Server, token string, payload []byte) int {
	t.Helper()
	req, err := http.NewRequest(http.MethodPut, ts.URL+"/files/"+token, bytes.NewReader(payload))
	if err != nil {
		t.Fatalf("build PUT: %v", err)
	}
	resp, err := ts.Client().Do(req)
	if err != nil {
		t.Fatalf("PUT: %v", err)
	}
	_, _ = io.Copy(io.Discard, resp.Body)
	_ = resp.Body.Close()
	return resp.StatusCode
}

func downloadBegin(t *testing.T, c *wsClient, id int, fileID string) string {
	t.Helper()
	data := c.expectOKAfter(id, fmt.Sprintf(
		`{"id":%d,"cmd":"file.downloadBegin","data":{"file_id":%q}}`, id, fileID))
	var token string
	mustUnmarshal(t, data["download_token"], &token)
	return token
}

// doGet fetches /files/<token>, optionally with a Range header, and returns
// status, body and headers with all error paths funneled through t.Fatalf.
func doGet(t *testing.T, ts *httptest.Server, token, rangeHdr string) (int, []byte, http.Header) {
	t.Helper()
	req, err := http.NewRequest(http.MethodGet, ts.URL+"/files/"+token, nil)
	if err != nil {
		t.Fatalf("build GET: %v", err)
	}
	if rangeHdr != "" {
		req.Header.Set("Range", rangeHdr)
	}
	resp, err := ts.Client().Do(req)
	if err != nil {
		t.Fatalf("GET: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("read GET body: %v", err)
	}
	return resp.StatusCode, body, resp.Header
}

func randomPayload(t *testing.T, n int) []byte {
	t.Helper()
	p := make([]byte, n)
	if _, err := rand.Read(p); err != nil {
		t.Fatalf("rand: %v", err)
	}
	return p
}

func TestStoryOneAttachmentChain(t *testing.T) {
	ts, srv := newTestServer(t)

	anna := dialWS(t, ts)
	anna.expectGreeting()
	anna.hello(1, `,"label":"Anna"`)
	chatID := seedChat(t, anna, "files")

	bob := dialWS(t, ts)
	bob.expectGreeting()
	bob.hello(1, `,"label":"Bob"`)

	payload := randomPayload(t, 200000)
	fileID, token := uploadBegin(t, anna, 10, "report.pdf", len(payload), "application/pdf")
	if code := putBytes(t, ts, token, payload); code != http.StatusNoContent {
		t.Fatalf("PUT = %d, want 204", code)
	}
	// One-shot: the same token is dead (SC-003).
	if code := putBytes(t, ts, token, payload); code != http.StatusNotFound {
		t.Fatalf("reused upload token = %d, want 404", code)
	}
	// Bytes are on disk under the server id, byte-identical.
	disk, err := os.ReadFile(filepath.Join(srv.cfg.FilesPath, fileID))
	if err != nil || !bytes.Equal(disk, payload) {
		t.Fatalf("disk bytes: %d err=%v", len(disk), err)
	}

	// Attachment-only send: full attachment in the echo...
	sent := anna.expectOKAfter(11, fmt.Sprintf(
		`{"id":11,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"f1","attachment":{"file_id":%q}}}`, chatID, fileID))
	var echo protocol.Message
	mustUnmarshal(t, sent["message"], &echo)
	if echo.Attachment == nil || echo.Attachment.FileID != fileID || echo.Attachment.Name != "report.pdf" ||
		echo.Attachment.Size != int64(len(payload)) || echo.Attachment.Mime != "application/pdf" || echo.Attachment.ExpiresAt == 0 {
		t.Fatalf("echo attachment = %+v", echo.Attachment)
	}
	// ...and in the second client's event, without client_message_id.
	_, name, evData := bob.expectEvent()
	if name != protocol.EventMessageNew {
		t.Fatalf("bob event = %s", name)
	}
	var evAtt protocol.Attachment
	mustUnmarshal(t, evData["attachment"], &evAtt)
	if evAtt != *echo.Attachment {
		t.Fatalf("event attachment = %+v, want %+v", evAtt, *echo.Attachment)
	}
	if _, leaked := evData["client_message_id"]; leaked {
		t.Fatal("bob's message.new leaked client_message_id")
	}

	// Preview of a text-less attachment message is the file name (SC-005).
	page := listChats(t, anna, 12, `{"page":1,"page_size":10}`)
	if page.Chats[0].LastMessagePreview != "report.pdf" {
		t.Fatalf("preview = %q, want the file name", page.Chats[0].LastMessagePreview)
	}

	// Attachment WITH text keeps the text preview.
	fileID2, token2 := uploadBegin(t, anna, 13, "notes.txt", 4, "text/plain")
	if code := putBytes(t, ts, token2, []byte("data")); code != http.StatusNoContent {
		t.Fatalf("second PUT = %d", code)
	}
	anna.expectOKAfter(14, fmt.Sprintf(
		`{"id":14,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"f2","body":{"type":"text","text":"see attached"},"attachment":{"file_id":%q}}}`, chatID, fileID2))
	page = listChats(t, anna, 15, `{"page":1,"page_size":10}`)
	if page.Chats[0].LastMessagePreview != "see attached" {
		t.Fatalf("preview with text = %q", page.Chats[0].LastMessagePreview)
	}

	// Duplicate send: identical echo, no second event for Bob.
	dup := anna.expectOKAfter(16, fmt.Sprintf(
		`{"id":16,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"f1","attachment":{"file_id":%q}}}`, chatID, fileID))
	var dupMsg protocol.Message
	mustUnmarshal(t, dup["message"], &dupMsg)
	if dupMsg.MessageID != echo.MessageID || dupMsg.Attachment == nil || *dupMsg.Attachment != *echo.Attachment {
		t.Fatalf("duplicate echo = %+v", dupMsg)
	}

	// Negatives.
	anna.send(`{"id":20,"cmd":"file.uploadBegin","data":{"name":"big","size":999999999999,"mime":"x"}}`)
	anna.expectErr(20, protocol.ErrPayloadTooLarge)
	anna.send(`{"id":21,"cmd":"file.uploadBegin","data":{"name":"","size":10,"mime":"x"}}`)
	anna.expectErr(21, protocol.ErrInvalidRequest)
	anna.send(fmt.Sprintf(`{"id":22,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"n1"}}`, chatID))
	anna.expectErr(22, protocol.ErrInvalidRequest)
	anna.send(fmt.Sprintf(`{"id":23,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"n2","attachment":{"file_id":"f_missing"}}}`, chatID))
	anna.expectErr(23, protocol.ErrInvalidRequest)
	anna.send(fmt.Sprintf(`{"id":24,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"n3","attachment":{"file_id":%q}}}`, chatID, fileID))
	anna.expectErr(24, protocol.ErrInvalidRequest) // already bound

	// Un-uploaded file: send rejected; oversized and short PUTs store nothing.
	fileID3, token3 := uploadBegin(t, anna, 25, "half.bin", 1000, "application/octet-stream")
	anna.send(fmt.Sprintf(`{"id":26,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"n4","attachment":{"file_id":%q}}}`, chatID, fileID3))
	anna.expectErr(26, protocol.ErrInvalidRequest)
	if code := putBytes(t, ts, token3, randomPayload(t, 2000)); code != http.StatusRequestEntityTooLarge {
		t.Fatalf("oversized PUT = %d, want 413", code)
	}
	_, token4 := uploadBegin(t, anna, 27, "short.bin", 1000, "application/octet-stream")
	if code := putBytes(t, ts, token4, randomPayload(t, 500)); code != http.StatusBadRequest {
		t.Fatalf("short PUT = %d, want 400", code)
	}
	if srv.blob.Exists(fileID3) {
		t.Fatal("oversized upload left bytes behind")
	}
}

func TestStoryOneUploadSurvivesRestart(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "restart.db")

	ts, _, closeAll := openStack(t, path)
	c := dialWS(t, ts)
	c.expectGreeting()
	c.hello(1, `,"label":"Anna"`)
	chatID := seedChat(t, c, "restart-files")
	payload := []byte("survives restarts")
	fileID, token := uploadBegin(t, c, 3, "keep.bin", len(payload), "application/octet-stream")
	if code := putBytes(t, ts, token, payload); code != http.StatusNoContent {
		t.Fatalf("PUT = %d", code)
	}
	closeAll()

	// A fresh process over the same db and files dir: the upload is intact
	// and still sendable, and the bytes download byte-identically.
	ts2, _, closeAll2 := openStack(t, path)
	defer closeAll2()
	c2 := dialWS(t, ts2)
	c2.expectGreeting()
	c2.hello(1, `,"label":"Anna"`)
	sent := c2.expectOKAfter(2, fmt.Sprintf(
		`{"id":2,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"r1","attachment":{"file_id":%q}}}`, chatID, fileID))
	var msg protocol.Message
	mustUnmarshal(t, sent["message"], &msg)
	if msg.Attachment == nil || msg.Attachment.Name != "keep.bin" {
		t.Fatalf("post-restart attachment = %+v", msg.Attachment)
	}
	dl := downloadBegin(t, c2, 3, fileID)
	code, got, _ := doGet(t, ts2, dl, "")
	if code != http.StatusOK || !bytes.Equal(got, payload) {
		t.Fatalf("post-restart download = %d, %d bytes", code, len(got))
	}
}

func TestStoryTwoDownloadWithResume(t *testing.T) {
	ts, srv := newTestServer(t)

	anna := dialWS(t, ts)
	anna.expectGreeting()
	anna.hello(1, `,"label":"Anna"`)
	chatID := seedChat(t, anna, "dl")
	payload := randomPayload(t, 262144)
	fileID, token := uploadBegin(t, anna, 3, "movie.bin", len(payload), "application/octet-stream")
	if code := putBytes(t, ts, token, payload); code != http.StatusNoContent {
		t.Fatalf("PUT = %d", code)
	}
	anna.expectOKAfter(4, fmt.Sprintf(
		`{"id":4,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"d1","attachment":{"file_id":%q}}}`, chatID, fileID))

	bob := dialWS(t, ts)
	bob.expectGreeting()
	bob.hello(1, `,"label":"Bob"`)

	// Full download, byte-identical (SC-001).
	dl := downloadBegin(t, bob, 2, fileID)
	code, full, hdr := doGet(t, ts, dl, "")
	if code != http.StatusOK {
		t.Fatalf("GET = %d, want 200", code)
	}
	if ct := hdr.Get("Content-Type"); ct != "application/octet-stream" {
		t.Fatalf("Content-Type = %q", ct)
	}
	if !bytes.Equal(full, payload) {
		t.Fatalf("full download mismatch: %d bytes", len(full))
	}
	// The token is one-shot.
	if code, _, _ := doGet(t, ts, dl, ""); code != http.StatusNotFound {
		t.Fatalf("reused download token = %d, want 404", code)
	}

	// Resume: a fresh token, Range from the middle -> exactly the remainder
	// (SC-002), and the concatenation equals the original.
	const cut = 131072
	dl2 := downloadBegin(t, bob, 3, fileID)
	code, tail, _ := doGet(t, ts, dl2, fmt.Sprintf("bytes=%d-", cut))
	if code != http.StatusPartialContent {
		t.Fatalf("range GET = %d, want 206", code)
	}
	if len(tail) != len(payload)-cut {
		t.Fatalf("resumed %d bytes, want exactly %d", len(tail), len(payload)-cut)
	}
	if !bytes.Equal(append(payload[:cut:cut], tail...), payload) {
		t.Fatal("resumed concatenation mismatch")
	}

	// Range beyond the size.
	dl3 := downloadBegin(t, bob, 4, fileID)
	if code, _, _ := doGet(t, ts, dl3, "bytes=99999999-"); code != http.StatusRequestedRangeNotSatisfiable {
		t.Fatalf("out-of-range GET = %d, want 416", code)
	}

	// downloadBegin negatives: unknown, un-uploaded, physically gone.
	bob.send(`{"id":5,"cmd":"file.downloadBegin","data":{"file_id":"f_missing"}}`)
	bob.expectErr(5, protocol.ErrNotFound)
	pendingID, _ := uploadBegin(t, bob, 6, "pending.bin", 10, "x/y")
	bob.send(fmt.Sprintf(`{"id":7,"cmd":"file.downloadBegin","data":{"file_id":%q}}`, pendingID))
	bob.expectErr(7, protocol.ErrInvalidRequest)
	if err := os.Remove(filepath.Join(srv.cfg.FilesPath, fileID)); err != nil {
		t.Fatalf("remove bytes: %v", err)
	}
	bob.send(fmt.Sprintf(`{"id":8,"cmd":"file.downloadBegin","data":{"file_id":%q}}`, fileID))
	bob.expectErr(8, protocol.ErrAttachmentGone)
}

func TestStoryThreeChatFilesPanel(t *testing.T) {
	ts, _ := newTestServer(t)

	c := dialWS(t, ts)
	c.expectGreeting()
	c.hello(1, `,"label":"Anna"`)
	chatID := seedChat(t, c, "panel")

	var fileIDs []string
	for i := range 3 {
		sendText(t, c, 100+i, chatID, fmt.Sprintf("t%d", i), "text between files")
		fid, tok := uploadBegin(t, c, 200+i, fmt.Sprintf("doc%d.bin", i), 8, "application/octet-stream")
		if code := putBytes(t, ts, tok, []byte("12345678")); code != http.StatusNoContent {
			t.Fatalf("PUT %d = %d", i, code)
		}
		c.expectOKAfter(300+i, fmt.Sprintf(
			`{"id":%d,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"p%d","attachment":{"file_id":%q}}}`, 300+i, chatID, i, fid))
		fileIDs = append(fileIDs, fid)
	}

	reply := c.expectOKAfter(10, fmt.Sprintf(`{"id":10,"cmd":"chat.files","data":{"chat_id":%q,"limit":2}}`, chatID))
	var page struct {
		Files   []store.ChatFileEntry `json:"files"`
		HasMore bool                  `json:"has_more"`
	}
	mustUnmarshal(t, reply["files"], &page.Files)
	mustUnmarshal(t, reply["has_more"], &page.HasMore)
	if !page.HasMore || len(page.Files) != 2 {
		t.Fatalf("panel page = %d rows hasMore=%v", len(page.Files), page.HasMore)
	}
	if page.Files[0].FileID != fileIDs[1] || page.Files[1].FileID != fileIDs[2] {
		t.Fatalf("panel order = %s, %s", page.Files[0].Name, page.Files[1].Name)
	}
	if page.Files[0].MessageID == "" || page.Files[0].Seq == 0 {
		t.Fatalf("panel row lacks the message anchor: %+v", page.Files[0])
	}

	reply = c.expectOKAfter(11, fmt.Sprintf(`{"id":11,"cmd":"chat.files","data":{"chat_id":%q,"before_seq":%d,"limit":500}}`, chatID, page.Files[0].Seq))
	mustUnmarshal(t, reply["files"], &page.Files)
	mustUnmarshal(t, reply["has_more"], &page.HasMore)
	if page.HasMore || len(page.Files) != 1 || page.Files[0].FileID != fileIDs[0] {
		t.Fatalf("panel rest = %+v hasMore=%v", page.Files, page.HasMore)
	}

	// Empty chat, unknown chat, invalid limit.
	empty := seedChat(t, c, "nofiles")
	reply = c.expectOKAfter(12, fmt.Sprintf(`{"id":12,"cmd":"chat.files","data":{"chat_id":%q,"limit":10}}`, empty))
	mustUnmarshal(t, reply["files"], &page.Files)
	if len(page.Files) != 0 {
		t.Fatalf("empty panel = %+v", page.Files)
	}
	c.send(`{"id":13,"cmd":"chat.files","data":{"chat_id":"c_missing","limit":10}}`)
	c.expectErr(13, protocol.ErrNotFound)
	c.send(fmt.Sprintf(`{"id":14,"cmd":"chat.files","data":{"chat_id":%q,"limit":0}}`, chatID))
	c.expectErr(14, protocol.ErrInvalidRequest)
}
