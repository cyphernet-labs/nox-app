package server

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/coder/websocket"

	"nox.app/client-backend/internal/blob"
	"nox.app/client-backend/internal/config"
	"nox.app/client-backend/internal/db"
	"nox.app/client-backend/internal/protocol"
)

// SC-001 (047): a stopped server's files - and a running one's - hold no
// conversation, no attachment, no key and no token in the clear. Whoever
// carries the disk away gets ciphertext and a sealed key.

// runSession is a device paired and greeted on a server Run started.
type runSession struct {
	cfg       config.Config
	serverKey ed25519.PublicKey
	dev       *device
	c         *wsClient
	next      int
	// journal is the journal id the greeting named.
	journal string
}

// pairOnRun pairs a fresh device on a running server through its machine
// link and greets with it.
func pairOnRun(t *testing.T, cfg config.Config, logs *syncLog) *runSession {
	t.Helper()
	raw, err := base64.StdEncoding.DecodeString(loggedServerKey(logs.String()))
	if err != nil {
		t.Fatalf("server key: %v", err)
	}
	link, err := RequestMachineLink(t.Context(), cfg.StatusAddr)
	if err != nil {
		t.Fatalf("RequestMachineLink: %v", err)
	}
	s := &runSession{cfg: cfg, serverKey: ed25519.PublicKey(raw), dev: newDevice(t), next: 3}
	s.c = dialRun(t, cfg.Addr, s.serverKey, s.dev)
	s.c.expectGreeting()
	s.c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"macos"}}`, readLink(t, link.Link).Token))
	s.c.expectOK(1)
	mustUnmarshal(t, s.c.hello(2, "")["journal_id"], &s.journal)
	return s
}

// close says goodbye before the server stops, so its shutdown does not wait
// out a close handshake nobody answers.
func (s *runSession) close() {
	_ = s.c.conn.Close(websocket.StatusNormalClosure, "")
}

// ok sends a command whose format starts with the frame's id and returns the
// reply's data. The id is the session's next.
func (s *runSession) ok(t *testing.T, format string, args ...any) map[string]json.RawMessage {
	t.Helper()
	s.next++
	return s.c.expectOKAfter(s.next, fmt.Sprintf(format, append([]any{s.next}, args...)...))
}

// put sends body as the PUT of an upload token through the channel.
func (s *runSession) put(t *testing.T, token string, body []byte) int {
	t.Helper()
	client := newTestChannel(s.cfg.Addr, s.serverKey, &testDevices{}).clientAs(s.dev)
	req, err := http.NewRequest(http.MethodPut, "https://"+s.cfg.Addr+"/files/"+token, bytes.NewReader(body))
	if err != nil {
		t.Fatalf("NewRequest: %v", err)
	}
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("PUT: %v", err)
	}
	_ = resp.Body.Close()
	return resp.StatusCode
}

// putAndBreak sends the first n bytes of a PUT for token and breaks the
// connection once the server sealed the whole chunks among them.
func (s *runSession) putAndBreak(t *testing.T, token string, fileID string, payload []byte, n int) {
	t.Helper()
	conn, err := dialChannel(t.Context(), s.cfg.Addr, s.serverKey, s.dev.priv)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	head := fmt.Sprintf("PUT /files/%s HTTP/1.1\r\nHost: %s\r\nContent-Length: %d\r\n\r\n", token, s.cfg.Addr, len(payload))
	if _, err := conn.Write(append([]byte(head), payload[:n]...)); err != nil {
		t.Fatalf("write: %v", err)
	}
	part := filepath.Join(s.cfg.FilesPath, fileID+".part")
	want := blob.CipherLen(int64(n) / blob.ChunkSize * blob.ChunkSize)
	eventually(t, "the server seals the chunks it received", func() bool {
		info, err := os.Stat(part)
		return err == nil && info.Size() >= want
	})
	_ = conn.Close()
}

// readEverything reads every file under dir into memory.
func readEverything(t *testing.T, dir string) map[string][]byte {
	t.Helper()
	files := map[string][]byte{}
	err := filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		files[path] = data
		return nil
	})
	if err != nil {
		t.Fatalf("walk %s: %v", dir, err)
	}
	return files
}

// noneInTheClear fails on the first file holding any of the needles.
func noneInTheClear(t *testing.T, when string, files map[string][]byte, needles map[string][]byte) {
	t.Helper()
	for path, data := range files {
		if found := containsAny(data, needles); found != "" {
			t.Fatalf("%s: %s holds %s in the clear", when, filepath.Base(path), found)
		}
	}
}

func TestNothingOnTheServersDiskIsInTheClear(t *testing.T) {
	cfg := testRunConfig(t)
	cfg.PublicAddr = "nox-at-rest-marker.example.org:8443"
	cfg.OnionAddr = testOnionAddr
	logs, stop := runServer(t, cfg)
	s := pairOnRun(t, cfg, logs)
	const marker = "AT-REST-MARKER-047"

	// A chat and messages.
	created := s.ok(t, `{"id":%d,"cmd":"chat.create","data":{"name":%q}}`, marker+" chat")
	var chat protocol.Chat
	mustUnmarshal(t, created["chat"], &chat)
	for i := range 20 {
		s.ok(t, `{"id":%d,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"m%d","body":{"type":"text","text":"%s message %d"}}}`,
			chat.ChatID, i, marker, i)
	}

	// A finished attachment, sent.
	content := bytes.Repeat([]byte(marker+"-bytes "), 3*blob.ChunkSize/len(marker))
	fileID, token, _ := declareRun(t, s, marker+"-photo.jpg", len(content))
	if code := s.put(t, token, content); code != http.StatusNoContent {
		t.Fatalf("PUT = %d", code)
	}
	s.ok(t, `{"id":%d,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"f1","attachment":{"file_id":%q}}}`,
		chat.ChatID, fileID)

	// An upload broken off half-way: its part holds two sealed chunks.
	halfID, halfToken, _ := declareRun(t, s, "half.bin", len(content))
	s.putAndBreak(t, halfToken, halfID, content, 2*blob.ChunkSize+500)

	// An invite still open, and a machine link.
	s.ok(t, `{"id":%d,"cmd":"device.invite","data":{}}`)
	if _, err := RequestMachineLink(t.Context(), cfg.StatusAddr); err != nil {
		t.Fatalf("RequestMachineLink: %v", err)
	}

	dir := filepath.Dir(cfg.DBPath)
	plain := map[string][]byte{
		"a message":          []byte(marker + " message"),
		"the chat name":      []byte(marker + " chat"),
		"the folded name":    []byte(strings.ToLower(marker) + " chat"),
		"an attachment":      []byte(marker + "-bytes"),
		"a file name":        []byte(marker + "-photo"),
		"the public address": []byte("nox-at-rest-marker"),
		"the onion address":  []byte(strings.TrimSuffix(testOnionAddr, ".onion")),
		"the device key":     []byte(s.dev.pub),
		"the device key raw": s.dev.priv.Public().(ed25519.PublicKey),
		"the server key":     []byte(base64.StdEncoding.EncodeToString(s.serverKey)),
		"the server key raw": s.serverKey,
		"a schema":           []byte("CREATE TABLE"),
	}
	// While it runs: the WAL holds the newest pages, and is encrypted too.
	noneInTheClear(t, "running", readEverything(t, dir), plain)

	s.close()
	if err := stop(); err != nil {
		t.Fatalf("Run returned %v", err)
	}
	files := readEverything(t, dir)
	noneInTheClear(t, "stopped", files, plain)

	// The secrets themselves, read out of the database with its key once
	// the files were taken: the machine's private key, every pairing token.
	d, err := db.Open(cfg.DBPath, runDataKey(t, cfg))
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	defer func() { _ = d.Close() }()
	secrets := map[string][]byte{}
	var seed string
	if err := d.Read.QueryRow("SELECT private_key FROM server_identity WHERE id = 1").Scan(&seed); err != nil {
		t.Fatalf("read the key: %v", err)
	}
	secrets["the server's private key"] = []byte(seed)
	if raw, err := base64.StdEncoding.DecodeString(seed); err == nil {
		secrets["the server's private key raw"] = raw
	}
	for name, token := range tokensIn(t, d.Read) {
		secrets[name] = []byte(token)
	}
	if len(secrets) < 4 {
		t.Fatalf("only %d secrets to look for: the run did not leave the tokens it was meant to", len(secrets))
	}
	noneInTheClear(t, "stopped", files, secrets)

	// And what is there is what the data model says: the database and its
	// key file, the finished file and the part with its record.
	for _, want := range []string{cfg.DBPath, cfg.KeyPath(), filepath.Join(cfg.FilesPath, fileID),
		filepath.Join(cfg.FilesPath, halfID+".part"), filepath.Join(cfg.FilesPath, halfID+".synced")} {
		if _, ok := files[want]; !ok {
			t.Fatalf("%s is not on disk: the scan looked at less than it should", filepath.Base(want))
		}
	}
}

// tokensIn lists every pairing token the database holds.
func tokensIn(t *testing.T, read *sql.DB) map[string]string {
	t.Helper()
	rows, err := read.QueryContext(context.Background(), "SELECT kind, token FROM pair_tokens")
	if err != nil {
		t.Fatalf("query tokens: %v", err)
	}
	defer func() { _ = rows.Close() }()
	tokens := map[string]string{}
	for rows.Next() {
		var kind, token string
		if err := rows.Scan(&kind, &token); err != nil {
			t.Fatalf("scan: %v", err)
		}
		tokens[fmt.Sprintf("a %s token #%d", kind, len(tokens))] = token
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("rows: %v", err)
	}
	return tokens
}

// declareRun sends file.uploadBegin on a run session.
func declareRun(t *testing.T, s *runSession, name string, size int) (string, string, int64) {
	t.Helper()
	data := s.ok(t, `{"id":%d,"cmd":"file.uploadBegin","data":{"name":%q,"size":%d,"mime":"application/octet-stream"}}`, name, size)
	var fileID, token string
	var received int64
	mustUnmarshal(t, data["file_id"], &fileID)
	mustUnmarshal(t, data["upload_token"], &token)
	mustUnmarshal(t, data["received"], &received)
	return fileID, token, received
}
