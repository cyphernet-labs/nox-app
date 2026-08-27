package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
)

type Note struct {
	ID        int64  `json:"id"`
	Title     string `json:"title"`
	Body      string `json:"body"`
	UpdatedAt int64  `json:"updated_at"`
}

// Event is one row of the transactional outbox. seq is a strictly
// increasing total order over all committed writes (single writer +
// AUTOINCREMENT), which is what makes client replay-by-seq correct.
type Event struct {
	Seq       int64           `json:"seq"`
	Type      string          `json:"type"`
	Entity    string          `json:"entity"`
	EntityID  int64           `json:"entity_id"`
	Payload   json.RawMessage `json:"payload"`
	CreatedAt int64           `json:"created_at"`
}

var ErrNotFound = errors.New("not found")

type Store struct {
	read  *sql.DB // concurrent SELECT pool
	write *sql.DB // single connection, BEGIN IMMEDIATE transactions
	hub   *Hub
}

// ---- reads (concurrent, snapshot-isolated by WAL) ----

func (s *Store) ListNotes(ctx context.Context) ([]Note, error) {
	rows, err := s.read.QueryContext(ctx,
		"SELECT id, title, body, updated_at FROM notes ORDER BY id")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	notes := []Note{}
	for rows.Next() {
		var n Note
		if err := rows.Scan(&n.ID, &n.Title, &n.Body, &n.UpdatedAt); err != nil {
			return nil, err
		}
		notes = append(notes, n)
	}
	return notes, rows.Err()
}

func (s *Store) GetNote(ctx context.Context, id int64) (Note, error) {
	var n Note
	err := s.read.QueryRowContext(ctx,
		"SELECT id, title, body, updated_at FROM notes WHERE id = ?", id).
		Scan(&n.ID, &n.Title, &n.Body, &n.UpdatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return Note{}, ErrNotFound
	}
	return n, err
}

func (s *Store) EventsSince(ctx context.Context, seq int64) ([]Event, error) {
	rows, err := s.read.QueryContext(ctx,
		`SELECT seq, type, entity, entity_id, payload, created_at
		   FROM events WHERE seq > ? ORDER BY seq`, seq)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	evs := []Event{}
	for rows.Next() {
		var e Event
		var payload []byte
		if err := rows.Scan(&e.Seq, &e.Type, &e.Entity, &e.EntityID, &payload, &e.CreatedAt); err != nil {
			return nil, err
		}
		e.Payload = json.RawMessage(payload)
		evs = append(evs, e)
	}
	return evs, rows.Err()
}

// ---- writes (serialized through the single write connection) ----
// Pattern for every mutation:
//   1. one BEGIN IMMEDIATE transaction: mutate the entity AND insert the
//      outbox row (same transaction, so a notification can never exist
//      for uncommitted data);
//   2. after COMMIT returns: hand the event to the hub for fan-out.

func (s *Store) CreateNote(ctx context.Context, title, body string) (Note, error) {
	var n Note
	var ev Event
	err := s.inTx(ctx, func(tx *sql.Tx) error {
		if err := tx.QueryRowContext(ctx,
			`INSERT INTO notes (title, body) VALUES (?, ?)
			 RETURNING id, title, body, updated_at`, title, body).
			Scan(&n.ID, &n.Title, &n.Body, &n.UpdatedAt); err != nil {
			return err
		}
		var err error
		ev, err = insertEvent(ctx, tx, "note.created", n.ID, n)
		return err
	})
	if err != nil {
		return Note{}, err
	}
	s.hub.Broadcast(ev)
	return n, nil
}

func (s *Store) UpdateNote(ctx context.Context, id int64, title, body string) (Note, error) {
	var n Note
	var ev Event
	err := s.inTx(ctx, func(tx *sql.Tx) error {
		err := tx.QueryRowContext(ctx,
			`UPDATE notes SET title = ?, body = ?, updated_at = unixepoch()
			  WHERE id = ?
			 RETURNING id, title, body, updated_at`, title, body, id).
			Scan(&n.ID, &n.Title, &n.Body, &n.UpdatedAt)
		if errors.Is(err, sql.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		ev, err = insertEvent(ctx, tx, "note.updated", n.ID, n)
		return err
	})
	if err != nil {
		return Note{}, err
	}
	s.hub.Broadcast(ev)
	return n, nil
}

func (s *Store) DeleteNote(ctx context.Context, id int64) error {
	var ev Event
	err := s.inTx(ctx, func(tx *sql.Tx) error {
		res, err := tx.ExecContext(ctx, "DELETE FROM notes WHERE id = ?", id)
		if err != nil {
			return err
		}
		affected, err := res.RowsAffected()
		if err != nil {
			return err
		}
		if affected == 0 {
			return ErrNotFound
		}
		ev, err = insertEvent(ctx, tx, "note.deleted", id, map[string]int64{"id": id})
		return err
	})
	if err != nil {
		return err
	}
	s.hub.Broadcast(ev)
	return nil
}

func (s *Store) inTx(ctx context.Context, fn func(tx *sql.Tx) error) error {
	tx, err := s.write.BeginTx(ctx, nil) // _txlock=immediate => BEGIN IMMEDIATE
	if err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		tx.Rollback()
		return err
	}
	return tx.Commit()
}

func insertEvent(ctx context.Context, tx *sql.Tx, typ string, entityID int64, payload any) (Event, error) {
	raw, err := json.Marshal(payload)
	if err != nil {
		return Event{}, fmt.Errorf("marshal event payload: %w", err)
	}
	ev := Event{Type: typ, Entity: "note", EntityID: entityID, Payload: raw}
	err = tx.QueryRowContext(ctx,
		`INSERT INTO events (type, entity, entity_id, payload)
		 VALUES (?, 'note', ?, ?)
		 RETURNING seq, created_at`, typ, entityID, string(raw)).
		Scan(&ev.Seq, &ev.CreatedAt)
	return ev, err
}
