package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"nox.app/client-backend/internal/protocol"
	"nox.app/client-backend/internal/store"
)

// --- socket commands (contract §7, §4) ---

type uploadBeginRequest struct {
	Name string `json:"name"`
	Size int64  `json:"size"`
	Mime string `json:"mime"`
}

type uploadBeginReply struct {
	FileID             string `json:"file_id"`
	UploadURL          string `json:"upload_url"`
	UploadToken        string `json:"upload_token"`
	MaxAttachmentBytes int64  `json:"max_attachment_bytes"`
}

func (c *client) handleFileUploadBegin(cmd protocol.Command) {
	var req uploadBeginRequest
	if err := json.Unmarshal(cmd.Data, &req); err != nil {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "malformed file.uploadBegin data"))
		return
	}
	name := strings.TrimSpace(req.Name)
	if name == "" || strings.TrimSpace(req.Mime) == "" || req.Size < 1 {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest,
			"name, mime and a positive size are required"))
		return
	}
	if req.Size > c.srv.cfg.Limits.MaxAttachmentBytes {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrPayloadTooLarge,
			fmt.Sprintf("size exceeds max_attachment_bytes %d", c.srv.cfg.Limits.MaxAttachmentBytes)))
		return
	}

	att, err := c.srv.store.CreateUpload(c.ctx, name, req.Size, strings.TrimSpace(req.Mime), time.Now().Unix())
	if err != nil {
		c.logger.Error("create upload failed", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to register upload"))
		return
	}
	token := c.srv.tokens.issue(att.FileID, opUpload)
	c.sendFrame(protocol.OKReply(cmd.ID, uploadBeginReply{
		FileID:             att.FileID,
		UploadURL:          "/files/" + token,
		UploadToken:        token,
		MaxAttachmentBytes: c.srv.cfg.Limits.MaxAttachmentBytes,
	}))
	c.logger.Info("upload registered", "file", att.FileID, "size", att.Size)
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
	// Terminal: expired by TTL or the bytes are physically gone.
	if time.Now().Unix() >= info.Attachment.ExpiresAt || !c.srv.blob.Exists(req.FileID) {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrAttachmentGone, "attachment bytes are no longer stored"))
		return
	}

	token := c.srv.tokens.issue(req.FileID, opDownload)
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

// handlePutFile receives attachment bytes for a one-shot upload token.
// Exactly the declared size is accepted: more trips MaxBytesReader (413),
// less means a broken stream (400) - either way nothing is stored and the
// client restarts from file.uploadBegin. All token failures are 404 alike:
// existence is not disclosed to guessers.
func (s *Server) handlePutFile(w http.ResponseWriter, r *http.Request) {
	fileID, ok := s.tokens.consume(r.PathValue("token"), opUpload)
	if !ok {
		http.NotFound(w, r)
		return
	}
	info, err := s.store.FileByID(r.Context(), fileID)
	if err != nil || info.Uploaded {
		http.NotFound(w, r)
		return
	}

	up, err := s.blob.Create(fileID)
	if err != nil {
		s.logger.Error("blob create failed", "err", err, "file", fileID)
		http.Error(w, "storage failure", http.StatusInternalServerError)
		return
	}
	body := http.MaxBytesReader(w, r.Body, info.Attachment.Size)
	n, err := up.CopyFrom(body)
	if err != nil {
		up.Abort()
		var tooBig *http.MaxBytesError
		if errors.As(err, &tooBig) {
			http.Error(w, "attachment exceeds the declared size", http.StatusRequestEntityTooLarge)
			return
		}
		s.logger.Warn("upload stream failed", "file", fileID, "received", n)
		http.Error(w, "upload interrupted", http.StatusBadRequest)
		return
	}
	if n != info.Attachment.Size {
		up.Abort()
		http.Error(w, "byte count does not match the declared size", http.StatusBadRequest)
		return
	}
	if err := up.Finalize(); err != nil {
		s.logger.Error("blob finalize failed", "err", err, "file", fileID)
		http.Error(w, "storage failure", http.StatusInternalServerError)
		return
	}
	if err := s.store.MarkUploaded(r.Context(), fileID); err != nil {
		s.logger.Error("mark uploaded failed", "err", err, "file", fileID)
		http.Error(w, "storage failure", http.StatusInternalServerError)
		return
	}
	s.logger.Info("upload complete", "file", fileID, "size", n)
	w.WriteHeader(http.StatusNoContent)
}

// handleGetFile serves attachment bytes for a one-shot download token.
// ServeContent brings Range/416 semantics for resumable downloads.
func (s *Server) handleGetFile(w http.ResponseWriter, r *http.Request) {
	fileID, ok := s.tokens.consume(r.PathValue("token"), opDownload)
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
	w.Header().Set("Content-Type", info.Attachment.Mime)
	http.ServeContent(w, r, "", stat.ModTime(), f)
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
