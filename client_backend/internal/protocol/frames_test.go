package protocol

import (
	"encoding/json"
	"testing"
)

func TestReplyShapes(t *testing.T) {
	tests := []struct {
		name  string
		reply Reply
		want  string
	}{
		{
			name:  "ok reply carries data and no error",
			reply: OKReply(7, map[string]bool{"available": true}),
			want:  `{"id":7,"ok":true,"data":{"available":true}}`,
		},
		{
			name:  "error reply carries code and no data",
			reply: ErrReply(7, ErrNameTaken, "Chat name already exists"),
			want:  `{"id":7,"ok":false,"error":{"code":"name_taken","message":"Chat name already exists"}}`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			raw, err := MarshalFrame(tt.reply)
			if err != nil {
				t.Fatalf("MarshalFrame: %v", err)
			}
			if string(raw) != tt.want {
				t.Fatalf("frame = %s, want %s", raw, tt.want)
			}
		})
	}
}

func TestParseCommand(t *testing.T) {
	t.Run("unknown sibling fields are ignored", func(t *testing.T) {
		cmd, err := ParseCommand([]byte(`{"id":3,"cmd":"chat.create","data":{"name":"x"},"future_field":42}`))
		if err != nil {
			t.Fatalf("ParseCommand: %v", err)
		}
		if cmd.ID != 3 || cmd.Cmd != CmdChatCreate {
			t.Fatalf("parsed = %+v", cmd)
		}
	})

	t.Run("missing cmd fails", func(t *testing.T) {
		if _, err := ParseCommand([]byte(`{"id":3,"data":{}}`)); err == nil {
			t.Fatal("want error for missing cmd")
		}
	})

	t.Run("non-object frame fails", func(t *testing.T) {
		if _, err := ParseCommand([]byte(`[1,2,3]`)); err == nil {
			t.Fatal("want error for non-object frame")
		}
	})
}

func TestEventFrameShape(t *testing.T) {
	ev := Event{Seq: 1042, Event: EventMessageNew, Data: json.RawMessage(`{"message_id":"m_1"}`)}
	raw, err := MarshalFrame(ev)
	if err != nil {
		t.Fatalf("MarshalFrame: %v", err)
	}
	want := `{"seq":1042,"event":"message.new","data":{"message_id":"m_1"}}`
	if string(raw) != want {
		t.Fatalf("frame = %s, want %s", raw, want)
	}
}

func TestMessageOmitsEmptyClientMessageID(t *testing.T) {
	raw, err := json.Marshal(Message{MessageID: "m_1", Seq: 1, ChatID: "c_1", AuthorID: "a", AuthorLabel: "a", SentAt: 1, Body: json.RawMessage(`{}`)})
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if string(raw) == "" || jsonHas(t, raw, "client_message_id") {
		t.Fatalf("client_message_id must be omitted when empty: %s", raw)
	}
}

func jsonHas(t *testing.T, raw []byte, key string) bool {
	t.Helper()
	var m map[string]any
	if err := json.Unmarshal(raw, &m); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	_, ok := m[key]
	return ok
}
