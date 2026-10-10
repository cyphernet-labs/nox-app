package store

import (
	"context"
	"encoding/json"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sync"
	"testing"

	"nox.app/client-backend/internal/db"
	"nox.app/client-backend/internal/protocol"
)

// migrationsFS is the on-disk migrations directory, shared by tests that open
// a database themselves rather than through newStore.
func migrationsFS(t *testing.T) fs.FS {
	t.Helper()
	return os.DirFS("../../migrations")
}

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

	chat, ev, _, err := s.CreateChat(ctx, "", "smoke", "Anna", 100)
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

	if _, _, _, err := s.CreateChat(ctx, "", "General", "Anna", 100); err != nil {
		t.Fatalf("first CreateChat: %v", err)
	}
	_, _, _, err := s.CreateChat(ctx, "", "general", "Bob", 101)
	if !errors.Is(err, ErrNameTaken) {
		t.Fatalf("err = %v, want ErrNameTaken", err)
	}

	// Case folding must be Unicode-aware, not SQLite's ASCII-only lower().
	if _, _, _, err := s.CreateChat(ctx, "", "Общий", "Anna", 102); err != nil {
		t.Fatalf("Cyrillic CreateChat: %v", err)
	}
	if _, _, _, err := s.CreateChat(ctx, "", "оБЩИЙ", "Bob", 103); !errors.Is(err, ErrNameTaken) {
		t.Fatalf("Cyrillic duplicate err = %v, want ErrNameTaken", err)
	}

	events, err := s.EventsSince(ctx, 0)
	if err != nil {
		t.Fatalf("EventsSince: %v", err)
	}
	if len(events) != 2 {
		t.Fatalf("events = %d, want 2 (failed creates must leave no event)", len(events))
	}
}

// Chat ids a device mints (041): c_ and 32 lowercase hex digits. The store
// does not check the shape - the handler does - but the tests use real ones.
const (
	deviceChatID      = "c_5f0e9c1d2a3b4c5d6e7f8091a2b3c4d5"
	otherDeviceChatID = "c_0123456789abcdef0123456789abcdef"
)

func TestCreateChatWithDeviceIDCreatesItUnderThatIDWithOneEvent(t *testing.T) {
	s := newStore(t)
	ctx := t.Context()

	chat, ev, created, err := s.CreateChat(ctx, deviceChatID, "Kitchen", "Anna", 100)
	if err != nil || !created {
		t.Fatalf("CreateChat: created=%v err=%v", created, err)
	}
	if chat.ChatID != deviceChatID {
		t.Fatalf("chat_id = %q, want the device's %q", chat.ChatID, deviceChatID)
	}
	var payload protocol.Chat
	if err := json.Unmarshal(ev.Payload, &payload); err != nil || payload != chat {
		t.Fatalf("event payload = %+v err=%v, want %+v", payload, err, chat)
	}

	events, err := s.EventsSince(ctx, 0)
	if err != nil {
		t.Fatalf("EventsSince: %v", err)
	}
	if len(events) != 1 || events[0].Type != protocol.EventChatCreated || events[0].Seq != ev.Seq {
		t.Fatalf("events = %+v, want exactly the one chat.created", events)
	}
	if got, err := s.GetChat(ctx, deviceChatID); err != nil || got != chat {
		t.Fatalf("GetChat = %+v err=%v, want %+v", got, err, chat)
	}
}

func TestCreateChatRepeatOfDeviceIDReturnsTheChatAndWritesNothing(t *testing.T) {
	s := newStore(t)
	ctx := t.Context()

	first, _, _, err := s.CreateChat(ctx, deviceChatID, "Kitchen", "Anna", 100)
	if err != nil {
		t.Fatalf("CreateChat: %v", err)
	}

	// The device lost the reply and sends the same command again. Its name is
	// taken by now - by this very chat - and a different clock and creator
	// prove what comes back is the stored row, not a card built from the call.
	again, ev, created, err := s.CreateChat(ctx, deviceChatID, "Kitchen", "Bob", 999)
	if err != nil {
		t.Fatalf("repeat: %v", err)
	}
	if created {
		t.Fatal("a repeat must not create")
	}
	if again != first {
		t.Fatalf("repeat = %+v, want the stored %+v", again, first)
	}
	if ev.Seq != 0 {
		t.Fatalf("repeat produced event %+v", ev)
	}

	chats, _, err := s.ListChats(ctx, 1, 10, "")
	if err != nil || len(chats) != 1 {
		t.Fatalf("chats = %d err=%v, want exactly 1", len(chats), err)
	}
	events, err := s.EventsSince(ctx, 0)
	if err != nil || len(events) != 1 {
		t.Fatalf("events = %d err=%v, want exactly 1", len(events), err)
	}
}

