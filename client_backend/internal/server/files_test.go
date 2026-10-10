package server

import (
	"bytes"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/http/httptrace"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"

	"nox.app/client-backend/internal/protocol"
	"nox.app/client-backend/internal/store"
)

func uploadBegin(t *testing.T, c *wsClient, id int, name string, size int, mime string) (string, string) {
	t.Helper()
	data := c.expectOKAfter(id, fmt.Sprintf(
		`{"id":%d,"cmd":"file.uploadBegin","data":{"name":%q,"size":%d,"mime":%q}}`, id, name, size, mime))
	var fileID, token, uploadURL string
	mustUnmarshal(t, data["file_id"], &fileID)
	mustUnmarshal(t, data["upload_token"], &token)
	mustUnmarshal(t, data["upload_url"], &uploadURL)
	if uploadURL != "/files/"+token {
		t.Fatalf("upload_url = %q, want relative /files/<token>", uploadURL)
	}
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
	var token, downloadURL string
	mustUnmarshal(t, data["download_token"], &token)
	mustUnmarshal(t, data["download_url"], &downloadURL)
	if downloadURL != "/files/"+token {
		t.Fatalf("download_url = %q, want relative /files/<token>", downloadURL)
	}
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

	anna := dialWS(t, ts, srv)
	anna.expectGreeting()
	anna.hello(1, `,"label":"Anna"`)
	chatID := seedChat(t, anna, "files")

	bob := dialWS(t, ts, srv)
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
	// ...and in the second client's event, without client_message_id. The
	// dispatcher may flush the pre-subscription chat.created first - read
	// until the message arrives.
	var evData map[string]json.RawMessage
	gotMsg := false
	for range 5 {
		_, name, data := bob.expectEvent()
		if name == protocol.EventMessageNew {
			evData = data
			gotMsg = true
			break
		}
	}
	if !gotMsg {
		t.Fatal("bob never received message.new")
	}
	var evAtt protocol.Attachment
	mustUnmarshal(t, evData["attachment"], &evAtt)
	if evAtt != *echo.Attachment {
		t.Fatalf("event attachment = %+v, want %+v", evAtt, *echo.Attachment)
	}
	if _, present := evData["client_message_id"]; !present {
		t.Fatal("the author's other device lost its own client_message_id")
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

	// Un-uploaded file: send rejected. An oversized PUT keeps nothing it
	// carried; a short one keeps its bytes for a continuation (043). Neither
	// finishes the file.
	fileID3, token3 := uploadBegin(t, anna, 25, "half.bin", 1000, "application/octet-stream")
	anna.send(fmt.Sprintf(`{"id":26,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"n4","attachment":{"file_id":%q}}}`, chatID, fileID3))
	anna.expectErr(26, protocol.ErrInvalidRequest)
	if code := putBytes(t, ts, token3, randomPayload(t, 2000)); code != http.StatusRequestEntityTooLarge {
		t.Fatalf("oversized PUT = %d, want 413", code)
	}
	if _, _, received := declare(t, anna, 28, "half.bin", 1000, "application/octet-stream", fileID3); received != 0 {
		t.Fatalf("after an oversized PUT received = %d, want 0: none of its bytes are kept", received)
	}
	fileID4, token4 := uploadBegin(t, anna, 27, "short.bin", 1000, "application/octet-stream")
	if code := putBytes(t, ts, token4, randomPayload(t, 500)); code != http.StatusBadRequest {
		t.Fatalf("short PUT = %d, want 400", code)
	}
	if _, _, received := declare(t, anna, 29, "short.bin", 1000, "application/octet-stream", fileID4); received != 500 {
		t.Fatalf("after a short PUT received = %d, want its 500 bytes kept", received)
	}
	if srv.blob.Exists(fileID3) || srv.blob.Exists(fileID4) {
		t.Fatal("an unfinished upload became a finished file")
	}

	// New 024 validation negatives: JSON-null body, empty attachment object,
	// oversized metadata.
	anna.send(fmt.Sprintf(`{"id":30,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"n5","body":null}}`, chatID))
	anna.expectErr(30, protocol.ErrInvalidRequest)
	anna.send(fmt.Sprintf(`{"id":31,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"n6","body":{"type":"text","text":"x"},"attachment":{}}}`, chatID))
	anna.expectErr(31, protocol.ErrInvalidRequest)
	longName := strings.Repeat("n", 256)
	anna.send(fmt.Sprintf(`{"id":32,"cmd":"file.uploadBegin","data":{"name":%q,"size":10,"mime":"x/y"}}`, longName))
	anna.expectErr(32, protocol.ErrInvalidRequest)

	// L: the duplicate produced no event - Bob's next two events are the
	// notes.txt attachment message and the probe below, with nothing in
	// between.
	sendText(t, anna, 33, chatID, "probe1", "after dup probe")
	_, _, ev2 := bob.expectEvent()
	var att2 protocol.Attachment
	mustUnmarshal(t, ev2["attachment"], &att2)
	if att2.Name != "notes.txt" {
		t.Fatalf("bob's second event attachment = %+v, want notes.txt", att2)
	}
	_, _, ev3 := bob.expectEvent()
	var probeMsg protocol.Message
	raw, err := json.Marshal(ev3)
	if err != nil {
		t.Fatalf("re-marshal: %v", err)
	}
	if err := json.Unmarshal(raw, &probeMsg); err != nil || probeMsg.Attachment != nil {
		t.Fatalf("bob's third event = %+v err=%v, want the plain probe (no duplicate attachment event)", probeMsg, err)
	}
}

func TestStoryOneUploadSurvivesRestart(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "restart.db")

	ts, srv, closeAll := openStack(t, path, nil)
	firstClosed := false
	defer func() {
		if !firstClosed {
			closeAll()
		}
	}()
	c := dialWS(t, ts, srv)
	c.expectGreeting()
	c.hello(1, `,"label":"Anna"`)
	chatID := seedChat(t, c, "restart-files")
	payload := []byte("survives restarts")
	fileID, token := uploadBegin(t, c, 3, "keep.bin", len(payload), "application/octet-stream")
	if code := putBytes(t, ts, token, payload); code != http.StatusNoContent {
		t.Fatalf("PUT = %d", code)
	}
	_ = c.conn.Close(websocket.StatusNormalClosure, "restarting")
	closeAll()
	firstClosed = true

	// A fresh process over the same db and files dir: the upload is intact
	// and still sendable, and the bytes download byte-identically.
	ts2, srv2, closeAll2 := openStack(t, path, nil)
	defer closeAll2()
	c2 := dialWS(t, ts2, srv2)
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

	anna := dialWS(t, ts, srv)
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

	bob := dialWS(t, ts, srv)
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

	// HEAD must not burn the one-shot token (an accidental curl -I would
	// otherwise kill the link): 405, and the token still downloads.
	dl4 := downloadBegin(t, bob, 9, fileID)
	headReq, err := http.NewRequest(http.MethodHead, ts.URL+"/files/"+dl4, nil)
	if err != nil {
		t.Fatalf("build HEAD: %v", err)
	}
	headResp, err := ts.Client().Do(headReq)
	if err != nil {
		t.Fatalf("HEAD: %v", err)
	}
	_ = headResp.Body.Close()
	if headResp.StatusCode != http.StatusMethodNotAllowed {
		t.Fatalf("HEAD = %d, want 405", headResp.StatusCode)
	}
	if code, body, _ := doGet(t, ts, dl4, ""); code != http.StatusOK || !bytes.Equal(body, payload) {
		t.Fatalf("GET after HEAD = %d, %d bytes - the token must survive a HEAD", code, len(body))
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
	ts, srv := newTestServer(t)

	c := dialWS(t, ts, srv)
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

func TestOrphanSweepRemovesAbandonedUploads(t *testing.T) {
	ts, srv := newTestServer(t)

	c := dialWS(t, ts, srv)
	c.expectGreeting()
	c.hello(1, `,"label":"Anna"`)
	chatID := seedChat(t, c, "sweep")

	// Bound file seeded with an OLD created_at: it must survive the sweep
	// because it is bound, not because it is fresh (a wall-clock-based
	// assertion would pass for the wrong reason).
	boundAtt, err := srv.store.CreateUpload(t.Context(), "bound.bin", 5, "x/y", 100)
	if err != nil {
		t.Fatalf("CreateUpload bound: %v", err)
	}
	boundUp, err := srv.blob.Create(boundAtt.FileID)
	if err != nil {
		t.Fatalf("blob.Create bound: %v", err)
	}
	if _, err := boundUp.Write([]byte("bytes")); err != nil {
		t.Fatalf("write bound: %v", err)
	}
	if err := boundUp.Finalize(); err != nil {
		t.Fatalf("finalize bound: %v", err)
	}
	if err := srv.store.MarkUploaded(t.Context(), boundAtt.FileID); err != nil {
		t.Fatalf("MarkUploaded bound: %v", err)
	}
	boundID := boundAtt.FileID
	c.expectOKAfter(4, fmt.Sprintf(
		`{"id":4,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"s1","attachment":{"file_id":%q}}}`, chatID, boundID))

	// Old orphan: declared and uploaded long ago, never sent (seeded through
	// the store to control created_at; bytes written to the blob directly).
	oldAtt, err := srv.store.CreateUpload(t.Context(), "old.bin", 3, "x/y", 100)
	if err != nil {
		t.Fatalf("CreateUpload: %v", err)
	}
	up, err := srv.blob.Create(oldAtt.FileID)
	if err != nil {
		t.Fatalf("blob.Create: %v", err)
	}
	if _, err := up.Write([]byte("old")); err != nil {
		t.Fatalf("write: %v", err)
	}
	if err := up.Finalize(); err != nil {
		t.Fatalf("finalize: %v", err)
	}
	if err := srv.store.MarkUploaded(t.Context(), oldAtt.FileID); err != nil {
		t.Fatalf("MarkUploaded: %v", err)
	}

	// Old UNFINISHED upload (043): a part and its record, never completed.
	// The same rule as for a finished one: a day unbound and it goes, both
	// files with it.
	halfAtt, err := srv.store.CreateUpload(t.Context(), "half.bin", 10, "x/y", 100)
	if err != nil {
		t.Fatalf("CreateUpload half: %v", err)
	}
	half, err := srv.blob.Create(halfAtt.FileID)
	if err != nil {
		t.Fatalf("blob.Create half: %v", err)
	}
	if _, err := half.Write([]byte("half")); err != nil {
		t.Fatalf("write half: %v", err)
	}
	if err := half.Suspend(); err != nil {
		t.Fatalf("suspend half: %v", err)
	}
	for _, name := range []string{halfAtt.FileID + ".part", halfAtt.FileID + ".synced"} {
		if _, err := os.Stat(filepath.Join(srv.cfg.FilesPath, name)); err != nil {
			t.Fatalf("seeded %s missing: %v", name, err)
		}
	}

	// Fresh orphan: declared over the wire just now - must survive.
	freshID, _ := uploadBegin(t, c, 5, "fresh.bin", 5, "x/y")

	if err := srv.sweepOrphans(t.Context(), 1000); err != nil {
		t.Fatalf("sweepOrphans: %v", err)
	}

	if srv.blob.Exists(oldAtt.FileID) {
		t.Fatal("old orphan bytes survived the sweep")
	}
	for _, name := range []string{halfAtt.FileID + ".part", halfAtt.FileID + ".synced"} {
		if _, err := os.Stat(filepath.Join(srv.cfg.FilesPath, name)); !errors.Is(err, os.ErrNotExist) {
			t.Fatalf("%s of the old unfinished upload survived the sweep (err=%v)", name, err)
		}
	}
	if _, err := srv.store.FileByID(t.Context(), halfAtt.FileID); !errors.Is(err, store.ErrFileNotFound) {
		t.Fatalf("old unfinished row = %v, want gone", err)
	}
	if _, err := srv.store.FileByID(t.Context(), oldAtt.FileID); !errors.Is(err, store.ErrFileNotFound) {
		t.Fatalf("old orphan row = %v, want gone", err)
	}
	if !srv.blob.Exists(boundID) {
		t.Fatal("bound file bytes were swept")
	}
	if _, err := srv.store.FileByID(t.Context(), freshID); err != nil {
		t.Fatalf("fresh upload swept: %v", err)
	}
}

// A transfer needs a paired key on the connection AND a live token (044,
// FR-006a). A token alone was a bearer credential: whoever held one moved the
// bytes. A stranger is told 401 before the token is even looked at, so it can
// neither spend one nor learn whether it is live.
func TestATransferNeedsAPairedKeyAsWellAsAToken(t *testing.T) {
	ts, srv := newTestServer(t)
	anna := dialWS(t, ts, srv)
	anna.expectGreeting()
	anna.hello(1, "")
	stranger := channelOf(t, ts).clientAs(newDevice(t))
	payload := randomPayload(t, 4096)
	fileID, token := uploadBegin(t, anna, 2, "a.bin", len(payload), "application/octet-stream")

	status := func(client *http.Client, method, token string, body []byte) int {
		t.Helper()
		req, err := http.NewRequest(method, ts.URL+"/files/"+token, bytes.NewReader(body))
		if err != nil {
			t.Fatalf("build %s: %v", method, err)
		}
		resp, err := client.Do(req)
		if err != nil {
			t.Fatalf("%s: %v", method, err)
		}
		_, _ = io.Copy(io.Discard, resp.Body)
		_ = resp.Body.Close()
		return resp.StatusCode
	}

	if got := status(stranger, http.MethodPut, token, payload); got != http.StatusUnauthorized {
		t.Fatalf("PUT from an unpaired key with a live token = %d, want 401", got)
	}
	// The refusal spent nothing: the paired device's PUT with the same token
	// lands.
	if got := putBytes(t, ts, token, payload); got != http.StatusNoContent {
		t.Fatalf("PUT from the paired device after the refusal = %d, want 204", got)
	}
	// A spent token from a paired device is still the 404 a client of 043
	// reads as "ask for a new pass"; from a stranger it is 401 all the same.
	if got := putBytes(t, ts, token, payload); got != http.StatusNotFound {
		t.Fatalf("spent token from the paired device = %d, want 404", got)
	}
	if got := status(stranger, http.MethodPut, token, payload); got != http.StatusUnauthorized {
		t.Fatalf("spent token from an unpaired key = %d, want 401", got)
	}

	download := downloadBegin(t, anna, 3, fileID)
	for _, method := range []string{http.MethodGet, http.MethodHead} {
		if got := status(stranger, method, download, nil); got != http.StatusUnauthorized {
			t.Fatalf("%s from an unpaired key with a live token = %d, want 401", method, got)
		}
	}
	code, body, _ := doGet(t, ts, download, "")
	if code != http.StatusOK || !bytes.Equal(body, payload) {
		t.Fatalf("GET from the paired device after the refusals = %d, %d bytes", code, len(body))
	}
}

// The key is looked up on every request, not once per connection. A
// connection kept open between two transfers carries none under way, so a
// revocation has nothing on it to cut (see the test below) - and the next
// request on it is refused instead.
func TestARevokedDeviceLosesItsTransfersOnAnOpenConnection(t *testing.T) {
	ts, srv := newTestServer(t)
	anna := dialWS(t, ts, srv)
	anna.expectGreeting()
	anna.hello(1, "")
	client := channelOf(t, ts).clientAs(anna.dev)
	payload := randomPayload(t, 2048)
	_, first := uploadBegin(t, anna, 2, "a.bin", len(payload), "application/octet-stream")

	// One request first, so the connection exists and is kept for the next.
	req, err := http.NewRequest(http.MethodGet, ts.URL+"/files/not-a-token", nil)
	if err != nil {
		t.Fatalf("build GET: %v", err)
	}
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("GET: %v", err)
	}
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("a paired device with a bad token = %d, want 404", resp.StatusCode)
	}

	if err := srv.store.RevokeDevice(t.Context(), anna.dev.pub); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}
	var reused bool
	trace := httptrace.WithClientTrace(t.Context(), &httptrace.ClientTrace{
		GotConn: func(info httptrace.GotConnInfo) { reused = info.Reused },
	})
	put, err := http.NewRequestWithContext(trace, http.MethodPut, ts.URL+"/files/"+first, bytes.NewReader(payload))
	if err != nil {
		t.Fatalf("build PUT: %v", err)
	}
	resp, err = client.Do(put)
	if err != nil {
		t.Fatalf("PUT: %v", err)
	}
	_ = resp.Body.Close()
	if !reused {
		t.Fatal("the PUT opened a new connection, so this test proves nothing about an open one")
	}
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("PUT from a device revoked mid-connection = %d, want 401", resp.StatusCode)
	}
}

