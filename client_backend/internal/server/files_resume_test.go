package server

import (
	"bufio"
	"bytes"
	"crypto/tls"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"

	"nox.app/client-backend/internal/protocol"
)

// Feature 043: an upload continues where it broke off, and no transfer is cut
// for taking long - only for standing still.

// declare sends file.uploadBegin - continuing fileID when it is not empty -
// and returns the file, the token and how much the server says it holds.
func declare(t *testing.T, c *wsClient, id int, name string, size int, mime, fileID string) (string, string, int64) {
	t.Helper()
	cont := ""
	if fileID != "" {
		cont = fmt.Sprintf(`,"file_id":%q`, fileID)
	}
	data := c.expectOKAfter(id, fmt.Sprintf(
		`{"id":%d,"cmd":"file.uploadBegin","data":{"name":%q,"size":%d,"mime":%q%s}}`, id, name, size, mime, cont))
	var gotID, token, uploadURL string
	mustUnmarshal(t, data["file_id"], &gotID)
	mustUnmarshal(t, data["upload_token"], &token)
	mustUnmarshal(t, data["upload_url"], &uploadURL)
	if uploadURL != "/files/"+token {
		t.Fatalf("upload_url = %q, want relative /files/<token>", uploadURL)
	}
	raw, ok := data["received"]
	if !ok {
		t.Fatal("the reply carries no received: a client could not tell this server continues uploads")
	}
	var received int64
	mustUnmarshal(t, raw, &received)
	return gotID, token, received
}

// rawPut is a PUT driven by hand over its own TLS connection. The standard
// client cannot stop half-way, hold a connection open without sending, or
// break one on purpose - and those are exactly the cases at stake here.
type rawPut struct {
	t    *testing.T
	conn *tls.Conn
	br   *bufio.Reader
}

func openRawPut(t *testing.T, ts *httptest.Server, token string, contentLength int) *rawPut {
	t.Helper()
	transport, ok := ts.Client().Transport.(*http.Transport)
	if !ok {
		t.Fatal("the test client's transport is not the pinned one")
	}
	conn, err := tls.Dial("tcp", ts.Listener.Addr().String(), transport.TLSClientConfig)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	t.Cleanup(func() { _ = conn.Close() })
	head := fmt.Sprintf("PUT /files/%s HTTP/1.1\r\nHost: %s\r\nContent-Length: %d\r\n\r\n",
		token, ts.Listener.Addr(), contentLength)
	if _, err := conn.Write([]byte(head)); err != nil {
		t.Fatalf("write head: %v", err)
	}
	return &rawPut{t: t, conn: conn, br: bufio.NewReader(conn)}
}

func (p *rawPut) send(b []byte) {
	p.t.Helper()
	if _, err := p.conn.Write(b); err != nil {
		p.t.Fatalf("write body: %v", err)
	}
}

// status reads the response, waiting up to d for it.
func (p *rawPut) status(d time.Duration) int {
	p.t.Helper()
	if err := p.conn.SetReadDeadline(time.Now().Add(d)); err != nil {
		p.t.Fatalf("set deadline: %v", err)
	}
	resp, err := http.ReadResponse(p.br, nil)
	if err != nil {
		p.t.Fatalf("read response: %v", err)
	}
	_ = resp.Body.Close()
	return resp.StatusCode
}

// breakOff drops the connection mid-body, the way a phone leaving the network
// does.
func (p *rawPut) breakOff() {
	_ = p.conn.Close()
}

func partPath(srv *Server, fileID string) string {
	return filepath.Join(srv.cfg.FilesPath, fileID+".part")
}