func TestCreateChatRepeatAfterRenameReturnsTheCurrentName(t *testing.T) {
	s := newStore(t)
	ctx := t.Context()

	if _, _, _, err := s.CreateChat(ctx, deviceChatID, "Kitchen", "Anna", 100); err != nil {
		t.Fatalf("CreateChat: %v", err)
	}
	renamed, _, _, err := s.RenameChat(ctx, deviceChatID, "Pantry")
	if err != nil {
		t.Fatalf("RenameChat: %v", err)
	}
	cursor, err := s.Cursor(ctx)
	if err != nil {
		t.Fatalf("Cursor: %v", err)
	}

	// The repeat still carries the name the device sent the first time.
	again, _, created, err := s.CreateChat(ctx, deviceChatID, "Kitchen", "Anna", 200)
	if err != nil || created {
		t.Fatalf("repeat: created=%v err=%v", created, err)
	}
	if again != renamed {
		t.Fatalf("repeat = %+v, want the chat as it is now %+v", again, renamed)
	}
	after, err := s.Cursor(ctx)
	if err != nil {
		t.Fatalf("Cursor: %v", err)
	}
	if after != cursor {
		t.Fatalf("repeat grew the log: %d -> %d", cursor, after)
	}
}

func TestCreateChatRepeatNeverReturnsNameTaken(t *testing.T) {
	s := newStore(t)
	ctx := t.Context()

	if _, _, _, err := s.CreateChat(ctx, deviceChatID, "Kitchen", "Anna", 100); err != nil {
		t.Fatalf("CreateChat: %v", err)
	}
	if _, _, _, err := s.RenameChat(ctx, deviceChatID, "Pantry"); err != nil {
		t.Fatalf("RenameChat: %v", err)
	}
	// ANOTHER chat now holds the name the device first sent ...
	if _, _, _, err := s.CreateChat(ctx, "", "kitchen", "Anna", 200); err != nil {
		t.Fatalf("CreateChat other: %v", err)
	}

	// ... and the repeat still finds its own chat: the id is looked up before
	// the name is checked.
	again, _, created, err := s.CreateChat(ctx, deviceChatID, "Kitchen", "Anna", 300)
	if errors.Is(err, ErrNameTaken) {
		t.Fatal("a repeat of an existing chat_id must never be name_taken")
	}
	if err != nil || created || again.ChatID != deviceChatID || again.Name != "Pantry" {
		t.Fatalf("repeat = %+v created=%v err=%v, want the device's chat as it is now", again, created, err)
	}
}

func TestCreateChatNewDeviceIDWithTakenNameIsNameTaken(t *testing.T) {
	s := newStore(t)
	ctx := t.Context()

	if _, _, _, err := s.CreateChat(ctx, deviceChatID, "Kitchen", "Anna", 100); err != nil {
		t.Fatalf("CreateChat: %v", err)
	}
	_, _, created, err := s.CreateChat(ctx, otherDeviceChatID, "KITCHEN", "Anna", 200)
	if !errors.Is(err, ErrNameTaken) || created {
		t.Fatalf("err = %v created=%v, want ErrNameTaken", err, created)
	}
	if _, err := s.GetChat(ctx, otherDeviceChatID); !errors.Is(err, ErrChatNotFound) {
		t.Fatalf("a refused create left a row behind: err = %v", err)
	}
	events, err := s.EventsSince(ctx, 0)
	if err != nil || len(events) != 1 {
		t.Fatalf("events = %d err=%v, want only the first chat.created", len(events), err)
	}
}

