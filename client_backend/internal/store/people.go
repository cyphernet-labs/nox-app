package store

import (
	"context"
	"fmt"
)

// Person is one member of the circle: a name and whether they own the machine.
//
// No devices, no device count, no public keys, no last-seen time. "Who lives
// here" is not "who owns how much hardware", and a device count on its own says
// more about a person than a list of names has any business saying.
type Person struct {
	UserID string `json:"id"`
	Label  string `json:"label"`
	Owner  bool   `json:"owner"`
}

// ListPeople returns everyone on this server.
//
// This is where the ownership flag deferred out of phase 033 finally lands.
// device.list could not carry it: that command returns ONE person's devices, so
// the flag would read the same in every row and be a second copy of what the
// greeting already says. Here the rows are different people, and it
// distinguishes.
//
// Ownership is read from the machine's own row in the same statement, so the
// answer cannot drift from the one a greeting gives.
func (s *Store) ListPeople(ctx context.Context) ([]Person, error) {
	rows, err := s.read.QueryContext(ctx, `
		SELECT u.user_id, u.label,
		       CASE WHEN u.user_id = (SELECT owner_user_id FROM server_identity WHERE id = 1)
		            THEN 1 ELSE 0 END
		FROM users u
		ORDER BY u.created_at, u.user_id`)
	if err != nil {
		return nil, fmt.Errorf("list people: %w", err)
	}
	defer func() { _ = rows.Close() }()

	people := make([]Person, 0, 4)
	for rows.Next() {
		var p Person
		var owner int
		if err := rows.Scan(&p.UserID, &p.Label, &owner); err != nil {
			return nil, fmt.Errorf("scan person: %w", err)
		}
		p.Owner = owner != 0
		people = append(people, p)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate people: %w", err)
	}
	return people, nil
}