// waitPart waits until the server has written n bytes of fileID's part - all
// a raw PUT sent has been taken off the connection.
func waitPart(t *testing.T, srv *Server, fileID string, n int64) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for {
		if info, err := os.Stat(partPath(srv, fileID)); err == nil && info.Size() >= n {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("the server never wrote %d bytes of %s", n, fileID)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

// writing reports whether a request is writing fileID right now.
func writing(srv *Server, fileID string) bool {
	srv.writers.mu.Lock()
	defer srv.writers.mu.Unlock()
	_, busy := srv.writers.active[fileID]
	return busy
}

// waitIdle waits until no request is writing fileID any more.
func waitIdle(t *testing.T, srv *Server, fileID string) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for writing(srv, fileID) {
		if time.Now().After(deadline) {
			t.Fatalf("a request is still writing %s", fileID)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

// cutAfter starts a PUT for token, delivers the first n bytes of payload and
// breaks off, returning once the server has let go of the file.
func cutAfter(t *testing.T, ts *httptest.Server, srv *Server, fileID, token string, payload []byte, n int) {
	t.Helper()
	put := openRawPut(t, ts, token, len(payload))
	put.send(payload[:n])
	waitPart(t, srv, fileID, int64(n))
	put.breakOff()
	waitIdle(t, srv, fileID)
}

func diskBytes(t *testing.T, srv *Server, fileID string) []byte {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(srv.cfg.FilesPath, fileID))
	if err != nil {
		t.Fatalf("read finished bytes: %v", err)
	}
	return data
}

// slowReader hands out its bytes a chunk at a time with a pause before each:
// a body that keeps moving, however slowly.
type slowReader struct {
	data  []byte
	chunk int
	every time.Duration
}

func (r *slowReader) Read(p []byte) (int, error) {
	if len(r.data) == 0 {
		return 0, io.EOF
	}
	time.Sleep(r.every)
	n := min(r.chunk, len(p), len(r.data))
	copy(p, r.data[:n])
	r.data = r.data[n:]
	return n, nil
}

func greeted(t *testing.T, ts *httptest.Server, srv *Server) *wsClient {
	t.Helper()
	c := dialWS(t, ts, srv)
	c.expectGreeting()
	c.hello(1, `,"label":"Anna"`)
	return c
}

func TestAnUploadContinuesFromTheByteTheServerLacks(t *testing.T) {
	ts, srv := newTestServer(t)
	c := greeted(t, ts, srv)
	chatID := seedChat(t, c, "resume")

	payload := randomPayload(t, 300000)
	fileID, token, received := declare(t, c, 3, "trip.mp4", len(payload), "video/mp4", "")
	if received != 0 {
		t.Fatalf("a new upload answers received=%d, want 0", received)
	}

	cutAfter(t, ts, srv, fileID, token, payload, 100000)

	again, token2, received := declare(t, c, 4, "trip.mp4", len(payload), "video/mp4", fileID)
	if again != fileID {
		t.Fatalf("the continuation answers %q, want the same file %q", again, fileID)
	}
	if received != 100000 {
		t.Fatalf("received = %d, want the 100000 bytes that arrived before the break", received)
	}
	// Only the rest goes up (SC-002), and the file comes out whole.
	if code := putBytes(t, ts, token2, payload[received:]); code != http.StatusNoContent {
		t.Fatalf("PUT of the rest = %d, want 204", code)
	}
	if !bytes.Equal(diskBytes(t, srv, fileID), payload) {
		t.Fatal("the finished file is not the bytes that were sent")
	}
	c.expectOKAfter(5, fmt.Sprintf(
		`{"id":5,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"m1","attachment":{"file_id":%q}}}`, chatID, fileID))
}

func TestAContinuationOfAFinishedUploadAsksForNothingMore(t *testing.T) {
	ts, srv := newTestServer(t)
	c := greeted(t, ts, srv)

	payload := randomPayload(t, 5000)
	fileID, token, _ := declare(t, c, 3, "done.bin", len(payload), "application/octet-stream", "")
	if code := putBytes(t, ts, token, payload); code != http.StatusNoContent {
		t.Fatalf("PUT = %d", code)
	}
	// The 204 got lost on its way back: the client asks again.
	_, token2, received := declare(t, c, 4, "done.bin", len(payload), "application/octet-stream", fileID)
	if received != int64(len(payload)) {
		t.Fatalf("received = %d, want the whole %d", received, len(payload))
	}
	if code := putBytes(t, ts, token2, nil); code != http.StatusNoContent {
		t.Fatalf("empty PUT on a finished upload = %d, want 204", code)
	}
	if !bytes.Equal(diskBytes(t, srv, fileID), payload) {
		t.Fatal("the finished bytes changed")
	}
}

func TestAnEmptyPutFinishesAPartThatAlreadyHoldsEveryByte(t *testing.T) {
	ts, srv := newTestServer(t)
	c := greeted(t, ts, srv)

	payload := randomPayload(t, 1000)
	fileID, _, _ := declare(t, c, 3, "whole.bin", len(payload), "application/octet-stream", "")
	// Every byte arrived and was made durable, and then the process died
	// before the part became the file.
	up, err := srv.blob.Create(fileID)
	if err != nil {
		t.Fatalf("blob.Create: %v", err)
	}
	if _, err := up.Write(payload); err != nil {
		t.Fatalf("write: %v", err)
	}
	if err := up.Suspend(); err != nil {
		t.Fatalf("suspend: %v", err)
	}

	_, token, received := declare(t, c, 4, "whole.bin", len(payload), "application/octet-stream", fileID)
	if received != int64(len(payload)) {
		t.Fatalf("received = %d, want all %d", received, len(payload))
	}
	if code := putBytes(t, ts, token, nil); code != http.StatusNoContent {
		t.Fatalf("empty PUT = %d, want 204", code)
	}
	if !bytes.Equal(diskBytes(t, srv, fileID), payload) {
		t.Fatal("the finished file is not the bytes that were sent")
	}
	// And it is a file now: a message may name it.
	chatID := seedChat(t, c, "whole")
	c.expectOKAfter(5, fmt.Sprintf(
		`{"id":5,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"m1","attachment":{"file_id":%q}}}`, chatID, fileID))
}

func TestAContinuationOfNothingToContinueIsRefused(t *testing.T) {
	ts, srv := newTestServer(t)
	c := greeted(t, ts, srv)
	chatID := seedChat(t, c, "refusals")
	const mime = "application/octet-stream"

	continueWith := func(id int, name string, size int, mime, fileID string) {
		c.send(fmt.Sprintf(`{"id":%d,"cmd":"file.uploadBegin","data":{"name":%q,"size":%d,"mime":%q,"file_id":%q}}`,
			id, name, size, mime, fileID))
	}

	// Never declared.
	continueWith(3, "x.bin", 10, mime, "f_never")
	c.expectErr(3, protocol.ErrNotFound)

	// Declared, finished and sent: a sent file is not an upload any more.
	sentID, token, _ := declare(t, c, 4, "sent.bin", 4, mime, "")
	if code := putBytes(t, ts, token, []byte("sent")); code != http.StatusNoContent {
		t.Fatalf("PUT = %d", code)
	}
	c.expectOKAfter(5, fmt.Sprintf(
		`{"id":5,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"m1","attachment":{"file_id":%q}}}`, chatID, sentID))
	continueWith(6, "sent.bin", 4, mime, sentID)
	c.expectErr(6, protocol.ErrNotFound)

	// Declared and swept before it finished.
	sweptID, _, _ := declare(t, c, 7, "swept.bin", 10, mime, "")
	if err := srv.sweepOrphans(t.Context(), time.Now().Add(time.Hour).Unix()); err != nil {
		t.Fatalf("sweep: %v", err)
	}
	continueWith(8, "swept.bin", 10, mime, sweptID)
	c.expectErr(8, protocol.ErrNotFound)

	// The same id with another file's metadata.
	liveID, _, _ := declare(t, c, 9, "live.bin", 10, mime, "")
	continueWith(10, "live.bin", 11, mime, liveID)
	c.expectErr(10, protocol.ErrInvalidRequest)
	continueWith(11, "other.bin", 10, mime, liveID)
	c.expectErr(11, protocol.ErrInvalidRequest)
	continueWith(12, "live.bin", 10, "text/plain", liveID)
	c.expectErr(12, protocol.ErrInvalidRequest)
}

func TestAStalledUploadIsCutAndKeepsWhatArrived(t *testing.T) {
	ts, srv, closeAll := openStack(t, filepath.Join(t.TempDir(), "stall.db"), nil, func(s *Server) {
		s.stallTimeout = 300 * time.Millisecond
	})
	t.Cleanup(closeAll)
	c := greeted(t, ts, srv)

	payload := randomPayload(t, 100000)
	fileID, token, _ := declare(t, c, 3, "stall.bin", len(payload), "application/octet-stream", "")
	put := openRawPut(t, ts, token, len(payload))
	put.send(payload[:50000])
	// And then nothing: the server gives up on its own and says so.
	if code := put.status(5 * time.Second); code != http.StatusRequestTimeout {
		t.Fatalf("stalled PUT = %d, want 408", code)
	}
	waitIdle(t, srv, fileID)

	_, token2, received := declare(t, c, 4, "stall.bin", len(payload), "application/octet-stream", fileID)
	if received != 50000 {
		t.Fatalf("received = %d, want the 50000 that arrived before the stall", received)
	}
	if code := putBytes(t, ts, token2, payload[received:]); code != http.StatusNoContent {
		t.Fatalf("PUT of the rest = %d", code)
	}
	if !bytes.Equal(diskBytes(t, srv, fileID), payload) {
		t.Fatal("the finished file is not the bytes that were sent")
	}
}

func TestASlowButMovingUploadIsNeverCut(t *testing.T) {
	ts, srv, closeAll := openStack(t, filepath.Join(t.TempDir(), "slow.db"), nil, func(s *Server) {
		s.stallTimeout = 200 * time.Millisecond
	})
	t.Cleanup(closeAll)
	c := greeted(t, ts, srv)

	payload := randomPayload(t, 160<<10)
	fileID, token, _ := declare(t, c, 3, "slow.bin", len(payload), "application/octet-stream", "")
	// Twenty pauses of 50 ms: a second in all, five stall timeouts long, and
	// never 200 ms without a byte.
	req, err := http.NewRequest(http.MethodPut, ts.URL+"/files/"+token,
		&slowReader{data: payload, chunk: 8 << 10, every: 50 * time.Millisecond})
	if err != nil {
		t.Fatalf("build PUT: %v", err)
	}
	req.ContentLength = int64(len(payload))
	start := time.Now()
	resp, err := ts.Client().Do(req)
	if err != nil {
		t.Fatalf("PUT: %v", err)
	}
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("slow PUT = %d after %v, want 204", resp.StatusCode, time.Since(start))
	}
	if !bytes.Equal(diskBytes(t, srv, fileID), payload) {
		t.Fatal("the finished file is not the bytes that were sent")
	}
}

func TestAHangingUploadGivesWayToItsContinuation(t *testing.T) {
	ts, srv, closeAll := openStack(t, filepath.Join(t.TempDir(), "hang.db"), nil, func(s *Server) {
		// Long enough that only the continuation can end the hanging request.
		s.stallTimeout = time.Minute
	})
	t.Cleanup(closeAll)
	c := greeted(t, ts, srv)

	payload := randomPayload(t, 200000)
	fileID, token, _ := declare(t, c, 3, "hang.bin", len(payload), "application/octet-stream", "")
	put := openRawPut(t, ts, token, len(payload))
	put.send(payload[:70000])
	waitPart(t, srv, fileID, 70000)

	start := time.Now()
	_, token2, received := declare(t, c, 4, "hang.bin", len(payload), "application/octet-stream", fileID)
	if waited := time.Since(start); waited > srv.continuationWait+2*time.Second {
		t.Fatalf("the continuation took %v", waited)
	}
	if received != 70000 {
		t.Fatalf("received = %d, want all 70000 the hanging request took in", received)
	}
	if code := put.status(5 * time.Second); code != http.StatusConflict {
		t.Fatalf("the superseded PUT = %d, want 409", code)
	}
	if code := putBytes(t, ts, token2, payload[received:]); code != http.StatusNoContent {
		t.Fatalf("PUT of the rest = %d", code)
	}
	if !bytes.Equal(diskBytes(t, srv, fileID), payload) {
		t.Fatal("the finished file is not the bytes that were sent")
	}
}

func TestAWriterThatWillNotLetGoNeitherDelaysNorFailsTheContinuation(t *testing.T) {
	ts, srv, closeAll := openStack(t, filepath.Join(t.TempDir(), "stuck.db"), nil, func(s *Server) {
		s.continuationWait = 200 * time.Millisecond
		s.preemptWait = 200 * time.Millisecond
	})
	t.Cleanup(closeAll)
	c := greeted(t, ts, srv)

	payload := randomPayload(t, 100000)
	fileID, token, _ := declare(t, c, 3, "stuck.bin", len(payload), "application/octet-stream", "")
	cutAfter(t, ts, srv, fileID, token, payload, 30000)

	// A writer that ignores its interrupt - stuck in a disk write, say.
	stuck, ok := srv.writers.take(fileID, func() {}, time.Second)
	if !ok {
		t.Fatal("could not plant the stuck writer")
	}

	start := time.Now()
	_, token2, received := declare(t, c, 4, "stuck.bin", len(payload), "application/octet-stream", fileID)
	if waited := time.Since(start); waited < srv.continuationWait || waited > srv.continuationWait+2*time.Second {
		t.Fatalf("the continuation answered after %v, want its %v wait", waited, srv.continuationWait)
	}
	if received != 30000 {
		t.Fatalf("received = %d, want the 30000 durable bytes", received)
	}
	// The PUT cannot write beside it, and says so.
	if code := putBytes(t, ts, token2, payload[received:]); code != http.StatusConflict {
		t.Fatalf("PUT beside a stuck writer = %d, want 409", code)
	}

	stuck()
	_, token3, received := declare(t, c, 5, "stuck.bin", len(payload), "application/octet-stream", fileID)
	if code := putBytes(t, ts, token3, payload[received:]); code != http.StatusNoContent {
		t.Fatalf("PUT after the writer let go = %d", code)
	}
	if !bytes.Equal(diskBytes(t, srv, fileID), payload) {
		t.Fatal("the finished file is not the bytes that were sent")
	}
}

func TestAnUploadMakesWhatItReceivedDurableAsItGoes(t *testing.T) {
	ts, srv, closeAll := openStack(t, filepath.Join(t.TempDir(), "checkpoint.db"), nil, func(s *Server) {
		s.checkpointBytes = 64 << 10
		s.stallTimeout = time.Minute
	})
	t.Cleanup(closeAll)
	c := greeted(t, ts, srv)

	payload := randomPayload(t, 1<<20)
	fileID, token, _ := declare(t, c, 3, "durable.bin", len(payload), "application/octet-stream", "")
	put := openRawPut(t, ts, token, len(payload))
	put.send(payload[:200<<10])
	waitPart(t, srv, fileID, 200<<10)

	// Still mid-request - and already durable well past the first steps.
	deadline := time.Now().Add(5 * time.Second)
	for {
		durable, err := srv.blob.Received(fileID)
		if err != nil {
			t.Fatalf("Received: %v", err)
		}
		if durable >= 128<<10 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("only %d bytes durable while the request runs, want at least two 64 KiB steps", durable)
		}
		time.Sleep(5 * time.Millisecond)
	}
	if !writing(srv, fileID) {
		t.Fatal("the request ended; the checkpoints were to be seen while it ran")
	}
	put.breakOff()
	waitIdle(t, srv, fileID)
}

func TestTooManyBytesRollBackAndTooFewAreKept(t *testing.T) {
	ts, srv := newTestServer(t)
	c := greeted(t, ts, srv)
	const mime = "application/octet-stream"

	payload := randomPayload(t, 1000)
	fileID, token, _ := declare(t, c, 3, "edge.bin", len(payload), mime, "")
	cutAfter(t, ts, srv, fileID, token, payload, 400)

	// 700 bytes where 600 remain: nothing this request carried is kept, and
	// the 400 before it stay.
	_, token, received := declare(t, c, 4, "edge.bin", len(payload), mime, fileID)
	if received != 400 {
		t.Fatalf("received = %d, want 400", received)
	}
	if code := putBytes(t, ts, token, randomPayload(t, 700)); code != http.StatusRequestEntityTooLarge {
		t.Fatalf("oversized PUT = %d, want 413", code)
	}
	_, token, received = declare(t, c, 5, "edge.bin", len(payload), mime, fileID)
	if received != 400 {
		t.Fatalf("received after 413 = %d, want the 400 from before it", received)
	}

	// 100 bytes where 600 remain, and the body ends cleanly: they are kept.
	if code := putBytes(t, ts, token, payload[400:500]); code != http.StatusBadRequest {
		t.Fatalf("short PUT = %d, want 400", code)
	}
	_, token, received = declare(t, c, 6, "edge.bin", len(payload), mime, fileID)
	if received != 500 {
		t.Fatalf("received after the short PUT = %d, want 500", received)
	}
	if code := putBytes(t, ts, token, payload[500:]); code != http.StatusNoContent {
		t.Fatalf("PUT of the rest = %d", code)
	}
	if !bytes.Equal(diskBytes(t, srv, fileID), payload) {
		t.Fatal("the finished file is not the bytes that were sent")
	}
}

func TestAPutPastWhatIsStillOnDiskIsRefused(t *testing.T) {
	ts, srv := newTestServer(t)
	c := greeted(t, ts, srv)

	payload := randomPayload(t, 1000)
	fileID, token, _ := declare(t, c, 3, "gone.bin", len(payload), "application/octet-stream", "")
	cutAfter(t, ts, srv, fileID, token, payload, 400)
	_, token, received := declare(t, c, 4, "gone.bin", len(payload), "application/octet-stream", fileID)
	if received != 400 {
		t.Fatalf("received = %d, want 400", received)
	}
	// Between the answer and the PUT, the part lost bytes the token counts on.
	if err := os.Truncate(partPath(srv, fileID), 100); err != nil {
		t.Fatalf("truncate: %v", err)
	}
	if code := putBytes(t, ts, token, payload[400:]); code != http.StatusNotFound {
		t.Fatalf("PUT past the bytes on disk = %d, want 404", code)
	}
}

func TestAnUnfinishedUploadSurvivesARestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "restart.db")
	ts, srv, closeAll := openStack(t, path, nil)
	firstClosed := false
	t.Cleanup(func() {
		if !firstClosed {
			closeAll()
		}
	})
	c := greeted(t, ts, srv)
	payload := randomPayload(t, 300000)
	fileID, token, _ := declare(t, c, 3, "keep.bin", len(payload), "application/octet-stream", "")
	cutAfter(t, ts, srv, fileID, token, payload, 120000)
	_ = c.conn.Close(websocket.StatusNormalClosure, "restarting")
	closeAll()
	firstClosed = true

	// A new process over the same database and files: the tokens are gone,
	// the part and its record are not.
	ts2, srv2, closeAll2 := openStack(t, path, nil)
	t.Cleanup(closeAll2)
	c2 := greeted(t, ts2, srv2)
	_, token2, received := declare(t, c2, 3, "keep.bin", len(payload), "application/octet-stream", fileID)
	if received != 120000 {
		t.Fatalf("received after the restart = %d, want 120000", received)
	}
	if code := putBytes(t, ts2, token2, payload[received:]); code != http.StatusNoContent {
		t.Fatalf("PUT of the rest = %d", code)
	}
	if !bytes.Equal(diskBytes(t, srv2, fileID), payload) {
		t.Fatal("the finished file is not the bytes that were sent")
	}
}