func TestCreateChatWithoutIDMintsAServerID(t *testing.T) {
	s := newStore(t)
	ctx := t.Context()

	chat, ev, created, err := s.CreateChat(ctx, "", "Kitchen", "Anna", 100)
	if err != nil || !created {
		t.Fatalf("CreateChat: created=%v err=%v", created, err)
	}
	if !regexp.MustCompile(`^c_[0-9a-f]{16}$`).MatchString(chat.ChatID) {
		t.Fatalf("chat_id = %q, want the server's c_<16 hex>", chat.ChatID)
	}
	var payload protocol.Chat
	if err := json.Unmarshal(ev.Payload, &payload); err != nil || payload.ChatID != chat.ChatID {
		t.Fatalf("event chat_id = %q err=%v, want %q", payload.ChatID, err, chat.ChatID)
	}
}

// Two repeats racing each other - the reply was lost twice, or two passes of
// the device's queue overlapped - must still make one chat. The id lookup runs
// inside the write transaction, so the second waits for the first and finds
// its row; a lookup outside it would see "absent" twice and answer the loser
// with name_taken.
func TestCreateChatConcurrentRepeatsCreateOneChat(t *testing.T) {
	s := newStore(t)
	ctx := t.Context()

	const attempts = 8
	type outcome struct {
		chat    protocol.Chat
		created bool
		err     error
	}
	results := make([]outcome, attempts)
	var wg sync.WaitGroup
	for i := range attempts {
		wg.Go(func() {
			chat, _, created, err := s.CreateChat(ctx, deviceChatID, "Kitchen", "Anna", 100)
			results[i] = outcome{chat: chat, created: created, err: err}
		})
	}
	wg.Wait()

	creators := 0
	for i, r := range results {
		if r.err != nil {
			t.Fatalf("attempt %d: %v", i, r.err)
		}
		if r.chat.ChatID != deviceChatID {
			t.Fatalf("attempt %d chat_id = %q, want %q", i, r.chat.ChatID, deviceChatID)
		}
		if r.created {
			creators++
		}
	}
	if creators != 1 {
		t.Fatalf("attempts that created = %d, want exactly 1", creators)
	}
	events, err := s.EventsSince(ctx, 0)
	if err != nil || len(events) != 1 {
		t.Fatalf("events = %d err=%v, want exactly 1", len(events), err)
	}
}

func TestSendMessageSeqAndIdempotency(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	chat, _, _, err := s.CreateChat(ctx, "", "smoke", "Anna", 100)
	if err != nil {
		t.Fatalf("CreateChat: %v", err)
	}

	first, ev, created, err := s.SendMessage(ctx, chat.ChatID, "cmid-1", person(t, s, "Anna"), textBody("hello"), "", 101)
	if err != nil || !created {
		t.Fatalf("SendMessage: created=%v err=%v", created, err)
	}
	if first.Seq != 2 || ev.Seq != 2 {
		t.Fatalf("seq = %d/%d, want 2 (after chat.created)", first.Seq, ev.Seq)
	}

	dup, dupEv, created, err := s.SendMessage(ctx, chat.ChatID, "cmid-1", person(t, s, "Anna"), textBody("hello"), "", 999)
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
	_, _, _, err := s.SendMessage(context.Background(), "c_missing", "cmid-1", person(t, s, "a"), textBody("x"), "", 1)
	if !errors.Is(err, ErrChatNotFound) {
		t.Fatalf("err = %v, want ErrChatNotFound", err)
	}
}

func TestEventsSinceOrderingAndRepeatability(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	chat, _, _, err := s.CreateChat(ctx, "", "smoke", "Anna", 100)
	if err != nil {
		t.Fatalf("CreateChat: %v", err)
	}
	for i, id := range []string{"a", "b", "c"} {
		if _, _, _, err := s.SendMessage(ctx, chat.ChatID, id, person(t, s, "Anna"), textBody(id), "", int64(101+i)); err != nil {
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
			if got := previewFor(tt.body, ""); got != tt.want {
				t.Fatalf("preview = %q, want %q", got, tt.want)
			}
		})
	}

	t.Run("long text truncated to 120 runes", func(t *testing.T) {
		long := make([]rune, 200)
		for i := range long {
			long[i] = 'я'
		}
		got := previewFor(textBody(string(long)), "")
		if len([]rune(got)) != 120 {
			t.Fatalf("preview runes = %d, want 120", len([]rune(got)))
		}
	})
}

