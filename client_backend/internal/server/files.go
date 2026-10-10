package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"nox.app/client-backend/internal/blob"
	"nox.app/client-backend/internal/protocol"
	"nox.app/client-backend/internal/store"
)

// --- socket commands (contract §7, §4) ---

const (
	// Metadata caps (contract §7): unbounded names would be baked into
	// permanent event payloads and amplified into every list page and
	// replay - a poisoned frame could exceed max_frame_bytes forever.
	maxFileNameRunes = 255
	maxMimeRunes     = 128

	// defaultStallTimeout is how long a PUT or GET body may go without a
	// byte before the transfer counts as stalled (043). It is the ONLY time
	// limit on a transfer: through Tor 100 MiB take tens of minutes, and a
	// limit on the whole would cut exactly the slow path that needs the time.
	// The deadline is renewed on every read and every write, so it measures
	// silence, never duration.
	defaultStallTimeout = 60 * time.Second
	// defaultCheckpointBytes is how often an upload makes what it received
	// durable. A crash loses at most this much - a couple of minutes through
	// Tor - and 25 fsyncs for 100 MiB cost nothing on a local disk.
	defaultCheckpointBytes = 4 << 20
	// defaultPreemptWait bounds how long a PUT waits for the previous writer
	// of its file to let go. It waits on its own HTTP goroutine.
	defaultPreemptWait = 5 * time.Second
	// defaultContinuationWait bounds the same wait for a continuation. It
	// runs on the connection's read loop, which is also where pongs are
	// read, and a ping gives up when its pong is late - so a second, and
	// never a reason to refuse.
	defaultContinuationWait = time.Second
)

type uploadBeginRequest struct {
	Name string `json:"name"`
	Size int64  `json:"size"`
	Mime string `json:"mime"`
	// FileID continues the unfinished upload of that file (043). The rest of
	// the request stays a whole declaration: a server that predates
	// continuation skips the field and declares a new file from it.
	FileID string `json:"file_id"`
}

type uploadBeginReply struct {
	FileID             string `json:"file_id"`
	UploadURL          string `json:"upload_url"`
	UploadToken        string `json:"upload_token"`
	MaxAttachmentBytes int64  `json:"max_attachment_bytes"`
	// Received is how many leading bytes of the file the server holds safely,
	// and the offset the token's PUT starts at. Always present: its presence
	// is how a client tells this server can continue an upload.
	Received int64 `json:"received"`
}

func (c *client) handleFileUploadBegin(cmd protocol.Command) {
	var req uploadBeginRequest
	if err := json.Unmarshal(cmd.Data, &req); err != nil {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "malformed file.uploadBegin data"))
		return
	}
	name := strings.TrimSpace(req.Name)
	mime := strings.TrimSpace(req.Mime)
	if name == "" || mime == "" || req.Size < 1 {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest,
			"name, mime and a positive size are required"))
		return
	}
	if utf8.RuneCountInString(name) > maxFileNameRunes || utf8.RuneCountInString(mime) > maxMimeRunes {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest,
			fmt.Sprintf("name is capped at %d and mime at %d characters", maxFileNameRunes, maxMimeRunes)))
		return
	}
	if req.Size > c.srv.cfg.Limits.MaxAttachmentBytes {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrPayloadTooLarge,
			fmt.Sprintf("size exceeds max_attachment_bytes %d", c.srv.cfg.Limits.MaxAttachmentBytes)))
		return
	}
	if req.FileID != "" {
		c.continueUpload(cmd, req.FileID, name, req.Size, mime)
		return
	}

	att, err := c.srv.store.CreateUpload(c.ctx, name, req.Size, mime, time.Now().Unix())
	if err != nil {
		c.logger.Error("create upload failed", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to register upload"))
		return
	}
	c.replyUpload(cmd, att.FileID, 0)
	c.logger.Info("upload registered", "file", att.FileID, "size", att.Size)
}

