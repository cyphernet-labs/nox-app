package server

import (
	"bufio"
	"bytes"
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/coder/websocket"

	"nox.app/client-backend/internal/blob"
	"nox.app/client-backend/internal/protocol"
)

// Feature 043: an upload continues where it broke off, and no transfer is cut
// for taking long - only for standing still.
//
// Since 047 the bytes go to disk in sealed chunks of 64 KiB (blob.ChunkSize):
// an upload continues from the start of the chunk it broke off in, because a
// chunk is sealed only once all of it arrived and the rest of one goes with
// the request that carried it.

// chunk is one sealed chunk's worth of plaintext.
const chunk = blob.ChunkSize

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

// rawPut is a PUT driven by hand over its own channel. The standard client
// cannot stop half-way, hold a connection open without sending, or break one
// on purpose - and those are exactly the cases at stake here.
type rawPut struct {
	t    *testing.T
	conn *tls.Conn
	br   *bufio.Reader
}

// openRawPut sends the head of a PUT as the device that last greeted - a
// transfer needs a paired key on the connection as well as the token.
func openRawPut(t *testing.T, ts *httptest.Server, token string, contentLength int) *rawPut {
	t.Helper()
	dev, err := channelOf(t, ts).devices.current()
	if err != nil {
		t.Fatalf("pick a device: %v", err)
	}
	return openRawPutAs(t, ts, dev, token, contentLength)
}