func TestGetChatMatchesCreatedCardFieldForField(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	created, _, _, err := s.CreateChat(ctx, "", "Field parity", "Anna", 100)
	if err != nil {
		t.Fatalf("CreateChat: %v", err)
	}
	got, err := s.GetChat(ctx, created.ChatID)
	if err != nil {
		t.Fatalf("GetChat: %v", err)
	}
	if got != created {
		t.Fatalf("GetChat = %+v, want %+v", got, created)
	}

	if _, err := s.GetChat(ctx, "c_missing"); !errors.Is(err, ErrChatNotFound) {
		t.Fatalf("missing chat err = %v, want ErrChatNotFound", err)
	}
}

func TestListChatsOrderQueryAndPaging(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	// Different activity times; two chats share one (tiebreaker case).
	mk := func(name string, at int64) protocol.Chat {
		chat, _, _, err := s.CreateChat(ctx, "", name, "Anna", at)
		if err != nil {
			t.Fatalf("CreateChat %s: %v", name, err)
		}
		return chat
	}
	mk("Kitchen", 100)
	obshchiy := mk("Общий", 300)
	tieA := mk("Tie A", 200)
	tieB := mk("Tie B", 200)

	page, hasMore, err := s.ListChats(ctx, 1, 3, "")
	if err != nil {
		t.Fatalf("ListChats: %v", err)
	}
	if !hasMore || len(page) != 3 {
		t.Fatalf("page1 = %d rows, hasMore=%v", len(page), hasMore)
	}
	if page[0].ChatID != obshchiy.ChatID {
		t.Fatalf("page1[0] = %s, want the most recent", page[0].Name)
	}
	// Equal activity: stable ascending chat_id order between the two.
	wantSecond, wantThird := tieA, tieB
	if tieB.ChatID < tieA.ChatID {
		wantSecond, wantThird = tieB, tieA
	}
	if page[1].ChatID != wantSecond.ChatID || page[2].ChatID != wantThird.ChatID {
		t.Fatalf("tiebreaker order = %s, %s", page[1].Name, page[2].Name)
	}

	page2, hasMore, err := s.ListChats(ctx, 2, 3, "")
	if err != nil || hasMore || len(page2) != 1 || page2[0].Name != "Kitchen" {
		t.Fatalf("page2 = %+v hasMore=%v err=%v", page2, hasMore, err)
	}

	// Unicode case-insensitive substring query.
	found, hasMore, err := s.ListChats(ctx, 1, 10, "оБщИ")
	if err != nil || hasMore || len(found) != 1 || found[0].ChatID != obshchiy.ChatID {
		t.Fatalf("query result = %+v hasMore=%v err=%v", found, hasMore, err)
	}

	// Page beyond the data: empty, no error.
	empty, hasMore, err := s.ListChats(ctx, 99, 10, "")
	if err != nil || hasMore || len(empty) != 0 {
		t.Fatalf("far page = %d rows hasMore=%v err=%v", len(empty), hasMore, err)
	}
}

func TestListMessagesBackwardPaging(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	chat, _, _, err := s.CreateChat(ctx, "", "history", "Anna", 100)
	if err != nil {
		t.Fatalf("CreateChat: %v", err)
	}
	var seqs []int64
	for i := range 5 {
		msg, _, _, err := s.SendMessage(ctx, chat.ChatID, mustString(i), person(t, s, "Anna"), textBody("m"), "", int64(101+i))
		if err != nil {
			t.Fatalf("SendMessage %d: %v", i, err)
		}
		seqs = append(seqs, msg.Seq)
	}

	// Tail page of 2: the two newest, ascending, more behind.
	tail, hasMore, err := s.ListMessages(ctx, chat.ChatID, 0, 2)
	if err != nil || !hasMore || len(tail) != 2 {
		t.Fatalf("tail = %d rows hasMore=%v err=%v", len(tail), hasMore, err)
	}
	if tail[0].Seq != seqs[3] || tail[1].Seq != seqs[4] {
		t.Fatalf("tail seqs = %d,%d want %d,%d", tail[0].Seq, tail[1].Seq, seqs[3], seqs[4])
	}

	// Middle page: strictly older than the boundary, boundary excluded.
	mid, hasMore, err := s.ListMessages(ctx, chat.ChatID, tail[0].Seq, 2)
	if err != nil || !hasMore || len(mid) != 2 || mid[0].Seq != seqs[1] || mid[1].Seq != seqs[2] {
		t.Fatalf("mid = %+v hasMore=%v err=%v", mid, hasMore, err)
	}

	// Oldest page: the rest, no more behind.
	oldest, hasMore, err := s.ListMessages(ctx, chat.ChatID, mid[0].Seq, 2)
	if err != nil || hasMore || len(oldest) != 1 || oldest[0].Seq != seqs[0] {
		t.Fatalf("oldest = %+v hasMore=%v err=%v", oldest, hasMore, err)
	}

	// Empty chat: empty page, hasMore false.
	empty, _, _, err := s.CreateChat(ctx, "", "empty", "Anna", 200)
	if err != nil {
		t.Fatalf("CreateChat empty: %v", err)
	}
	none, hasMore, err := s.ListMessages(ctx, empty.ChatID, 0, 10)
	if err != nil || hasMore || len(none) != 0 {
		t.Fatalf("empty chat page = %d rows hasMore=%v err=%v", len(none), hasMore, err)
	}
}