// Revoking a device cuts its transfers under way, not only its socket. Each
// transfer runs on a connection of its own, which closing the socket does not
// touch, and nothing but silence ends one - so a lost phone halfway through a
// download would otherwise go on reading the person's files for as long as it
// kept reading. Its upload stops taking bytes and keeps the ones it had, its
// download breaks off far short of the file, and the person's other devices
// go on as they were.
func TestRevokingADeviceCutsItsTransfersUnderWay(t *testing.T) {
	ts, srv, closeAll := openStack(t, filepath.Join(t.TempDir(), "revoke.db"), nil, func(s *Server) {
		// Nothing but the revocation may end them here: silence would take a
		// minute.
		s.stallTimeout = time.Minute
	})
	t.Cleanup(closeAll)
	owner := greeted(t, ts, srv)
	lost := pairedDevice(t, ts, srv)
	phone := dialAs(t, ts, srv, lost)
	phone.expectGreeting()
	phone.hello(1, "")
	const mime = "application/octet-stream"

	// The phone has an upload half sent...
	upload := randomPayload(t, 200000)
	upID, upToken, _ := declare(t, phone, 2, "up.bin", len(upload), mime, "")
	put := openRawPutAs(t, ts, lost, upToken, len(upload))
	put.send(upload[:50000])
	waitPart(t, srv, upID, 50000)
	// ...and a download it is reading, larger than the socket buffers on both
	// ends can hold, so the server is still writing when the revocation comes.
	movie := randomPayload(t, 32<<20)
	movieID := storeFile(t, srv, movie)
	resp, err := channelOf(t, ts).clientAs(lost).Get(ts.URL + "/files/" + downloadBegin(t, phone, 3, movieID))
	if err != nil {
		t.Fatalf("GET: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()
	head := make([]byte, 64<<10)
	if _, err := io.ReadFull(resp.Body, head); err != nil {
		t.Fatalf("read the first bytes: %v", err)
	}
	// The owner is uploading at the same moment.
	mine := randomPayload(t, 100000)
	mineID, mineToken, _ := declare(t, owner, 2, "mine.bin", len(mine), mime, "")
	kept := openRawPutAs(t, ts, owner.dev, mineToken, len(mine))
	kept.send(mine[:30000])
	waitPart(t, srv, mineID, 30000)
	if n := transfersOf(srv, lost.pub); n != 2 {
		t.Fatalf("%d of the phone's transfers are under way, want its upload and its download", n)
	}

	revoked := time.Now()
	owner.expectOKAfter(3, fmt.Sprintf(`{"id":3,"cmd":"device.revoke","data":{"device_key":%q}}`, lost.pub))

	// The upload: the server stops reading at once, says nothing - the
	// connection just ends - and keeps exactly the bytes from before.
	waitIdle(t, srv, upID)
	put.expectCut(5 * time.Second)
	if info, err := os.Stat(partPath(srv, upID)); err != nil || info.Size() != 50000 {
		t.Fatalf("the part after the cut: %v, %v; want the 50000 bytes from before it", info, err)
	}
	if srv.blob.Exists(upID) {
		t.Fatal("the revoked device's upload became a file")
	}

	// The download: what was already on its way still arrives, and then the
	// body breaks off - far short of the file, and long before a stall could
	// have cut it.
	rest, err := io.ReadAll(resp.Body)
	if err == nil || len(head)+len(rest) >= len(movie) {
		t.Fatalf("the download went on past the revocation: %d of %d bytes, err=%v", len(head)+len(rest), len(movie), err)
	}
	if took := time.Since(revoked); took > srv.stallTimeout/6 {
		t.Fatalf("the transfers ended %v after the revocation", took)
	}
	eventually(t, "the phone has no transfer left", func() bool { return transfersOf(srv, lost.pub) == 0 })

	// The owner's upload was never touched.
	kept.send(mine[30000:])
	if code := kept.status(5 * time.Second); code != http.StatusNoContent {
		t.Fatalf("the owner's upload after the revocation = %d, want 204", code)
	}
	if !bytes.Equal(diskBytes(t, srv, mineID), mine) {
		t.Fatal("the owner's file is not the bytes that were sent")
	}
}

// transfersOf counts the transfers under way on connections that proved key.
func transfersOf(srv *Server, key string) int {
	srv.mu.Lock()
	defer srv.mu.Unlock()
	n := 0
	for tr := range srv.transfers {
		if tr.deviceKey == key {
			n++
		}
	}
	return n
}

// A handler served without the channel in front of it - a wiring mistake, a
// test mux - hands nothing out: no session, no bytes. Run never builds one,
// and this keeps a slip from becoming a hole.
func TestAHandlerWithoutTheChannelRefusesEverything(t *testing.T) {
	_, srv := newTestServer(t)
	for _, tc := range []struct{ method, path string }{
		{http.MethodGet, "/ws"},
		{http.MethodPut, "/files/anything"},
		{http.MethodGet, "/files/anything"},
	} {
		req := httptest.NewRequest(tc.method, tc.path, nil)
		req.Header.Set("Connection", "Upgrade")
		req.Header.Set("Upgrade", "websocket")
		req.Header.Set("Sec-WebSocket-Version", "13")
		req.Header.Set("Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==")
		rec := httptest.NewRecorder()
		srv.Handler().ServeHTTP(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("%s %s without a channel peer = %d, want 401", tc.method, tc.path, rec.Code)
		}
	}
}