// openRawPutAs is openRawPut as dev, whichever device greeted last.
func openRawPutAs(t *testing.T, ts *httptest.Server, dev *device, token string, contentLength int) *rawPut {
	t.Helper()
	ch := channelOf(t, ts)
	conn, err := dialChannel(t.Context(), ch.addr, ch.serverKey, dev.priv)
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

// expectCut fails the test unless the server ends the connection within d
// having said nothing more: no response, not even an error status.
func (p *rawPut) expectCut(d time.Duration) {
	p.t.Helper()
	if err := p.conn.SetReadDeadline(time.Now().Add(d)); err != nil {
		p.t.Fatalf("set deadline: %v", err)
	}
	n, err := p.br.Read(make([]byte, 1))
	var ne net.Error
	switch {
	case n > 0:
		p.t.Fatal("the server answered on a connection it was to cut")
	case errors.As(err, &ne) && ne.Timeout():
		p.t.Fatalf("the connection was still open %v later", d)
	case err == nil:
		p.t.Fatal("a read returned neither bytes nor an error")
	}
}

func partPath(srv *Server, fileID string) string {
	return filepath.Join(srv.cfg.FilesPath, fileID+".part")
}

// waitPart waits until fileID's part holds the first n bytes of the file
// sealed - every whole chunk of them. The rest of a chunk is in the memory of
// the request, and nothing on disk says it arrived.
func waitPart(t *testing.T, srv *Server, fileID string, n int64) {
	t.Helper()
	want := blob.CipherLen(n / chunk * chunk)
	deadline := time.Now().Add(5 * time.Second)
	for {
		if info, err := os.Stat(partPath(srv, fileID)); err == nil && info.Size() >= want {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("the server never sealed the chunks of the first %d bytes of %s", n, fileID)
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
// breaks off once the whole chunks among them are sealed, returning once the
// server has let go of the file. What is left of the chunk the break fell in
// is lost with the request: the next one starts at that chunk.
func cutAfter(t *testing.T, ts *httptest.Server, srv *Server, fileID, token string, payload []byte, n int) {
	t.Helper()
	put := openRawPut(t, ts, token, len(payload))
	put.send(payload[:n])
	waitPart(t, srv, fileID, int64(n))
	put.breakOff()
	waitIdle(t, srv, fileID)
}

// diskBytes reads fileID's finished file back through the store - the
// plaintext its sealed chunks open to.
func diskBytes(t *testing.T, srv *Server, fileID string) []byte {
	t.Helper()
	info, err := srv.store.FileByID(t.Context(), fileID)
	if err != nil {
		t.Fatalf("FileByID: %v", err)
	}
	r, err := srv.blob.Open(fileID, info.Attachment.Size)
	if err != nil {
		t.Fatalf("open finished bytes: %v", err)
	}
	defer func() { _ = r.Close() }()
	data, err := io.ReadAll(r)
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

	payload := randomPayload(t, 5*chunk+777)
	fileID, token, received := declare(t, c, 3, "trip.mp4", len(payload), "video/mp4", "")
	if received != 0 {
		t.Fatalf("a new upload answers received=%d, want 0", received)
	}

	// The break falls in the middle of the third chunk.
	cutAfter(t, ts, srv, fileID, token, payload, 2*chunk+1234)

	again, token2, received := declare(t, c, 4, "trip.mp4", len(payload), "video/mp4", fileID)
	if again != fileID {
		t.Fatalf("the continuation answers %q, want the same file %q", again, fileID)
	}
	if received != 2*chunk {
		t.Fatalf("received = %d, want the %d bytes of the two chunks sealed before the break", received, 2*chunk)
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

	payload := randomPayload(t, chunk+1000)
	fileID, _, _ := declare(t, c, 3, "whole.bin", len(payload), "application/octet-stream", "")
	// Every byte arrived and was made durable - the shorter last chunk sealed
	// with the file's last byte - and then the process died before the part
	// became the file.
	up, err := srv.blob.Create(fileID, int64(len(payload)))
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

	payload := randomPayload(t, 3*chunk)
	fileID, token, _ := declare(t, c, 3, "stall.bin", len(payload), "application/octet-stream", "")
	put := openRawPut(t, ts, token, len(payload))
	put.send(payload[:chunk+5000])
	// And then nothing: the server gives up on its own and says so.
	if code := put.status(5 * time.Second); code != http.StatusRequestTimeout {
		t.Fatalf("stalled PUT = %d, want 408", code)
	}
	waitIdle(t, srv, fileID)

	_, token2, received := declare(t, c, 4, "stall.bin", len(payload), "application/octet-stream", fileID)
	if received != chunk {
		t.Fatalf("received = %d, want the one chunk sealed before the stall", received)
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
		// Nor by the deadline on a body nothing reads (boundRequestBody):
		// the handler reads this one, under deadlines of its own.
		s.bodyTimeout = 100 * time.Millisecond
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

	payload := randomPayload(t, 4*chunk)
	fileID, token, _ := declare(t, c, 3, "hang.bin", len(payload), "application/octet-stream", "")
	put := openRawPut(t, ts, token, len(payload))
	put.send(payload[:2*chunk+500])
	waitPart(t, srv, fileID, 2*chunk)

	start := time.Now()
	_, token2, received := declare(t, c, 4, "hang.bin", len(payload), "application/octet-stream", fileID)
	if waited := time.Since(start); waited > srv.continuationWait+2*time.Second {
		t.Fatalf("the continuation took %v", waited)
	}
	if received != 2*chunk {
		t.Fatalf("received = %d, want both chunks the hanging request sealed", received)
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

	payload := randomPayload(t, 3*chunk)
	fileID, token, _ := declare(t, c, 3, "stuck.bin", len(payload), "application/octet-stream", "")
	cutAfter(t, ts, srv, fileID, token, payload, chunk+3000)

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
	if received != chunk {
		t.Fatalf("received = %d, want the durable chunk", received)
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
	waitPart(t, srv, fileID, 3*chunk)

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

	payload := randomPayload(t, 4*chunk+1000)
	fileID, token, _ := declare(t, c, 3, "edge.bin", len(payload), mime, "")
	cutAfter(t, ts, srv, fileID, token, payload, 2*chunk+400)

	// 100 bytes more than remain: nothing this request carried is kept, and
	// the two chunks before it stay.
	_, token, received := declare(t, c, 4, "edge.bin", len(payload), mime, fileID)
	if received != 2*chunk {
		t.Fatalf("received = %d, want %d", received, 2*chunk)
	}
	if code := putBytes(t, ts, token, randomPayload(t, len(payload)-2*chunk+100)); code != http.StatusRequestEntityTooLarge {
		t.Fatalf("oversized PUT = %d, want 413", code)
	}
	_, token, received = declare(t, c, 5, "edge.bin", len(payload), mime, fileID)
	if received != 2*chunk {
		t.Fatalf("received after 413 = %d, want the %d from before it", received, 2*chunk)
	}

	// A chunk and 100 bytes where more remain, and the body ends cleanly: the
	// whole chunk is kept, the 100 bytes of the next one go with the request.
	if code := putBytes(t, ts, token, payload[2*chunk:3*chunk+100]); code != http.StatusBadRequest {
		t.Fatalf("short PUT = %d, want 400", code)
	}
	_, token, received = declare(t, c, 6, "edge.bin", len(payload), mime, fileID)
	if received != 3*chunk {
		t.Fatalf("received after the short PUT = %d, want %d", received, 3*chunk)
	}
	if code := putBytes(t, ts, token, payload[received:]); code != http.StatusNoContent {
		t.Fatalf("PUT of the rest = %d", code)
	}
	if !bytes.Equal(diskBytes(t, srv, fileID), payload) {
		t.Fatal("the finished file is not the bytes that were sent")
	}
}

func TestAPutPastWhatIsStillOnDiskIsRefused(t *testing.T) {
	ts, srv := newTestServer(t)
	c := greeted(t, ts, srv)

	payload := randomPayload(t, 4*chunk)
	fileID, token, _ := declare(t, c, 3, "gone.bin", len(payload), "application/octet-stream", "")
	cutAfter(t, ts, srv, fileID, token, payload, 2*chunk+400)
	_, token, received := declare(t, c, 4, "gone.bin", len(payload), "application/octet-stream", fileID)
	if received != 2*chunk {
		t.Fatalf("received = %d, want %d", received, 2*chunk)
	}
	// Between the answer and the PUT, the part lost a chunk the token counts
	// on.
	if err := os.Truncate(partPath(srv, fileID), blob.CipherLen(chunk)+100); err != nil {
		t.Fatalf("truncate: %v", err)
	}
	if code := putBytes(t, ts, token, payload[received:]); code != http.StatusNotFound {
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
	payload := randomPayload(t, 5*chunk)
	fileID, token, _ := declare(t, c, 3, "keep.bin", len(payload), "application/octet-stream", "")
	cutAfter(t, ts, srv, fileID, token, payload, 2*chunk+1000)
	_ = c.conn.Close(websocket.StatusNormalClosure, "restarting")
	closeAll()
	firstClosed = true

	// A new process over the same database and files: the tokens are gone,
	// the part and its record are not.
	ts2, srv2, closeAll2 := openStack(t, path, nil)
	t.Cleanup(closeAll2)
	c2 := greeted(t, ts2, srv2)
	_, token2, received := declare(t, c2, 3, "keep.bin", len(payload), "application/octet-stream", fileID)
	if received != 2*chunk {
		t.Fatalf("received after the restart = %d, want %d", received, 2*chunk)
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
	payload := randomPayload(t, 3*chunk)
	fileID, token, _ := declare(t, c, 3, name, len(payload), "video/mp4", "")
	cutAfter(t, ts, srv, fileID, token, payload, chunk+100)
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
	up, err := srv.blob.Create(att.FileID, int64(len(payload)))
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
		// Nor by the deadline on a body nothing reads (boundRequestBody): a
		// GET has none, and net/http lifts the deadline to watch for the
		// peer hanging up while the handler writes.
		s.bodyTimeout = 100 * time.Millisecond
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

// --- the edges of a finished upload ---

// holdAfterFinalize stops every upload between the rename that makes its part
// the file and the commit that tells the database so, until let is called:
// the window a client hanging up, a continuation or a crash lands in.
func holdAfterFinalize(t *testing.T) (tweak func(*Server), finalized <-chan string, let func()) {
	t.Helper()
	reached := make(chan string, 1)
	release := make(chan struct{})
	let = sync.OnceFunc(func() { close(release) })
	// Released before the stack closes, or a held request would hold its
	// shutdown too.
	t.Cleanup(let)
	return func(s *Server) {
		s.afterFinalize = func(fileID string) {
			reached <- fileID
			<-release
		}
	}, reached, let
}

func waitFinalized(t *testing.T, finalized <-chan string) {
	t.Helper()
	select {
	case <-finalized:
	case <-time.After(5 * time.Second):
		t.Fatal("the upload never got as far as its commit")
	}
}

func isUploaded(t *testing.T, srv *Server, fileID string) bool {
	t.Helper()
	info, err := srv.store.FileByID(t.Context(), fileID)
	if err != nil {
		t.Fatalf("FileByID: %v", err)
	}
	return info.Uploaded
}

// putChunked is putBytes with no declared length: the body goes chunked, and
// only reading it tells how long it is.
func putChunked(t *testing.T, ts *httptest.Server, token string, payload []byte) int {
	t.Helper()
	req, err := http.NewRequest(http.MethodPut, ts.URL+"/files/"+token, io.MultiReader(bytes.NewReader(payload)))
	if err != nil {
		t.Fatalf("build PUT: %v", err)
	}
	req.ContentLength = -1
	resp, err := ts.Client().Do(req)
	if err != nil {
		t.Fatalf("PUT: %v", err)
	}
	_, _ = io.Copy(io.Discard, resp.Body)
	_ = resp.Body.Close()
	return resp.StatusCode
}

func TestAClientThatHangsUpAfterItsLastByteStillHasItsFile(t *testing.T) {
	hold, finalized, let := holdAfterFinalize(t)
	ts, srv, closeAll := openStack(t, filepath.Join(t.TempDir(), "hangup.db"), nil, hold)
	t.Cleanup(closeAll)
	c := greeted(t, ts, srv)
	chatID := seedChat(t, c, "hangup")

	payload := randomPayload(t, 100000)
	fileID, token, _ := declare(t, c, 3, "last.bin", len(payload), "application/octet-stream", "")
	put := openRawPut(t, ts, token, len(payload))
	put.send(payload)
	waitFinalized(t, finalized)
	// Every byte is in and the part is the file; the client goes before the
	// answer comes. net/http, reading the connection for a next request by
	// now, sees it close and cancels the request's context.
	put.breakOff()
	time.Sleep(200 * time.Millisecond)
	let()
	waitIdle(t, srv, fileID)

	if !isUploaded(t, srv, fileID) {
		t.Fatal("every byte is on disk and the row does not know it: the commit died with the request")
	}
	c.expectOKAfter(4, fmt.Sprintf(
		`{"id":4,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"m1","attachment":{"file_id":%q}}}`, chatID, fileID))
}

func TestAContinuationBetweenTheLastByteAndTheCommitFindsTheFileWhole(t *testing.T) {
	hold, finalized, let := holdAfterFinalize(t)
	ts, srv, closeAll := openStack(t, filepath.Join(t.TempDir(), "between.db"), nil, hold, func(s *Server) {
		// Longer than the hold: what is asserted is what the continuation
		// answers once the writer let go, not what its timeout makes of it.
		s.continuationWait = 5 * time.Second
	})
	t.Cleanup(closeAll)
	c := greeted(t, ts, srv)

	payload := randomPayload(t, 100000)
	fileID, token, _ := declare(t, c, 3, "whole.bin", len(payload), "application/octet-stream", "")
	put := openRawPut(t, ts, token, len(payload))
	put.send(payload)
	waitFinalized(t, finalized)

	// The client's watch fired as the last byte left: it asks how much the
	// server holds while the request is between that byte and its commit.
	c.send(fmt.Sprintf(`{"id":4,"cmd":"file.uploadBegin","data":{"name":"whole.bin","size":%d,"mime":"application/octet-stream","file_id":%q}}`,
		len(payload), fileID))
	time.Sleep(200 * time.Millisecond)
	let()

	var received int64
	mustUnmarshal(t, c.expectOK(4)["received"], &received)
	if received != int64(len(payload)) {
		t.Fatalf("received = %d, want all %d: the whole file would go up again", received, len(payload))
	}
	if code := put.status(5 * time.Second); code != http.StatusNoContent {
		t.Fatalf("the PUT that delivered every byte = %d, want 204", code)
	}
	if !isUploaded(t, srv, fileID) {
		t.Fatal("the file is whole and the row does not know it")
	}
}

func TestAWholeFileTheCommitNeverReachedIsFinishedByAnEmptyPut(t *testing.T) {
	ts, srv := newTestServer(t)
	c := greeted(t, ts, srv)
	chatID := seedChat(t, c, "crash")
	const mime = "application/octet-stream"

	payload := randomPayload(t, 5000)
	fileID, _, _ := declare(t, c, 3, "crash.bin", len(payload), mime, "")
	// Every byte arrived and the part became the file - and the process died
	// before the commit that says so.
	up, err := srv.blob.Create(fileID, int64(len(payload)))
	if err != nil {
		t.Fatalf("blob.Create: %v", err)
	}
	if _, err := up.Write(payload); err != nil {
		t.Fatalf("write: %v", err)
	}
	if err := up.Finalize(); err != nil {
		t.Fatalf("finalize: %v", err)
	}

	// A token from before the file was whole asks for bytes it no longer
	// lacks: refused, and the file is not written over.
	stale := srv.tokens.issue(fileID, opUpload, 0)
	if code := putBytes(t, ts, stale, randomPayload(t, len(payload))); code != http.StatusNotFound {
		t.Fatalf("PUT from the first byte of a whole file = %d, want 404", code)
	}
	if !bytes.Equal(diskBytes(t, srv, fileID), payload) {
		t.Fatal("the whole file was written over")
	}

	_, token, received := declare(t, c, 4, "crash.bin", len(payload), mime, fileID)
	if received != int64(len(payload)) {
		t.Fatalf("received = %d, want all %d: the bytes are whole on disk", received, len(payload))
	}
	if code := putBytes(t, ts, token, nil); code != http.StatusNoContent {
		t.Fatalf("empty PUT on a whole file = %d, want 204", code)
	}
	if !isUploaded(t, srv, fileID) {
		t.Fatal("the empty PUT did not land the commit")
	}
	c.expectOKAfter(5, fmt.Sprintf(
		`{"id":5,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"m1","attachment":{"file_id":%q}}}`, chatID, fileID))
}

func TestABodyDeclaredLongerThanTheRestIsRefusedBeforeAByteIsRead(t *testing.T) {
	ts, srv, closeAll := openStack(t, filepath.Join(t.TempDir(), "long.db"), nil, func(s *Server) {
		// Read instead of refused, the request would wait this long for a
		// body that never comes.
		s.stallTimeout = 30 * time.Second
	})
	t.Cleanup(closeAll)
	c := greeted(t, ts, srv)

	const size = 1 << 20
	fileID, token, _ := declare(t, c, 3, "long.bin", size, "application/octet-stream", "")
	// One byte more than the whole file, and not one of them sent.
	put := openRawPut(t, ts, token, size+1)
	if code := put.status(2 * time.Second); code != http.StatusRequestEntityTooLarge {
		t.Fatalf("PUT declared past the end = %d, want 413", code)
	}
	if _, err := os.Stat(partPath(srv, fileID)); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("the refused request left a part behind (stat err = %v)", err)
	}
}

func TestTooManyBytesInABodyOfNoDeclaredLengthRollBackPastItsCheckpoints(t *testing.T) {
	ts, srv, closeAll := openStack(t, filepath.Join(t.TempDir(), "chunked.db"), nil, func(s *Server) {
		// Small enough that the request makes its bytes durable before it
		// turns out to be too long.
		s.checkpointBytes = 1 << 10
	})
	t.Cleanup(closeAll)
	c := greeted(t, ts, srv)
	const mime = "application/octet-stream"

	payload := randomPayload(t, 4*chunk)
	fileID, token, _ := declare(t, c, 3, "chunked.bin", len(payload), mime, "")
	cutAfter(t, ts, srv, fileID, token, payload, chunk+100)
	_, token, received := declare(t, c, 4, "chunked.bin", len(payload), mime, fileID)
	if received != chunk {
		t.Fatalf("received = %d, want one chunk", received)
	}

	// Three chunks remain; this body carries two KiB more and says so
	// nowhere. Its chunks are sealed and made durable as they come - every
	// one of them, the file's last included - before it turns out too long.
	if code := putChunked(t, ts, token, randomPayload(t, 3*chunk+2<<10)); code != http.StatusRequestEntityTooLarge {
		t.Fatalf("oversized chunked PUT = %d, want 413", code)
	}
	_, token, received = declare(t, c, 5, "chunked.bin", len(payload), mime, fileID)
	if received != chunk {
		t.Fatalf("received after 413 = %d, want the chunk from before it: "+
			"the record still vouches for bytes of a request too long to be the file", received)
	}
	if code := putBytes(t, ts, token, payload[received:]); code != http.StatusNoContent {
		t.Fatalf("PUT of the rest = %d", code)
	}
	if !bytes.Equal(diskBytes(t, srv, fileID), payload) {
		t.Fatal("the finished file is not the bytes that were sent")
	}
}

func TestALatePutWithAnEarlierTokenCannotCutThePartBack(t *testing.T) {
	ts, srv := newTestServer(t)
	c := greeted(t, ts, srv)
	const mime = "application/octet-stream"

	payload := randomPayload(t, 6*chunk)
	fileID, token, _ := declare(t, c, 3, "late.bin", len(payload), mime, "")
	cutAfter(t, ts, srv, fileID, token, payload, 2*chunk+100)

	// Two continuations: the PUT on the first is held up on its way, so the
	// client asks again and goes on with the second.
	_, earlier, _ := declare(t, c, 4, "late.bin", len(payload), mime, fileID)
	_, later, received := declare(t, c, 5, "late.bin", len(payload), mime, fileID)
	put := openRawPut(t, ts, later, len(payload)-int(received))
	put.send(payload[received : 4*chunk+100])
	waitPart(t, srv, fileID, 4*chunk)
	put.breakOff()
	waitIdle(t, srv, fileID)

	// The first one arrives at last.
	if code := putBytes(t, ts, earlier, payload[2*chunk:]); code != http.StatusNotFound {
		t.Fatalf("PUT on a token the client asked past = %d, want 404", code)
	}
	if durable, err := srv.blob.Received(fileID); err != nil || durable != 4*chunk {
		t.Fatalf("the part holds %d durable bytes after the late PUT (err %v), want the four chunks the later one left", durable, err)
	}
}

func TestAPutThatWaitedForAFinishingWriterDoesNotWriteOverTheFile(t *testing.T) {
	ts, srv := newTestServer(t)
	c := greeted(t, ts, srv)

	payload := randomPayload(t, 5000)
	fileID, _, _ := declare(t, c, 3, "finishing.bin", len(payload), "application/octet-stream", "")

	// A writer with every byte in: interrupted, it still finishes - the part
	// becomes the file and the row says so - and only then lets go.
	interrupted := make(chan struct{}, 1)
	release, ok := srv.writers.take(fileID, func() {
		select {
		case interrupted <- struct{}{}:
		default:
		}
	}, time.Second)
	if !ok {
		t.Fatal("could not plant the finishing writer")
	}
	finished := make(chan error, 1)
	go func() {
		defer release()
		<-interrupted
		up, err := srv.blob.Create(fileID, int64(len(payload)))
		if err == nil {
			_, err = up.Write(payload)
		}
		if err == nil {
			err = up.Finalize()
		}
		if err == nil {
			err = srv.store.MarkUploaded(context.Background(), fileID)
		}
		finished <- err
	}()

	// A token from the first byte, issued while the file was still being
	// written: the continuation that issued it had waited its second and
	// answered with what was durable then.
	token := srv.tokens.issue(fileID, opUpload, 0)
	if code := putBytes(t, ts, token, randomPayload(t, len(payload))); code != http.StatusNotFound {
		t.Fatalf("PUT that waited for the writer that finished the file = %d, want 404", code)
	}
	if err := <-finished; err != nil {
		t.Fatalf("the planted writer failed to finish: %v", err)
	}
	if !bytes.Equal(diskBytes(t, srv, fileID), payload) {
		t.Fatal("the finished file was written over")
	}
}

func TestADiskThatFailsMidUploadKeepsWhatWasAlreadyDurable(t *testing.T) {
	ts, srv, closeAll := openStack(t, filepath.Join(t.TempDir(), "disk.db"), nil, func(s *Server) {
		s.checkpointBytes = 1 << 10
	})
	t.Cleanup(closeAll)
	c := greeted(t, ts, srv)
	const mime = "application/octet-stream"

	payload := randomPayload(t, 4*chunk)
	fileID, token, _ := declare(t, c, 3, "disk.bin", len(payload), mime, "")
	cutAfter(t, ts, srv, fileID, token, payload, chunk+100)

	// The disk refuses the next record: where its temporary file goes, there
	// is a directory.
	blocker := filepath.Join(srv.cfg.FilesPath, fileID+".synced.tmp")
	if err := os.Mkdir(blocker, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	_, token, received := declare(t, c, 4, "disk.bin", len(payload), mime, fileID)
	if code := putBytes(t, ts, token, payload[received:]); code != http.StatusInternalServerError {
		t.Fatalf("PUT the disk refused = %d, want 500", code)
	}
	if err := os.Remove(blocker); err != nil && !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("remove: %v", err)
	}

	_, token, received = declare(t, c, 5, "disk.bin", len(payload), mime, fileID)
	if received != chunk {
		t.Fatalf("received after a storage failure = %d, want the chunk durable before it", received)
	}
	if code := putBytes(t, ts, token, payload[received:]); code != http.StatusNoContent {
		t.Fatalf("PUT of the rest = %d", code)
	}
	if !bytes.Equal(diskBytes(t, srv, fileID), payload) {
		t.Fatal("the finished file is not the bytes that were sent")
	}
}

func TestAnyByteSentToAFinishedUploadIsRefused(t *testing.T) {
	ts, srv := newTestServer(t)
	c := greeted(t, ts, srv)
	const mime = "application/octet-stream"

	payload := randomPayload(t, 5000)
	fileID, token, _ := declare(t, c, 3, "done.bin", len(payload), mime, "")
	if code := putBytes(t, ts, token, payload); code != http.StatusNoContent {
		t.Fatalf("PUT = %d", code)
	}

	// Nothing remains, so a single byte is more than the rest - declared, or
	// found by reading one.
	for i, put := range []func(token string) int{
		func(token string) int { return putBytes(t, ts, token, []byte("x")) },
		func(token string) int { return putChunked(t, ts, token, []byte("x")) },
	} {
		_, token, received := declare(t, c, 4+i, "done.bin", len(payload), mime, fileID)
		if received != int64(len(payload)) {
			t.Fatalf("received = %d, want all %d", received, len(payload))
		}
		if code := put(token); code != http.StatusRequestEntityTooLarge {
			t.Fatalf("PUT %d of a byte past a finished file = %d, want 413", i, code)
		}
	}
	if !bytes.Equal(diskBytes(t, srv, fileID), payload) {
		t.Fatal("the finished bytes changed")
	}
	// With nothing in it, it is the lost 204 asked for again, however it is sent.
	_, token, _ = declare(t, c, 6, "done.bin", len(payload), mime, fileID)
	if code := putChunked(t, ts, token, nil); code != http.StatusNoContent {
		t.Fatalf("empty chunked PUT on a finished file = %d, want 204", code)
	}
}

// deadlineWriter is a ResponseWriter that records the read deadlines it is
// handed and nothing else.
type deadlineWriter struct {
	header http.Header
	set    []time.Time
}

func (d *deadlineWriter) Header() http.Header         { return d.header }
func (d *deadlineWriter) Write(p []byte) (int, error) { return len(p), nil }
func (d *deadlineWriter) WriteHeader(int)             {}

func (d *deadlineWriter) SetReadDeadline(t time.Time) error {
	d.set = append(d.set, t)
	return nil
}

func TestAnInterruptAfterTheLastByteLeavesTheConnectionAlone(t *testing.T) {
	w := &deadlineWriter{header: http.Header{}}
	body := newStallReader(w, io.NopCloser(strings.NewReader("every byte")), time.Minute)
	if _, err := io.ReadAll(body); err != nil {
		t.Fatalf("read: %v", err)
	}
	renewals := len(w.set)
	body.interrupt()
	if len(w.set) != renewals {
		t.Fatal("an interrupt after the last byte moved the read deadline: net/http reads that connection " +
			"for the next request by then, and a deadline in the past cancels the request's context under its commit")
	}

	// Before the last byte, the same interrupt wakes the read at once.
	w = &deadlineWriter{header: http.Header{}}
	body = newStallReader(w, io.NopCloser(strings.NewReader("more to come")), time.Minute)
	if _, err := body.Read(make([]byte, 4)); err != nil {
		t.Fatalf("read: %v", err)
	}
	body.interrupt()
	if last := w.set[len(w.set)-1]; last.After(time.Now()) {
		t.Fatalf("an interrupt mid-body set the deadline to %v, still ahead", last)
	}
	if _, err := body.Read(make([]byte, 4)); !errors.Is(err, errSuperseded) {
		t.Fatalf("a read after the interrupt = %v, want errSuperseded", err)
	}
}

// SC-004 (047): a 100 MiB upload broken off in the middle of a chunk goes on
// from that chunk's first byte and arrives whole - and the file it makes
// opens to exactly the bytes that were sent.
func TestAHundredMegabytesBrokenMidChunkArriveWhole(t *testing.T) {
	ts, srv := newTestServer(t)
	c := greeted(t, ts, srv)

	payload := randomPayload(t, 100<<20)
	fileID, token, _ := declare(t, c, 3, "film.mp4", len(payload), "video/mp4", "")
	// The break falls 12345 bytes into chunk 700.
	cutAfter(t, ts, srv, fileID, token, payload, 700*chunk+12345)

	_, token2, received := declare(t, c, 4, "film.mp4", len(payload), "video/mp4", fileID)
	if received != 700*chunk {
		t.Fatalf("received = %d, want the %d bytes of the 700 chunks before the break", received, 700*chunk)
	}
	if code := putBytes(t, ts, token2, payload[received:]); code != http.StatusNoContent {
		t.Fatalf("PUT of the rest = %d", code)
	}
	if !bytes.Equal(diskBytes(t, srv, fileID), payload) {
		t.Fatal("the finished file is not the bytes that were sent")
	}
}

// FR-010, SC-004: any range of an encrypted file - inside one chunk, across
// chunks, from the end, several at once - is exactly those bytes of the file.
func TestEveryRangeOfAnEncryptedFileIsExactlyItsBytes(t *testing.T) {
	ts, srv := newTestServer(t)
	c := greeted(t, ts, srv)
	payload := randomPayload(t, 5*chunk+777)
	fileID := storeFile(t, srv, payload)
	size := len(payload)
	id := 3
	for _, rg := range []struct {
		header     string
		start, end int
	}{
		{"bytes=100-200", 100, 200},
		{fmt.Sprintf("bytes=%d-%d", chunk-6, chunk+9), chunk - 6, chunk + 9},
		{fmt.Sprintf("bytes=%d-", 3*chunk+1), 3*chunk + 1, size - 1},
		{"bytes=-10", size - 10, size - 1},
		{fmt.Sprintf("bytes=0-%d", size-1), 0, size - 1},
	} {
		code, got, _ := doGet(t, ts, downloadBegin(t, c, id, fileID), rg.header)
		id++
		if code != http.StatusPartialContent || !bytes.Equal(got, payload[rg.start:rg.end+1]) {
			t.Fatalf("%s = %d, %d bytes; want 206 and bytes %d..%d", rg.header, code, len(got), rg.start, rg.end)
		}
	}
	// Two ranges at once, the later one first: the reader seeks back.
	code, got, hdr := doGet(t, ts, downloadBegin(t, c, id, fileID), fmt.Sprintf("bytes=%d-%d,10-19", 4*chunk, 4*chunk+9))
	if code != http.StatusPartialContent || !strings.HasPrefix(hdr.Get("Content-Type"), "multipart/byteranges") {
		t.Fatalf("two ranges = %d %q", code, hdr.Get("Content-Type"))
	}
	if !bytes.Contains(got, payload[4*chunk:4*chunk+10]) || !bytes.Contains(got, payload[10:20]) {
		t.Fatal("the two ranges are not the file's bytes")
	}
}
