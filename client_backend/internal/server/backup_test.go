package server

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"nox.app/client-backend/internal/backup"
	"nox.app/client-backend/internal/blob"
	"nox.app/client-backend/internal/config"
	"nox.app/client-backend/internal/vault"
)

// Backup and restore end to end (047, SC-005): `noxd backup` of a running
// server, `noxd restore` of it on an empty place, and the restored server
// taking the same devices without pairing - with a new journal id, so they
// read the conversation again.

// getFile downloads fileID on a run session.
func (s *runSession) getFile(t *testing.T, fileID string) []byte {
	t.Helper()
	data := s.ok(t, `{"id":%d,"cmd":"file.downloadBegin","data":{"file_id":%q}}`, fileID)
	var token string
	mustUnmarshal(t, data["download_token"], &token)
	client := newTestChannel(s.cfg.Addr, s.serverKey, &testDevices{}).clientAs(s.dev)
	resp, err := client.Get("https://" + s.cfg.Addr + "/files/" + token)
	if err != nil {
		t.Fatalf("GET: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()
	body, err := io.ReadAll(resp.Body)
	if err != nil || resp.StatusCode != http.StatusOK {
		t.Fatalf("GET = %d (%v)", resp.StatusCode, err)
	}
	return body
}

func TestARestoredServerTakesItsDevicesBackWithANewJournal(t *testing.T) {
	cfg := testRunConfig(t)
	logs, stop := runServer(t, cfg)
	s := pairOnRun(t, cfg, logs)
	journal := s.journal

	created := s.ok(t, `{"id":%d,"cmd":"chat.create","data":{"name":"before the backup"}}`)
	var chatID string
	var chat struct {
		ChatID string `json:"chat_id"`
	}
	mustUnmarshal(t, created["chat"], &chat)
	chatID = chat.ChatID
	s.ok(t, `{"id":%d,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"m1","body":{"type":"text","text":"kept"}}}`, chatID)
	content := randomPayload(t, 2*blob.ChunkSize+321)
	fileID, token, _ := declareRun(t, s, "photo.jpg", len(content))
	if code := s.put(t, token, content); code != http.StatusNoContent {
		t.Fatalf("PUT = %d", code)
	}
	s.ok(t, `{"id":%d,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"m2","attachment":{"file_id":%q}}}`, chatID, fileID)

	// noxd backup: written by the running server, which goes on serving.
	dst := filepath.Join(t.TempDir(), "nox.tar")
	if err := RequestBackup(t.Context(), cfg.StatusAddr, dst); err != nil {
		t.Fatalf("noxd backup: %v", err)
	}
	s.ok(t, `{"id":%d,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"m3","body":{"type":"text","text":"after the backup"}}}`, chatID)
	// A second backup to the same path is refused, the first left whole.
	var refused *CommandError
	if err := RequestBackup(t.Context(), cfg.StatusAddr, dst); !errors.As(err, &refused) || refused.Code != codePath {
		t.Fatalf("a backup over an existing one = %v, want path", err)
	}
	if out := logs.String(); !strings.Contains(out, "backup written") || strings.Contains(out, dst) {
		t.Fatalf("the log does not say a backup was written, or names where:\n%s", out)
	}
	s.close()
	if err := stop(); err != nil {
		t.Fatalf("Run returned %v", err)
	}

	// noxd restore on an empty place, as on another machine.
	other := filepath.Join(t.TempDir(), "elsewhere")
	if err := os.Mkdir(other, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	restored := testRunConfig(t)
	restored.DBPath = filepath.Join(other, "nox.db")
	restored.FilesPath = restored.DBPath + "-files"
	if _, err := backup.Restore(t.Context(), dst, backup.Target{DBPath: restored.DBPath, FilesPath: restored.FilesPath},
		func() (string, error) { return testPassword, nil }); err != nil {
		t.Fatalf("restore: %v", err)
	}

	// It starts locked, and opens with the same password.
	logs2, _ := startRun(t, restored)
	if got := health(t, restored.StatusAddr); got != `{"status":"locked"}` {
		t.Fatalf("/health of the restored server = %s, want locked", got)
	}
	if err := RequestUnlock(t.Context(), restored.StatusAddr, testPassword, ""); err != nil {
		t.Fatalf("unlock the restored server: %v", err)
	}
	if loggedServerKey(logs2.String()) != loggedServerKey(logs.String()) {
		t.Fatal("the restored server proves another key: every device would have to pair again")
	}

	// The device paired before the backup greets without pairing; the journal
	// id is new, so it reads the conversation again - and finds it as it was
	// at the backup.
	s2 := &runSession{cfg: restored, serverKey: s.serverKey, dev: s.dev, next: 2}
	s2.c = dialRun(t, restored.Addr, s.serverKey, s.dev)
	s2.c.expectGreeting()
	reply := s2.c.hello(1, "")
	var journal2 string
	mustUnmarshal(t, reply["journal_id"], &journal2)
	if journal2 == "" || journal2 == journal {
		t.Fatalf("the restored journal id = %q, want a new one (was %q)", journal2, journal)
	}
	page := s2.ok(t, `{"id":%d,"cmd":"messages.list","data":{"chat_id":%q,"limit":50}}`, chatID)
	var msgs []struct {
		Body json.RawMessage `json:"body"`
	}
	mustUnmarshal(t, page["messages"], &msgs)
	var texts []string
	for _, m := range msgs {
		texts = append(texts, string(m.Body))
	}
	joined := strings.Join(texts, " ")
	if !strings.Contains(joined, "kept") || strings.Contains(joined, "after the backup") {
		t.Fatalf("the restored conversation = %s, want what it was at the backup", joined)
	}
	if got := s2.getFile(t, fileID); !bytes.Equal(got, content) {
		t.Fatal("the restored attachment is not the file that was sent")
	}
}

// SC-006 at the server: a new password re-seals the key in well under five
// seconds whatever the server holds - nothing else is touched - and only the
// new password opens the server after it.
func TestAPasswordChangeTouchesNothingButTheKey(t *testing.T) {
	cfg := testRunConfig(t)
	// The real costs here: the time asked about is the real one.
	logs := &syncLog{}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() {
		done <- run(ctx, cfg, os.DirFS("../../migrations"), slog.New(slog.NewTextHandler(logs, nil)), vault.DefaultParams())
	}()
	t.Cleanup(func() {
		cancel()
		select {
		case <-done:
		case <-time.After(45 * time.Second):
			t.Error("Run did not stop")
		}
	})
	eventually(t, "the page answers", func() bool {
		_, err := RequestState(context.Background(), cfg.StatusAddr)
		return err == nil
	})
	if err := RequestUnlock(t.Context(), cfg.StatusAddr, testPassword, testPassword); err != nil {
		t.Fatalf("set the password: %v", err)
	}
	eventually(t, "the startup line names the key", func() bool { return loggedServerKey(logs.String()) != "" })
	s := pairOnRun(t, cfg, logs)
	created := s.ok(t, `{"id":%d,"cmd":"chat.create","data":{"name":"volume"}}`)
	var chat struct {
		ChatID string `json:"chat_id"`
	}
	mustUnmarshal(t, created["chat"], &chat)
	for i := range 200 {
		s.ok(t, `{"id":%d,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"v%d","body":{"type":"text","text":"%s"}}}`,
			chat.ChatID, i, strings.Repeat("x", 2000))
	}
	content := randomPayload(t, 16<<20)
	fileID, token, _ := declareRun(t, s, "big.bin", len(content))
	if code := s.put(t, token, content); code != http.StatusNoContent {
		t.Fatalf("PUT = %d", code)
	}
	attachment := filepath.Join(cfg.FilesPath, fileID)
	before, err := os.ReadFile(attachment)
	if err != nil {
		t.Fatalf("read: %v", err)
	}

	const next = "staple orbit lantern"
	start := time.Now()
	if err := RequestPasswordChange(t.Context(), cfg.StatusAddr, testPassword, next); err != nil {
		t.Fatalf("noxd password: %v", err)
	}
	if took := time.Since(start); took >= 5*time.Second {
		t.Fatalf("the password change took %v, want under 5 s", took)
	}
	after, err := os.ReadFile(attachment)
	if err != nil || !bytes.Equal(before, after) {
		t.Fatal("the change re-wrote an attachment: it should re-seal the key and nothing else")
	}
	if _, err := vault.Open(cfg.KeyPath(), testPassword); !errors.Is(err, vault.ErrWrongPassword) {
		t.Fatalf("the old password after the change = %v, want wrong", err)
	}
	if _, err := vault.Open(cfg.KeyPath(), next); err != nil {
		t.Fatalf("the new password: %v", err)
	}
	// The server goes on as it was: the device is still served.
	s.ok(t, `{"id":%d,"cmd":"chats.list","data":{"page":1,"page_size":10}}`)
	if strings.Contains(logs.String(), next) || strings.Contains(logs.String(), testPassword) {
		t.Fatal("a password reached the log")
	}
}

// backupAt builds the config of a server whose files live in dir.
func backupAt(t *testing.T, dir string) config.Config {
	t.Helper()
	cfg := testRunConfig(t)
	cfg.DBPath = filepath.Join(dir, "nox.db")
	cfg.FilesPath = cfg.DBPath + "-files"
	return cfg
}

// A backup path the server cannot use is said to the command with the reason,
// and nothing is written.
func TestABackupToAPathTheServerCannotUseIsRefusedWithTheReason(t *testing.T) {
	cfg := backupAt(t, t.TempDir())
	_, _ = runServer(t, cfg)
	var refused *CommandError
	missing := filepath.Join(t.TempDir(), "no", "such", "dir", "b.tar")
	if err := RequestBackup(t.Context(), cfg.StatusAddr, missing); !errors.As(err, &refused) || refused.Code != codePath ||
		!strings.Contains(refused.Message, "does not exist") {
		t.Fatalf("a backup into a missing directory = %v, want path and the reason", err)
	}
	if err := RequestBackup(t.Context(), cfg.StatusAddr, "relative.tar"); !errors.As(err, &refused) || refused.Code != codePath {
		t.Fatalf("a relative backup path = %v, want path", err)
	}
}