// continueUpload answers a declaration that names an earlier upload (043):
// how much of the file the server holds, and a token for the rest.
func (c *client) continueUpload(cmd protocol.Command, fileID, name string, size int64, mime string) {
	info, ok := c.unfinishedUpload(cmd, fileID, name, size, mime)
	if !ok {
		return
	}
	received := size
	if !info.Uploaded {
		// A PUT may still be writing it - one whose connection died without a
		// word goes on waiting for bytes until its stall deadline. Stop it, so
		// the answer counts everything it received; if it does not let go in
		// time, answer with what is durable already. The PUT this token admits
		// cuts the part back to the offset it names either way.
		c.srv.writers.interrupt(fileID, c.srv.continuationWait)
		// Read again: a writer whose last byte was already in does not stop,
		// it finishes - and what the first read said is no longer true.
		if info, ok = c.unfinishedUpload(cmd, fileID, name, size, mime); !ok {
			return
		}
		if !info.Uploaded && !c.srv.finished(fileID, size) {
			durable, err := c.srv.blob.Received(fileID)
			if err != nil {
				c.logger.Error("upload progress lookup failed", "err", err, "file", fileID)
				c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to read upload progress"))
				return
			}
			received = min(durable, size)
		}
	}
	c.replyUpload(cmd, fileID, received)
	c.logger.Info("upload resumed", "file", fileID, "from", received, "size", size)
}

// unfinishedUpload looks up the upload a continuation names and answers the
// refusals itself.
//
// Bound, swept or never there all read the same - "no unfinished upload by
// that id" - and the client starts a new one; for the person that is not an
// error. A declaration that names the same id with other metadata is a
// client mistake, and continuing it would put one file's bytes under
// another's name.
func (c *client) unfinishedUpload(cmd protocol.Command, fileID, name string, size int64, mime string) (store.FileInfo, bool) {
	info, err := c.srv.store.FileByID(c.ctx, fileID)
	switch {
	case errors.Is(err, store.ErrFileNotFound):
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrNotFound, "no unfinished upload with this file_id"))
		return store.FileInfo{}, false
	case err != nil:
		c.logger.Error("file lookup failed", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to look up file"))
		return store.FileInfo{}, false
	}
	if info.MessageID != "" {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrNotFound, "no unfinished upload with this file_id"))
		return store.FileInfo{}, false
	}
	att := info.Attachment
	if att.Name != name || att.Size != size || att.Mime != mime {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest,
			"name, size and mime differ from the ones this upload was declared with"))
		return store.FileInfo{}, false
	}
	return info, true
}

// finished reports whether fileID's part has become the file, whole: every
// byte arrived and was flushed before the rename, whatever the row says. The
// commit that follows the rename can fail to land - a crash, a write the
// database refused - and the bytes are no less whole for it (043).
func (s *Server) finished(fileID string, size int64) bool {
	n, err := s.blob.Size(fileID)
	return err == nil && n == size
}

// replyUpload issues a token for the bytes of fileID from received on and
// answers with it.
func (c *client) replyUpload(cmd protocol.Command, fileID string, received int64) {
	token := c.srv.tokens.issue(fileID, opUpload, received)
	c.sendFrame(protocol.OKReply(cmd.ID, uploadBeginReply{
		FileID:             fileID,
		UploadURL:          "/files/" + token,
		UploadToken:        token,
		MaxAttachmentBytes: c.srv.cfg.Limits.MaxAttachmentBytes,
		Received:           received,
	}))
}

type downloadBeginRequest struct {
	FileID string `json:"file_id"`
}

type downloadBeginReply struct {
	DownloadURL   string `json:"download_url"`
	DownloadToken string `json:"download_token"`
}