func TestTheFileNameNeverReachesTheLog(t *testing.T) {
	buf := &syncBuffer{}
	ts, srv, closeAll := openStack(t, filepath.Join(t.TempDir(), "log.db"), slog.New(slog.NewJSONHandler(buf, nil)), func(s *Server) {
		s.stallTimeout = 300 * time.Millisecond
	})
	t.Cleanup(closeAll)
	c := greeted(t, ts, srv)

	const name = "secret-holiday-video.mp4"
	payload := randomPayload(t, 50000)
	fileID, token, _ := declare(t, c, 3, name, len(payload), "video/mp4", "")
	cutAfter(t, ts, srv, fileID, token, payload, 10000)
	_, token, received := declare(t, c, 4, name, len(payload), "video/mp4", fileID)
	stalled := openRawPut(t, ts, token, len(payload)-int(received))
	stalled.send(payload[received : received+5000])
	if code := stalled.status(5 * time.Second); code != http.StatusRequestTimeout {
		t.Fatalf("stalled PUT = %d", code)
	}
	waitIdle(t, srv, fileID)
	_, token, received = declare(t, c, 5, name, len(payload), "video/mp4", fileID)
	if code := putBytes(t, ts, token, payload[received:]); code != http.StatusNoContent {
		t.Fatalf("PUT of the rest = %d", code)
	}

	log := buf.String()
	if !strings.Contains(log, "upload resumed") || !strings.Contains(log, "upload stalled") {
		t.Fatalf("the transfers were not logged at all:\n%s", log)
	}
	if strings.Contains(log, "secret-holiday") {
		t.Fatalf("the file's name reached the log:\n%s", log)
	}
}