func TestRenameChatEventNoOpAndUniqueness(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	chat, _, _, err := s.CreateChat(ctx, "", "Old name", "Anna", 100)
	if err != nil {
		t.Fatalf("CreateChat: %v", err)
	}
	if _, _, _, err := s.CreateChat(ctx, "", "Занято", "Bob", 100); err != nil {
		t.Fatalf("CreateChat second: %v", err)
	}
	if _, _, _, err := s.SendMessage(ctx, chat.ChatID, "r1", person(t, s, "Anna"), textBody("hi"), "", 150); err != nil {
		t.Fatalf("SendMessage: %v", err)
	}
	before, err := s.GetChat(ctx, chat.ChatID)
	if err != nil {
		t.Fatalf("GetChat: %v", err)
	}

	// Successful rename: event with the full card, activity untouched.
	renamed, ev, changed, err := s.RenameChat(ctx, chat.ChatID, "New name")
	if err != nil || !changed {
		t.Fatalf("RenameChat: changed=%v err=%v", changed, err)
	}
	if renamed.Name != "New name" || renamed.LastActivityAt != before.LastActivityAt || renamed.LastMessagePreview != before.LastMessagePreview {
		t.Fatalf("renamed = %+v, want name change only over %+v", renamed, before)
	}
	if ev.Type != protocol.EventChatUpdated {
		t.Fatalf("event type = %s", ev.Type)
	}
	var payload protocol.Chat
	if err := json.Unmarshal(ev.Payload, &payload); err != nil || payload != renamed {
		t.Fatalf("event payload = %+v err=%v, want %+v", payload, err, renamed)
	}

	cursorAfterRename, err := s.Cursor(ctx)
	if err != nil {
		t.Fatalf("Cursor: %v", err)
	}

	// Exact no-op: no event row, same card.
	same, _, changed, err := s.RenameChat(ctx, chat.ChatID, "New name")
	if err != nil || changed || same != renamed {
		t.Fatalf("no-op rename: %+v changed=%v err=%v", same, changed, err)
	}
	if cur, _ := s.Cursor(ctx); cur != cursorAfterRename {
		t.Fatalf("no-op grew the log: %d -> %d", cursorAfterRename, cur)
	}

	// Case-only change is a REAL rename with an event.
	upper, _, changed, err := s.RenameChat(ctx, chat.ChatID, "NEW NAME")
	if err != nil || !changed || upper.Name != "NEW NAME" {
		t.Fatalf("case-only rename: %+v changed=%v err=%v", upper, changed, err)
	}

	// Unicode case-insensitive collision with the other chat.
	if _, _, _, err := s.RenameChat(ctx, chat.ChatID, "зАНЯТО"); !errors.Is(err, ErrNameTaken) {
		t.Fatalf("collision err = %v, want ErrNameTaken", err)
	}
	// Unknown chat.
	if _, _, _, err := s.RenameChat(ctx, "c_missing", "x"); !errors.Is(err, ErrChatNotFound) {
		t.Fatalf("missing err = %v, want ErrChatNotFound", err)
	}
}