func (c *client) handleFileDownloadBegin(cmd protocol.Command) {
	var req downloadBeginRequest
	if err := json.Unmarshal(cmd.Data, &req); err != nil || req.FileID == "" {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "file_id is required"))
		return
	}

	info, err := c.srv.store.FileByID(c.ctx, req.FileID)
	switch {
	case errors.Is(err, store.ErrFileNotFound):
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrNotFound, "file does not exist"))
		return
	case err != nil:
		c.logger.Error("file lookup failed", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to look up file"))
		return
	}
	if !info.Uploaded {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "file bytes are not uploaded yet"))
		return
	}
	// Terminal: expired by TTL, bytes physically gone, or bytes torn (a
	// size mismatch means a crash beat the flush - never serve them).
	size, sizeErr := c.srv.blob.Size(req.FileID)
	if time.Now().Unix() >= info.Attachment.ExpiresAt || sizeErr != nil || size != info.Attachment.Size {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrAttachmentGone, "attachment bytes are no longer stored"))
		return
	}

	token := c.srv.tokens.issue(req.FileID, opDownload, 0)
	c.sendFrame(protocol.OKReply(cmd.ID, downloadBeginReply{
		DownloadURL:   "/files/" + token,
		DownloadToken: token,
	}))
}

type chatFilesRequest struct {
	ChatID    string `json:"chat_id"`
	BeforeSeq int64  `json:"before_seq"`
	Limit     int    `json:"limit"`
}

type chatFilesReply struct {
	Files   []store.ChatFileEntry `json:"files"`
	HasMore bool                  `json:"has_more"`
}

func (c *client) handleChatFiles(cmd protocol.Command) {
	var req chatFilesRequest
	if err := json.Unmarshal(cmd.Data, &req); err != nil || req.ChatID == "" {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "chat_id is required"))
		return
	}
	if req.Limit < 1 {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "limit must be at least 1"))
		return
	}
	if _, err := c.srv.store.GetChat(c.ctx, req.ChatID); err != nil {
		if errors.Is(err, store.ErrChatNotFound) {
			c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrNotFound, "chat does not exist"))
			return
		}
		c.logger.Error("chat files failed", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to list chat files"))
		return
	}

	files, hasMore, err := c.srv.store.ListChatFiles(c.ctx, req.ChatID, req.BeforeSeq, min(req.Limit, maxPageSize))
	if err != nil {
		c.logger.Error("chat files failed", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to list chat files"))
		return
	}
	c.sendFrame(protocol.OKReply(cmd.ID, chatFilesReply{Files: files, HasMore: hasMore}))
}

// --- HTTP surface (contract §1/§7) ---

// admitTransfer answers whether the request's connection belongs to a paired
// device, and refuses it itself when not (044, FR-006a). A transfer needs
// BOTH: a paired key on the connection and a live transfer token - a token
// alone was a bearer credential that worked for whoever held it.
//
// Asked BEFORE the token is looked at, so a stranger who somehow holds one can
// neither spend it nor learn whether it is live. The key is looked up on every
// request, not once per connection, so a request on a connection that outlived
// its device's revocation is refused.
//
// An admitted transfer stays registered under its key until the handler calls
// done, and revoking the device cuts it there and then (dropDevice): a
// transfer has no time limit, and a lost phone halfway through a download
// would otherwise go on reading for as long as it liked. It is registered
// BEFORE the key is looked up, and the order is what closes the gap between
// the two. A revocation deletes the row and only then walks the registry, so
// either the walk finds this transfer and cuts it, or the walk came first -
// and the deletion before it, which the lookup then sees.
//
// 401 for a stranger, and still 404 for a bad token from a paired device: the
// 404 is how a client of 043 knows to ask for a new pass, and that must not
// change. A store that cannot answer is a 500 - the device did nothing wrong.
//
// A 401 ends the connection (endWithAnswer). The door has ended a stranger's
// already; a 401 that is still to be decided here is a device revoked between
// the door's question and this one, whose connection would otherwise be kept
// for its next request.
func (s *Server) admitTransfer(w http.ResponseWriter, r *http.Request) (done func(), ok bool) {
	conn, ok := channelConnFrom(r.Context())
	if !ok {
		endWithAnswer(w, r)
		http.Error(w, "the connection proved no device key", http.StatusUnauthorized)
		return nil, false
	}
	key := conn.peer.deviceKey()
	done = s.trackTransfer(key, conn)
	_, paired, err := s.store.DeviceOwner(r.Context(), key)
	if err != nil {
		done()
		s.logger.Error("transfer device lookup failed", "err", err)
		http.Error(w, "storage failure", http.StatusInternalServerError)
		return nil, false
	}
	if !paired {
		done()
		endWithAnswer(w, r)
		http.Error(w, "the connection's device is not paired", http.StatusUnauthorized)
		return nil, false
	}
	return done, true
}

