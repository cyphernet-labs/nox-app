package server

import (
	"context"
	"time"

	"nox.app/client-backend/internal/backup"
)

// writeBackup writes a backup of this running server at path (047, `noxd
// backup`): the sealed data key, a snapshot of the database and the finished
// attachments, all of it encrypted, in one file only the password opens. The
// server goes on serving while it is written. It runs on the gate's goroutine
// (gate.backup), one at a time, never beside a password change.
//
// The log says that a backup was written and how much it holds - never where
// to, nor anything it holds.
func (s *Server) writeBackup(ctx context.Context, path string) error {
	start := time.Now()
	sum, err := backup.Write(ctx, path, backup.Source{
		DBPath:  s.cfg.DBPath,
		KeyPath: s.cfg.KeyPath(),
		DataKey: s.dataKey,
		Snapshot: func(ctx context.Context, snapshot string) error {
			return s.store.Snapshot(ctx, snapshot, s.dataKey)
		},
		Files: s.blob,
	}, start)
	if err != nil {
		return err
	}
	s.logger.Info("backup written", "files", sum.Files, "unfinished_uploads", sum.Missing,
		"file_bytes", sum.Bytes, "took_ms", time.Since(start).Milliseconds())
	return nil
}