func TestNameAvailable(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	chat, _, _, err := s.CreateChat(ctx, "", "Моё имя", "Anna", 100)
	if err != nil {
		t.Fatalf("CreateChat: %v", err)
	}

	cases := []struct {
		name    string
		exclude string
		want    bool
	}{
		{"Свободно", "", true},
		{"моё имя", "", false},
		{"МОЁ ИМЯ", chat.ChatID, true},
		{"моё имя", "c_other", false},
	}
	for _, tc := range cases {
		got, err := s.NameAvailable(ctx, tc.name, tc.exclude)
		if err != nil || got != tc.want {
			t.Fatalf("NameAvailable(%q, %q) = %v err=%v, want %v", tc.name, tc.exclude, got, err, tc.want)
		}
	}
}

func mustString(i int) string {
	return string(mustJSON(i))
}

func TestListChatsHugePageDoesNotPanic(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	if _, _, _, err := s.CreateChat(ctx, "", "victim", "Anna", 100); err != nil {
		t.Fatalf("CreateChat: %v", err)
	}
	// (page-1)*pageSize wraps negative without the guard; the slice
	// expression then panics (review finding, remote-triggerable).
	page, hasMore, err := s.ListChats(ctx, 92233720368547760, 100, "")
	if err != nil || hasMore || len(page) != 0 {
		t.Fatalf("huge page = %d rows hasMore=%v err=%v, want empty", len(page), hasMore, err)
	}
}

func TestNameUniquenessUsesCaseFoldingNotLowercase(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	// Greek final sigma: ToLower keeps sigma and final sigma distinct, so a
	// lowercase-based check would admit this duplicate.
	if _, _, _, err := s.CreateChat(ctx, "", "ΒΌΛΟΣ", "Anna", 100); err != nil {
		t.Fatalf("CreateChat: %v", err)
	}
	if _, _, _, err := s.CreateChat(ctx, "", "βόλος", "Bob", 101); !errors.Is(err, ErrNameTaken) {
		t.Fatalf("final-sigma duplicate err = %v, want ErrNameTaken", err)
	}
	if free, err := s.NameAvailable(ctx, "βόλος", ""); err != nil || free {
		t.Fatalf("NameAvailable sigma = %v err=%v, want taken", free, err)
	}
	// The search filter shares the same folding.
	found, _, err := s.ListChats(ctx, 1, 10, "βόλος")
	if err != nil || len(found) != 1 {
		t.Fatalf("sigma search = %d rows err=%v", len(found), err)
	}
}

func TestListChatsQueryOfSpacesMeansNoFilter(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	if _, _, _, err := s.CreateChat(ctx, "", "one", "Anna", 100); err != nil {
		t.Fatalf("CreateChat: %v", err)
	}
	if _, _, _, err := s.CreateChat(ctx, "", "two", "Anna", 200); err != nil {
		t.Fatalf("CreateChat: %v", err)
	}
	page, _, err := s.ListChats(ctx, 1, 10, "   ")
	if err != nil || len(page) != 2 {
		t.Fatalf("spaces query = %d rows err=%v, want all 2", len(page), err)
	}
}