// handlePutFile receives attachment bytes for a one-shot upload token
// (contract §7, 043). The token names the file and the offset its bytes
// begin at; the body carries the file from there to its end, and whatever
// arrives is kept - a request that breaks leaves its bytes for the next one
// to continue from. All token failures are 404 alike: existence is not
// disclosed to guessers.
func (s *Server) handlePutFile(w http.ResponseWriter, r *http.Request) {
	done, ok := s.admitTransfer(w, r)
	if !ok {
		return
	}
	defer done()
	fileID, offset, ok := s.tokens.consume(r.PathValue("token"), opUpload)
	if !ok {
		http.NotFound(w, r)
		return
	}
	info, err := s.store.FileByID(r.Context(), fileID)
	if err != nil || offset > info.Attachment.Size {
		http.NotFound(w, r)
		return
	}
	size := info.Attachment.Size
	remainder := size - offset
	if r.ContentLength > remainder {
		// Declared longer than the rest of the file: not the file the
		// declaration named. Refused before a byte is read - and before the
		// request writing the file now is disturbed for it.
		http.Error(w, "more bytes than the rest of the file", http.StatusRequestEntityTooLarge)
		return
	}

	body := newStallReader(w, r.Body, s.stallTimeout)
	release, ok := s.writers.take(fileID, body.interrupt, s.preemptWait)
	if !ok {
		http.Error(w, "an earlier upload of this file has not let go of it yet", http.StatusConflict)
		return
	}
	// Deferred in this order so they run in the other: the reader stops
	// accepting interrupts BEFORE the next writer may take the file, and a
	// late interrupt can never reach a connection that has moved on.
	defer release()
	defer body.finish()

	// Read again: the writer this request waited for may have finished the
	// file meanwhile, and a token issued before that must not write over it.
	if info, err = s.store.FileByID(r.Context(), fileID); err != nil {
		http.NotFound(w, r)
		return
	}
	if info.Uploaded || s.finished(fileID, size) {
		s.putFinished(w, r, body, fileID, offset, size, info.Uploaded)
		return
	}

	up, err := s.blob.Resume(fileID, offset)
	if errors.Is(err, blob.ErrShortPart) {
		// The bytes this token was issued after are no longer all on disk.
		http.NotFound(w, r)
		return
	}
	if err != nil {
		s.logger.Error("blob resume failed", "err", err, "file", fileID)
		http.Error(w, "storage failure", http.StatusInternalServerError)
		return
	}

	n, readErr, writeErr := s.receive(up, http.MaxBytesReader(w, body, remainder))
	at := offset + n
	var tooBig *http.MaxBytesError
	switch {
	case writeErr != nil:
		// The disk refused. What reached stable storage before it stays - the
		// earlier requests' bytes and this one's up to its last checkpoint -
		// and the rest cannot be vouched for. Only a part that cannot even be
		// cut back is thrown away whole.
		if err := up.Rollback(up.Durable()); err != nil {
			up.Abort()
			s.logger.Error("upload rollback failed", "err", err, "file", fileID)
		}
		s.logger.Error("upload write failed", "err", writeErr, "file", fileID, "at", at)
		http.Error(w, "storage failure", http.StatusInternalServerError)
	case errors.As(readErr, &tooBig):
		// More than the rest of the file in a body of no declared length:
		// this request's bytes are not the file the declaration named. The
		// ones before it stay.
		if err := up.Rollback(offset); err != nil {
			s.logger.Error("upload rollback failed", "err", err, "file", fileID)
		}
		http.Error(w, "more bytes than the rest of the file", http.StatusRequestEntityTooLarge)
	case readErr != nil:
		s.suspend(up, fileID)
		s.answerBroken(w, fileID, at, readErr)
	case n < remainder:
		s.suspend(up, fileID)
		s.logger.Info("upload short", "file", fileID, "at", at, "size", size)
		http.Error(w, "the body ended before the rest of the file; what arrived is kept", http.StatusBadRequest)
	default:
		if err := up.Finalize(); err != nil {
			s.logger.Error("blob finalize failed", "err", err, "file", fileID)
			http.Error(w, "storage failure", http.StatusInternalServerError)
			return
		}
		if s.afterFinalize != nil {
			s.afterFinalize(fileID)
		}
		s.commitUpload(w, r, fileID, offset, size)
	}
}

