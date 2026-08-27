// Package db owns the SQLite access discipline: two pools over one file
// (a read pool and a single-connection writer) with fixed pragmas, plus the
// user_version migration runner. No other package opens the database.
package db

import (
	"database/sql"
	"fmt"

	_ "modernc.org/sqlite"
)

// Pragmas are fixed for every connection (CLAUDE.md invariant 13):
// busy_timeout first, then WAL, NORMAL sync and enforced foreign keys.
const pragmas = "?_pragma=busy_timeout(5000)" +
	"&_pragma=journal_mode(WAL)" +
	"&_pragma=synchronous(NORMAL)" +
	"&_pragma=foreign_keys(1)"

// DB holds the two pools. All mutations go through Write (single connection,
// immediate transactions); reads go through Read.
type DB struct {
	Read  *sql.DB
	Write *sql.DB
}

// Open opens both pools over the same database file.
func Open(path string) (*DB, error) {
	read, err := sql.Open("sqlite", "file:"+path+pragmas)
	if err != nil {
		return nil, fmt.Errorf("open read pool: %w", err)
	}
	read.SetMaxOpenConns(4)

	write, err := sql.Open("sqlite", "file:"+path+pragmas+"&_txlock=immediate")
	if err != nil {
		_ = read.Close()
		return nil, fmt.Errorf("open write pool: %w", err)
	}
	write.SetMaxOpenConns(1)

	if err := write.Ping(); err != nil {
		_ = read.Close()
		_ = write.Close()
		return nil, fmt.Errorf("ping database %q: %w", path, err)
	}
	return &DB{Read: read, Write: write}, nil
}

// Close closes both pools, returning the first error encountered.
func (d *DB) Close() error {
	errW := d.Write.Close()
	errR := d.Read.Close()
	if errW != nil {
		return fmt.Errorf("close write pool: %w", errW)
	}
	if errR != nil {
		return fmt.Errorf("close read pool: %w", errR)
	}
	return nil
}