func TestFileLifecycleAndAttachmentBinding(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	chat, _, _, err := s.CreateChat(ctx, "", "files", "Anna", 100)
	if err != nil {
		t.Fatalf("CreateChat: %v", err)
	}
	att, err := s.CreateUpload(ctx, "report.pdf", 12345, "application/pdf", 200)
	if err != nil {
		t.Fatalf("CreateUpload: %v", err)
	}
	if att.ExpiresAt != 200+attachmentLifetimeSeconds {
		t.Fatalf("expires_at = %d", att.ExpiresAt)
	}

	// Sending before the bytes are uploaded is rejected.
	if _, _, _, err := s.SendMessage(ctx, chat.ChatID, "a1", person(t, s, "Anna"), nil, att.FileID, 300); !errors.Is(err, ErrFileNotReady) {
		t.Fatalf("unready err = %v, want ErrFileNotReady", err)
	}
	if err := s.MarkUploaded(ctx, att.FileID); err != nil {
		t.Fatalf("MarkUploaded: %v", err)
	}
	if err := s.MarkUploaded(ctx, att.FileID); !errors.Is(err, ErrFileNotFound) {
		t.Fatalf("second MarkUploaded err = %v, want guarded failure", err)
	}

	// Attachment-only send: echo carries the full attachment, preview = name.
	msg, ev, created, err := s.SendMessage(ctx, chat.ChatID, "a1", person(t, s, "Anna"), nil, att.FileID, 300)
	if err != nil || !created || msg.Attachment == nil {
		t.Fatalf("send: %+v created=%v err=%v", msg, created, err)
	}
	if *msg.Attachment != att {
		t.Fatalf("echo attachment = %+v, want %+v", msg.Attachment, att)
	}
	var evMsg protocol.Message
	if err := json.Unmarshal(ev.Payload, &evMsg); err != nil || evMsg.Attachment == nil || *evMsg.Attachment != att {
		t.Fatalf("event payload attachment = %+v err=%v", evMsg.Attachment, err)
	}
	got, err := s.GetChat(ctx, chat.ChatID)
	if err != nil || got.LastMessagePreview != "report.pdf" {
		t.Fatalf("preview = %q err=%v, want file name", got.LastMessagePreview, err)
	}

	// Idempotent replay returns the same attachment, no new event.
	replay, _, created, err := s.SendMessage(ctx, chat.ChatID, "a1", person(t, s, "Anna"), nil, att.FileID, 400)
	if err != nil || created || replay.Attachment == nil || *replay.Attachment != att {
		t.Fatalf("replay: %+v created=%v err=%v", replay, created, err)
	}

	// The file is bound: a second message cannot reference it.
	if _, _, _, err := s.SendMessage(ctx, chat.ChatID, "a2", person(t, s, "Anna"), nil, att.FileID, 500); !errors.Is(err, ErrFileTaken) {
		t.Fatalf("rebind err = %v, want ErrFileTaken", err)
	}
	// Unknown file.
	if _, _, _, err := s.SendMessage(ctx, chat.ChatID, "a3", person(t, s, "Anna"), nil, "f_missing", 500); !errors.Is(err, ErrFileNotFound) {
		t.Fatalf("unknown file err = %v, want ErrFileNotFound", err)
	}

	// History returns the attachment too.
	page, _, err := s.ListMessages(ctx, chat.ChatID, 0, 10)
	if err != nil || len(page) != 1 || page[0].Attachment == nil || *page[0].Attachment != att {
		t.Fatalf("history attachment = %+v err=%v", page, err)
	}
}

func TestPreviewForAttachmentAndText(t *testing.T) {
	cases := []struct {
		body json.RawMessage
		name string
		want string
	}{
		{textBody("hello there"), "report.pdf", "hello there"},
		{nil, "report.pdf", "report.pdf"},
		{textBody("   "), "report.pdf", "report.pdf"},
		{json.RawMessage(`{"type":"blob"}`), "archive.zip", "archive.zip"},
		{nil, "", ""},
	}
	for _, tc := range cases {
		if got := previewFor(tc.body, tc.name); got != tc.want {
			t.Fatalf("previewFor(%s, %q) = %q, want %q", tc.body, tc.name, got, tc.want)
		}
	}
}

func TestListChatFilesProjection(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	chat, _, _, err := s.CreateChat(ctx, "", "panel", "Anna", 100)
	if err != nil {
		t.Fatalf("CreateChat: %v", err)
	}
	var fileSeqs []int64
	for i := range 5 {
		if _, _, _, err := s.SendMessage(ctx, chat.ChatID, mustString(100+i), person(t, s, "Anna"), textBody("t"), "", int64(200+i)); err != nil {
			t.Fatalf("text send %d: %v", i, err)
		}
		att, err := s.CreateUpload(ctx, mustString(i)+".bin", 10, "application/octet-stream", int64(200+i))
		if err != nil {
			t.Fatalf("CreateUpload %d: %v", i, err)
		}
		if err := s.MarkUploaded(ctx, att.FileID); err != nil {
			t.Fatalf("MarkUploaded %d: %v", i, err)
		}
		msg, _, _, err := s.SendMessage(ctx, chat.ChatID, mustString(200+i), person(t, s, "Anna"), nil, att.FileID, int64(200+i))
		if err != nil {
			t.Fatalf("file send %d: %v", i, err)
		}
		fileSeqs = append(fileSeqs, msg.Seq)
	}

	// First page: the 3 newest attachments, ascending, more behind.
	page, hasMore, err := s.ListChatFiles(ctx, chat.ChatID, 0, 3)
	if err != nil || !hasMore || len(page) != 3 {
		t.Fatalf("page = %d rows hasMore=%v err=%v", len(page), hasMore, err)
	}
	if page[0].Seq != fileSeqs[2] || page[2].Seq != fileSeqs[4] {
		t.Fatalf("page seqs = %d..%d, want %d..%d", page[0].Seq, page[2].Seq, fileSeqs[2], fileSeqs[4])
	}
	// Second page from the boundary: the remaining 2.
	rest, hasMore, err := s.ListChatFiles(ctx, chat.ChatID, page[0].Seq, 10)
	if err != nil || hasMore || len(rest) != 2 || rest[0].Seq != fileSeqs[0] || rest[1].Seq != fileSeqs[1] {
		t.Fatalf("rest = %+v hasMore=%v err=%v", rest, hasMore, err)
	}
	// Empty chat.
	other, _, _, err := s.CreateChat(ctx, "", "nofiles", "Anna", 900)
	if err != nil {
		t.Fatalf("CreateChat: %v", err)
	}
	none, hasMore, err := s.ListChatFiles(ctx, other.ChatID, 0, 10)
	if err != nil || hasMore || len(none) != 0 {
		t.Fatalf("empty projection = %+v hasMore=%v err=%v", none, hasMore, err)
	}
}

