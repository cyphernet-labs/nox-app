package store

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"nox.app/client-backend/internal/db"
	"nox.app/client-backend/internal/protocol"
)

func newStore(t *testing.T) *Store {
	t.Helper()
	path := filepath.Join(t.TempDir(), "store.db")
	d, err := db.Open(path)
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	t.Cleanup(func() { _ = d.Close() })
	if _, err := db.Migrate(context.Background(), d.Write, os.DirFS("../../migrations")); err != nil {
		t.Fatalf("db.Migrate: %v", err)
	}
	return New(d.Read, d.Write)
}

func textBody(text string) json.RawMessage {
	return json.RawMessage(`{"type":"text","text":` + string(mustJSON(text)) + `}`)
}

func mustJSON(v any) []byte {
	raw, err := json.Marshal(v)
	if err != nil {
		panic(err)
	}
	return raw
}

func TestCreateChatEmitsAtomicEvent(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	chat, ev, err := s.CreateChat(ctx, "smoke", "Anna", 100)
	if err != nil {
		t.Fatalf("CreateChat: %v", err)
	}
	if ev.Seq != 1 || ev.Type != protocol.EventChatCreated {
		t.Fatalf("event = %+v, want seq 1 chat.created", ev)
	}

	var payload protocol.Chat
	if err := json.Unmarshal(ev.Payload, &payload); err != nil {
		t.Fatalf("payload: %v", err)
	}
	if payload != chat {
		t.Fatalf("payload = %+v, chat = %+v", payload, chat)
	}
	if chat.CreatedByLabel != "Anna" || chat.LastActivityAt != 100 {
		t.Fatalf("chat = %+v", chat)
	}
}

func TestCreateChatNameTakenCaseInsensitiveLeavesNoEvent(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	if _, _, err := s.CreateChat(ctx, "General", "Anna", 100); err != nil {
		t.Fatalf("first CreateChat: %v", err)
	}
	_, _, err := s.CreateChat(ctx, "general", "Bob", 101)
	if !errors.Is(err, ErrNameTaken) {
		t.Fatalf("err = %v, want ErrNameTaken", err)
	}

	events, err := s.EventsSince(ctx, 0)
	if err != nil {
		t.Fatalf("EventsSince: %v", err)
	}
	if len(events) != 1 {
		t.Fatalf("events = %d, want 1 (failed create must leave no event)", len(events))
	}
}

func TestSendMessageSeqAndIdempotency(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	chat, _, err := s.CreateChat(ctx, "smoke", "Anna", 100)
	if err != nil {
		t.Fatalf("CreateChat: %v", err)
	}

	first, ev, created, err := s.SendMessage(ctx, chat.ChatID, "cmid-1", "Anna", "Anna", textBody("hello"), 101)
	if err != nil || !created {
		t.Fatalf("SendMessage: created=%v err=%v", created, err)
	}
	if first.Seq != 2 || ev.Seq != 2 {
		t.Fatalf("seq = %d/%d, want 2 (after chat.created)", first.Seq, ev.Seq)
	}

	dup, dupEv, created, err := s.SendMessage(ctx, chat.ChatID, "cmid-1", "Anna", "Anna", textBody("hello"), 999)
	if err != nil {
		t.Fatalf("duplicate SendMessage: %v", err)
	}
	if created {
		t.Fatal("duplicate send must not create")
	}
	if dup.MessageID != first.MessageID || dup.SentAt != first.SentAt {
		t.Fatalf("duplicate returned %+v, want original %+v", dup, first)
	}
	if dupEv.Seq != 0 {
		t.Fatalf("duplicate produced event %+v", dupEv)
	}

	events, err := s.EventsSince(ctx, 0)
	if err != nil {
		t.Fatalf("EventsSince: %v", err)
	}
	if len(events) != 2 {
		t.Fatalf("events = %d, want 2", len(events))
	}
}

func TestSendMessageUnknownChat(t *testing.T) {
	s := newStore(t)
	_, _, _, err := s.SendMessage(context.Background(), "c_missing", "cmid-1", "a", "a", textBody("x"), 1)
	if !errors.Is(err, ErrChatNotFound) {
		t.Fatalf("err = %v, want ErrChatNotFound", err)
	}
}

func TestEventsSinceOrderingAndRepeatability(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	chat, _, err := s.CreateChat(ctx, "smoke", "Anna", 100)
	if err != nil {
		t.Fatalf("CreateChat: %v", err)
	}
	for i, id := range []string{"a", "b", "c"} {
		if _, _, _, err := s.SendMessage(ctx, chat.ChatID, id, "Anna", "Anna", textBody(id), int64(101+i)); err != nil {
			t.Fatalf("SendMessage %s: %v", id, err)
		}
	}

	firstRun, err := s.EventsSince(ctx, 1)
	if err != nil {
		t.Fatalf("EventsSince: %v", err)
	}
	if len(firstRun) != 3 {
		t.Fatalf("events since 1 = %d, want 3", len(firstRun))
	}
	for i, ev := range firstRun {
		if ev.Seq != int64(2+i) {
			t.Fatalf("ordering broken: %+v", firstRun)
		}
	}

	secondRun, err := s.EventsSince(ctx, 1)
	if err != nil {
		t.Fatalf("EventsSince repeat: %v", err)
	}
	for i := range firstRun {
		if string(firstRun[i].Payload) != string(secondRun[i].Payload) {
			t.Fatal("replay must be byte-identical")
		}
	}

	cursor, err := s.Cursor(ctx)
	if err != nil {
		t.Fatalf("Cursor: %v", err)
	}
	if cursor != 4 {
		t.Fatalf("cursor = %d, want 4", cursor)
	}
}

func TestPreviewFold(t *testing.T) {
	tests := []struct {
		name string
		body json.RawMessage
		want string
	}{
		{"multiline text folds to one line", textBody("a\nb\tc"), "a b c"},
		{"non-text body yields empty preview", json.RawMessage(`{"type":"blob","data":"x"}`), ""},
		{"invalid json yields empty preview", json.RawMessage(`nope`), ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := previewFromBody(tt.body); got != tt.want {
				t.Fatalf("preview = %q, want %q", got, tt.want)
			}
		})
	}

	t.Run("long text truncated to 120 runes", func(t *testing.T) {
		long := make([]rune, 200)
		for i := range long {
			long[i] = 'я'
		}
		got := previewFromBody(textBody(string(long)))
		if len([]rune(got)) != 120 {
			t.Fatalf("preview runes = %d, want 120", len([]rune(got)))
		}
	})
}