// storeFile puts a finished, unbound file straight into the store and the
// files directory, the way an upload would have left it.
func storeFile(t *testing.T, srv *Server, payload []byte) string {
	t.Helper()
	att, err := srv.store.CreateUpload(t.Context(), "big.bin", int64(len(payload)), "application/octet-stream", time.Now().Unix())
	if err != nil {
		t.Fatalf("CreateUpload: %v", err)
	}
	up, err := srv.blob.Create(att.FileID)
	if err != nil {
		t.Fatalf("blob.Create: %v", err)
	}
	if _, err := up.Write(payload); err != nil {
		t.Fatalf("write: %v", err)
	}
	if err := up.Finalize(); err != nil {
		t.Fatalf("finalize: %v", err)
	}
	if err := srv.store.MarkUploaded(t.Context(), att.FileID); err != nil {
		t.Fatalf("MarkUploaded: %v", err)
	}
	return att.FileID
}

func TestASlowButMovingDownloadIsNeverCut(t *testing.T) {
	ts, srv, closeAll := openStack(t, filepath.Join(t.TempDir(), "slowget.db"), nil, func(s *Server) {
		s.stallTimeout = 300 * time.Millisecond
	})
	t.Cleanup(closeAll)
	c := greeted(t, ts, srv)

	payload := randomPayload(t, 16<<20)
	fileID := storeFile(t, srv, payload)
	token := downloadBegin(t, c, 3, fileID)
	resp, err := ts.Client().Get(ts.URL + "/files/" + token)
	if err != nil {
		t.Fatalf("GET: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()

	// Half a megabyte at a time with a pause between: far longer in all than
	// the stall timeout, never that long without a byte taken.
	var got bytes.Buffer
	chunk := make([]byte, 512<<10)
	for {
		n, err := io.ReadFull(resp.Body, chunk)
		got.Write(chunk[:n])
		if errors.Is(err, io.EOF) || errors.Is(err, io.ErrUnexpectedEOF) {
			break
		}
		if err != nil {
			t.Fatalf("read after %d bytes: %v", got.Len(), err)
		}
		time.Sleep(100 * time.Millisecond)
	}
	if !bytes.Equal(got.Bytes(), payload) {
		t.Fatalf("got %d bytes, want the whole %d", got.Len(), len(payload))
	}
}

func TestADownloadWhoseReaderStoppedIsCut(t *testing.T) {
	ts, srv, closeAll := openStack(t, filepath.Join(t.TempDir(), "stopget.db"), nil, func(s *Server) {
		s.stallTimeout = 300 * time.Millisecond
	})
	t.Cleanup(closeAll)
	c := greeted(t, ts, srv)

	// Larger than what the socket buffers on both ends can hold, so the
	// server is left waiting to write.
	payload := randomPayload(t, 32<<20)
	fileID := storeFile(t, srv, payload)
	token := downloadBegin(t, c, 3, fileID)
	resp, err := ts.Client().Get(ts.URL + "/files/" + token)
	if err != nil {
		t.Fatalf("GET: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()

	head := make([]byte, 64<<10)
	if _, err := io.ReadFull(resp.Body, head); err != nil {
		t.Fatalf("read the first bytes: %v", err)
	}
	time.Sleep(2 * time.Second)
	rest, err := io.ReadAll(resp.Body)
	if err == nil && len(head)+len(rest) == len(payload) {
		t.Fatal("the whole file arrived after the reader stood still past the stall timeout")
	}
}

func TestIfRangeContinuesTheSameFileAndRestartsAnother(t *testing.T) {
	ts, srv := newTestServer(t)
	c := greeted(t, ts, srv)

	payload := randomPayload(t, 1000)
	fileID := storeFile(t, srv, payload)

	code, full, hdr := doGet(t, ts, downloadBegin(t, c, 3, fileID), "")
	if code != http.StatusOK || !bytes.Equal(full, payload) {
		t.Fatalf("first GET = %d, %d bytes", code, len(full))
	}
	validator := hdr.Get("Last-Modified")
	if validator == "" {
		t.Fatal("no Last-Modified: a client would have nothing to continue against")
	}

	get := func(id int, ifRange string) (int, []byte, http.Header) {
		req, err := http.NewRequest(http.MethodGet, ts.URL+"/files/"+downloadBegin(t, c, id, fileID), nil)
		if err != nil {
			t.Fatalf("build GET: %v", err)
		}
		req.Header.Set("Range", "bytes=100-")
		req.Header.Set("If-Range", ifRange)
		resp, err := ts.Client().Do(req)
		if err != nil {
			t.Fatalf("GET: %v", err)
		}
		defer func() { _ = resp.Body.Close() }()
		body, err := io.ReadAll(resp.Body)
		if err != nil {
			t.Fatalf("read: %v", err)
		}
		return resp.StatusCode, body, resp.Header
	}

	code, rest, hdr := get(4, validator)
	if code != http.StatusPartialContent || !bytes.Equal(rest, payload[100:]) {
		t.Fatalf("GET with the same validator = %d, %d bytes; want 206 and the rest", code, len(rest))
	}
	if cr := hdr.Get("Content-Range"); cr != "bytes 100-999/1000" {
		t.Fatalf("Content-Range = %q", cr)
	}

	code, whole, _ := get(5, "Mon, 02 Jan 2006 15:04:05 GMT")
	if code != http.StatusOK || !bytes.Equal(whole, payload) {
		t.Fatalf("GET with another validator = %d, %d bytes; want 200 and the whole file", code, len(whole))
	}
}
