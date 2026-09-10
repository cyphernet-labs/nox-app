package store

import (
	"context"
	"fmt"
)

// Counts is how much of each thing this server holds.
//
// Numbers only, and deliberately so: the service page shows them on a screen
// people glance at over each other's shoulders, so nothing here may carry a
// name, a title, a message body or a key. The queries below touch no such
// column - that is stronger than a page that merely declines to print them.
type Counts struct {
	Devices  int64
	Chats    int64
	Messages int64
}

// CountEverything reads all three in one go.
//
// One statement rather than three calls, because they are shown together:
// separate reads could be interleaved with a write and produce a picture that
// never existed - a message in a chat that is not counted yet.
func (s *Store) CountEverything(ctx context.Context) (Counts, error) {
	var c Counts
	err := s.read.QueryRowContext(ctx, `
		SELECT (SELECT COUNT(1) FROM devices),
		       (SELECT COUNT(1) FROM chats),
		       (SELECT COUNT(1) FROM messages)`).
		Scan(&c.Devices, &c.Chats, &c.Messages)
	if err != nil {
		return Counts{}, fmt.Errorf("count store contents: %w", err)
	}
	return c, nil
}