func TestOrphanSweepQueries(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	chat, _, _, err := s.CreateChat(ctx, "", "sweep", "Anna", 100)
	if err != nil {
		t.Fatalf("CreateChat: %v", err)
	}
	old, err := s.CreateUpload(ctx, "old.bin", 10, "x", 1000)
	if err != nil {
		t.Fatalf("CreateUpload old: %v", err)
	}
	fresh, err := s.CreateUpload(ctx, "fresh.bin", 10, "x", 5000)
	if err != nil {
		t.Fatalf("CreateUpload fresh: %v", err)
	}
	bound, err := s.CreateUpload(ctx, "bound.bin", 10, "x", 1000)
	if err != nil {
		t.Fatalf("CreateUpload bound: %v", err)
	}
	if err := s.MarkUploaded(ctx, bound.FileID); err != nil {
		t.Fatalf("MarkUploaded: %v", err)
	}
	if _, _, _, err := s.SendMessage(ctx, chat.ChatID, "b1", person(t, s, "Anna"), nil, bound.FileID, 1100); err != nil {
		t.Fatalf("bind send: %v", err)
	}

	// Cutoff between old(1000) and fresh(5000): only the unbound old one.
	ids, err := s.OrphanFiles(ctx, 2000)
	if err != nil || len(ids) != 1 || ids[0] != old.FileID {
		t.Fatalf("orphans = %v err=%v, want only the old unbound upload", ids, err)
	}
	if err := s.DeleteFiles(ctx, ids); err != nil {
		t.Fatalf("DeleteFiles: %v", err)
	}
	if _, err := s.FileByID(ctx, old.FileID); !errors.Is(err, ErrFileNotFound) {
		t.Fatalf("old file still present: %v", err)
	}
	if _, err := s.FileByID(ctx, fresh.FileID); err != nil {
		t.Fatalf("fresh file swept: %v", err)
	}
	if _, err := s.FileByID(ctx, bound.FileID); err != nil {
		t.Fatalf("bound file swept: %v", err)
	}
}

// person pairs one device and names it, the way the first device of a fresh
// install does. Messages carry a foreign key to users, so a test that writes a
// message needs its author to exist - and since feature 032 a person can only
// come into being through pairing. Idempotent: the device key finds the row on
// every later call.
func person(t *testing.T, s *Store, name string) Identity {
	t.Helper()
	ctx := context.Background()
	deviceKey := "dev-" + name

	if id, err := s.ResolveIdentity(ctx, deviceKey, name, 1); err == nil {
		return id
	}
	if _, err := s.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	if _, err := pairID(ctx, s, issueLink(t, s, 1), deviceKey, "test", 1); err != nil {
		t.Fatalf("Pair(%s): %v", name, err)
	}
	// State the chosen name the way onboarding does.
	id, err := s.ResolveIdentity(ctx, deviceKey, name, 1)
	if err != nil {
		t.Fatalf("ResolveIdentity(%s): %v", name, err)
	}
	return id
}

// readSource reads a file of this package, for the tests that assert about the
// code itself rather than about its behaviour.
func readSource(t *testing.T, name string) string {
	t.Helper()
	raw, err := os.ReadFile(name)
	if err != nil {
		t.Fatalf("read %s: %v", name, err)
	}
	return string(raw)
}