// putFinished answers a PUT for a file whose bytes are all here already.
//
// An empty one is how a client whose 204 was lost hears it again - and, when
// the commit that should have followed the bytes never landed, what lands it.
// A token for an earlier offset was issued before the file was whole: 404,
// and the client asks again and is told nothing is left to send. With nothing
// left, any byte at all is more than the rest of the file; one is read to
// tell when the length was not declared.
func (s *Server) putFinished(w http.ResponseWriter, r *http.Request, body io.Reader, fileID string, offset, size int64, committed bool) {
	if offset < size {
		http.NotFound(w, r)
		return
	}
	if r.ContentLength < 0 {
		var one [1]byte
		k, err := io.ReadFull(body, one[:])
		if k > 0 {
			http.Error(w, "more bytes than the rest of the file", http.StatusRequestEntityTooLarge)
			return
		}
		if !errors.Is(err, io.EOF) {
			s.answerBroken(w, fileID, size, err)
			return
		}
	}
	if committed {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	s.commitUpload(w, r, fileID, offset, size)
}

// commitUpload tells the database the file is whole and answers 204.
//
// The commit runs on a context the request cannot cancel. Its bytes are all
// on disk by now, and the client may already be gone - it hung up after its
// last byte, or a continuation came for the file - which cancels the request
// before the answer is written. A file left whole on disk and unknown to its
// row would be sent again from the first byte.
func (s *Server) commitUpload(w http.ResponseWriter, r *http.Request, fileID string, offset, size int64) {
	err := s.store.MarkUploaded(context.WithoutCancel(r.Context()), fileID)
	if errors.Is(err, store.ErrFileNotFound) {
		// Swept in between: nothing is left to finish.
		http.NotFound(w, r)
		return
	}
	if err != nil {
		s.logger.Error("mark uploaded failed", "err", err, "file", fileID)
		http.Error(w, "storage failure", http.StatusInternalServerError)
		return
	}
	s.logger.Info("upload complete", "file", fileID, "size", size, "from", offset)
	w.WriteHeader(http.StatusNoContent)
}

// answerBroken answers a PUT whose body broke off. It answers with a definite
// failure even when nobody can hear it: a handler that returns without one
// answers 200, and a client that did read it would take an unfinished file
// for a finished one.
func (s *Server) answerBroken(w http.ResponseWriter, fileID string, at int64, readErr error) {
	switch {
	case errors.Is(readErr, errSuperseded):
		s.logger.Info("upload interrupted", "file", fileID, "at", at, "by", "a newer request")
		http.Error(w, "a newer request for this file took over", http.StatusConflict)
	case isTimeout(readErr):
		s.logger.Info("upload stalled", "file", fileID, "at", at)
		http.Error(w, "no bytes arrived in time; what arrived is kept", http.StatusRequestTimeout)
	default:
		s.logger.Info("upload interrupted", "file", fileID, "at", at)
		http.Error(w, "the upload broke off; what arrived is kept", http.StatusRequestTimeout)
	}
}

// receive copies a request body into the part, making it durable every
// checkpointBytes, so a crash in the middle of a long upload loses at most
// that much. It returns how many bytes this request delivered, and keeps the
// two ways the copy can end apart: a read error is the network's, a write
// error the disk's.
func (s *Server) receive(up *blob.Upload, body io.Reader) (n int64, readErr, writeErr error) {
	buf := make([]byte, 32<<10)
	var sinceCheckpoint int64
	for {
		k, rerr := body.Read(buf)
		if k > 0 {
			written, werr := up.Write(buf[:k])
			n += int64(written)
			if werr != nil {
				return n, nil, werr
			}
			sinceCheckpoint += int64(written)
			if sinceCheckpoint >= s.checkpointBytes {
				if err := up.Checkpoint(); err != nil {
					return n, nil, err
				}
				sinceCheckpoint = 0
			}
		}
		if errors.Is(rerr, io.EOF) {
			return n, nil, nil
		}
		if rerr != nil {
			return n, rerr, nil
		}
	}
}

// suspend keeps what an unfinished request delivered for the next one. If
// the flush fails the record stays where it was, which only means some bytes
// are sent again.
func (s *Server) suspend(up *blob.Upload, fileID string) {
	if err := up.Suspend(); err != nil {
		s.logger.Error("upload suspend failed", "err", err, "file", fileID)
	}
}

// isTimeout reports whether a body read ended on its deadline.
func isTimeout(err error) bool {
	if errors.Is(err, os.ErrDeadlineExceeded) {
		return true
	}
	var netErr net.Error
	return errors.As(err, &netErr) && netErr.Timeout()
}

// errSuperseded ends a PUT whose file a newer request came for.
var errSuperseded = errors.New("a newer request for this file took over")

// stallReader reads a request body under a deadline that moves with the
// bytes (043): every Read gets the whole stall timeout from its own start, so
// a body that keeps moving - however slowly - is never cut, and one that
// stops is. interrupt ends the reading at once.
type stallReader struct {
	body  io.ReadCloser
	rc    *http.ResponseController
	stall time.Duration

	// mu orders a renewal against an interrupt: a renewal landing after the
	// interrupt set its deadline would push it back by a whole stall timeout,
	// and the newer request would wait that long. It belongs to one request
	// and guards nothing any other request reads.
	mu      sync.Mutex
	stopped bool
	// eof is set once the body has been read to its end. From there the
	// connection is net/http's again: it reads it for a next request, and a
	// deadline in the past would end that read and cancel this request's
	// context - with its last bytes still to be committed.
	eof bool
	// finished is set as the handler leaves. The controller must not be
	// touched after that: the connection may already carry the next request,
	// and a deadline in the past would cut it.
	finished bool
	// renew is false once the connection said it cannot take deadlines; the
	// body is then read with no stall limit rather than not at all.
	renew bool
}

func newStallReader(w http.ResponseWriter, body io.ReadCloser, stall time.Duration) *stallReader {
	return &stallReader{body: body, rc: http.NewResponseController(w), stall: stall, renew: true}
}

func (s *stallReader) Read(p []byte) (int, error) {
	s.mu.Lock()
	if s.stopped {
		s.mu.Unlock()
		return 0, errSuperseded
	}
	if s.renew && s.rc.SetReadDeadline(time.Now().Add(s.stall)) != nil {
		s.renew = false
	}
	s.mu.Unlock()

	n, err := s.body.Read(p)
	if err == nil {
		return n, nil
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if errors.Is(err, io.EOF) {
		// Every byte is in, whatever an interrupt says: the request goes on
		// to finish the file rather than give it up one step short.
		s.eof = true
		return n, err
	}
	if s.stopped {
		return n, errSuperseded
	}
	return n, err
}

// Close closes the request body; net/http owns its lifetime.
func (s *stallReader) Close() error {
	return s.body.Close()
}

// interrupt wakes a Read blocked on the connection and stops every Read
// after it. A no-op once the handler has finished; past the body's end it
// only marks the request stopped, because nothing is left to wake.
func (s *stallReader) interrupt() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.finished {
		return
	}
	s.stopped = true
	if s.eof {
		return
	}
	// A deadline in the past wakes the blocked read at once. Without deadline
	// support there is nothing to wake: the read ends with the connection,
	// and the next one sees stopped.
	if s.renew && s.rc.SetReadDeadline(time.Now()) != nil {
		s.renew = false
	}
}

// finish marks the handler as leaving; interrupts are ignored from here on.
func (s *stallReader) finish() {
	s.mu.Lock()
	s.finished = true
	s.mu.Unlock()
}

// stallWriter renews the write deadline before every write (043), so a
// download that keeps moving - however slowly - is never cut, and one whose
// reader stopped is. Only Header, Write and WriteHeader are exposed: hiding
// ReadFrom keeps io.Copy inside ServeContent writing through Write, where the
// renewal is.
type stallWriter struct {
	w     http.ResponseWriter
	rc    *http.ResponseController
	stall time.Duration
	renew bool
}

func newStallWriter(w http.ResponseWriter, stall time.Duration) *stallWriter {
	return &stallWriter{w: w, rc: http.NewResponseController(w), stall: stall, renew: true}
}

func (s *stallWriter) Header() http.Header {
	return s.w.Header()
}

func (s *stallWriter) WriteHeader(code int) {
	s.w.WriteHeader(code)
}

func (s *stallWriter) Write(p []byte) (int, error) {
	if s.renew && s.rc.SetWriteDeadline(time.Now().Add(s.stall)) != nil {
		s.renew = false
	}
	return s.w.Write(p)
}

// finish sends what is still buffered under the stall deadline, then clears
// it. Belt and braces: net/http (Go 1.27) clears the write deadline itself
// once a handler returns, before the connection carries another request. A
// deadline left behind would cut that request at an arbitrary moment, and a
// one-line reset costs less than depending on that never changing.
func (s *stallWriter) finish() {
	if !s.renew {
		return
	}
	// A failed flush means the reader is gone; the server finds that out on
	// its own, and nothing is left to protect.
	if s.rc.Flush() != nil {
		return
	}
	if s.rc.SetWriteDeadline(time.Time{}) != nil {
		s.renew = false
	}
}

// handleGetFile serves attachment bytes for a one-shot download token.
// ServeContent brings Range/If-Range/416 semantics for resumable downloads:
// the client continues with Range from what it has and If-Range with the
// Last-Modified of its first response (contract §7).
func (s *Server) handleGetFile(w http.ResponseWriter, r *http.Request) {
	done, ok := s.admitTransfer(w, r)
	if !ok {
		return
	}
	defer done()
	// The mux routes HEAD through GET patterns; a HEAD would burn the
	// one-shot token without delivering a byte (an accidental curl -I
	// would kill the link). Reject it before consuming.
	if r.Method == http.MethodHead {
		http.Error(w, "HEAD is not supported for one-shot links", http.StatusMethodNotAllowed)
		return
	}
	fileID, _, ok := s.tokens.consume(r.PathValue("token"), opDownload)
	if !ok {
		http.NotFound(w, r)
		return
	}
	info, err := s.store.FileByID(r.Context(), fileID)
	if err != nil || !info.Uploaded {
		http.NotFound(w, r)
		return
	}
	f, err := s.blob.Open(fileID)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	defer func() { _ = f.Close() }()
	stat, err := f.Stat()
	if err != nil {
		s.logger.Error("blob stat failed", "err", err, "file", fileID)
		http.Error(w, "storage failure", http.StatusInternalServerError)
		return
	}
	// A reader that stops must not pin the goroutine and the fd forever, and
	// one that reads slowly must not be cut: the deadline measures silence.
	sw := newStallWriter(w, s.stallTimeout)
	defer sw.finish()
	sw.Header().Set("Content-Type", info.Attachment.Mime)
	http.ServeContent(sw, r, "", stat.ModTime(), f)
}

// sweepOrphans removes uploads never bound to a message within a day
// (research R10): bytes first, rows second, so a crash in between leaves
// retryable rows, never unreferenced bytes.
func (s *Server) sweepOrphans(ctx context.Context, cutoff int64) error {
	ids, err := s.store.OrphanFiles(ctx, cutoff)
	if err != nil {
		return err
	}
	for _, id := range ids {
		if err := s.blob.Remove(id); err != nil {
			return err
		}
	}
	if err := s.store.DeleteFiles(ctx, ids); err != nil {
		return err
	}
	if len(ids) > 0 {
		s.logger.Info("orphan uploads swept", "count", len(ids))
	}
	return nil
}
