// Package db owns the SQLite access discipline: two pools over one file
// (a read pool and a single-connection writer) with fixed pragmas, plus the
// user_version migration runner. No other package opens the database.
//
// The file is encrypted page by page (047): SQLite runs as WebAssembly inside
// the process (github.com/ncruces/go-sqlite3, no CGO) over the "adiantum" VFS,
// which encrypts every page of the database and of its WAL with the data key
// before it reaches the disk. A database opened with another key reads as no
// database at all.
package db

import (
	"context"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"net/url"
	"path/filepath"
	"strings"

	"github.com/ncruces/go-sqlite3"
	"github.com/ncruces/go-sqlite3/driver"
	// Registers the "adiantum" VFS the URIs below name.
	_ "github.com/ncruces/go-sqlite3/vfs/adiantum"
)

// KeySize is the data key's length: Adiantum takes 32 bytes.
const KeySize = 32

// ErrWrongKey is a database file the data key does not open - a key file and
// a database that do not belong together.
var ErrWrongKey = errors.New("the data key does not open this database")

// pragmas are fixed for every connection (CLAUDE.md invariant 13). They run
// AFTER the key and in this order, as the driver documents: busy_timeout,
// then WAL, NORMAL sync, enforced foreign keys - and temporary tables in
// memory, because a temporary file would be encrypted with a throwaway key at
// best and is one more file on the disk at worst.
var pragmas = []string{
	"PRAGMA busy_timeout=5000",
	"PRAGMA journal_mode=WAL",
	"PRAGMA synchronous=NORMAL",
	"PRAGMA foreign_keys=1",
	"PRAGMA temp_store=memory",
}

// DB holds the two pools. All mutations go through Write (single connection,
// immediate transactions); reads go through Read.
type DB struct {
	Read  *sql.DB
	Write *sql.DB
}

// Open opens both pools over the database file at path, encrypted with key.
// A file that is not there yet is created empty; a file the key does not open
// is ErrWrongKey.
func Open(path string, key []byte) (*DB, error) {
	if len(key) != KeySize {
		return nil, fmt.Errorf("open database: the data key is %d bytes, want %d", len(key), KeySize)
	}
	readURI, err := fileURI(path, url.Values{"vfs": {"adiantum"}})
	if err != nil {
		return nil, err
	}
	writeURI, err := fileURI(path, url.Values{"vfs": {"adiantum"}, "_txlock": {"immediate"}})
	if err != nil {
		return nil, err
	}

	read, err := driver.Open(readURI, connect(key))
	if err != nil {
		return nil, fmt.Errorf("open read pool: %w", err)
	}
	read.SetMaxOpenConns(4)

	write, err := driver.Open(writeURI, connect(key))
	if err != nil {
		_ = read.Close()
		return nil, fmt.Errorf("open write pool: %w", err)
	}
	write.SetMaxOpenConns(1)

	if err := write.Ping(); err != nil {
		_ = read.Close()
		_ = write.Close()
		return nil, fmt.Errorf("open database %q: %w", path, err)
	}
	return &DB{Read: read, Write: write}, nil
}

// connect runs on every new connection, before anything else touches it.
//
// The key goes in as a PRAGMA rather than in the URI. A URI is a string that
// travels - into the connector, into the VFS's view of the file name, into
// whatever error quotes it - while the pragma is spent on the connection the
// moment it runs. Until it has run the file reads as empty, so it is first.
func connect(key []byte) func(*sqlite3.Conn) error {
	hexKey := hex.EncodeToString(key)
	return func(c *sqlite3.Conn) error {
		if err := c.Exec("PRAGMA hexkey='" + hexKey + "'"); err != nil {
			return fmt.Errorf("set the data key: %s", redact(err, hexKey))
		}
		for _, p := range pragmas {
			if err := c.Exec(p); err != nil {
				// The WAL pragma is the first to read the file's header, and a
				// header the key does not decrypt is "not a database".
				if errors.Is(err, sqlite3.NOTADB) {
					return ErrWrongKey
				}
				return fmt.Errorf("%s: %w", p, err)
			}
		}
		return nil
	}
}

// Snapshot writes a consistent copy of the database into a new file at path,
// encrypted with the same key: VACUUM INTO reads the whole database in one
// read transaction while writers go on, and writes it compacted. The file at
// path must not exist yet.
//
// The target's key has to travel in its URI - VACUUM INTO opens the file
// itself, and no pragma can reach it first - so the URI is bound as a
// parameter, never spliced into the statement, and SQLite's own message,
// which quotes the file it could not open, leaves here with the key cut out.
func Snapshot(ctx context.Context, conn *sql.DB, path string, key []byte) error {
	if len(key) != KeySize {
		return fmt.Errorf("snapshot: the data key is %d bytes, want %d", len(key), KeySize)
	}
	hexKey := hex.EncodeToString(key)
	uri, err := fileURI(path, url.Values{"vfs": {"adiantum"}, "hexkey": {hexKey}})
	if err != nil {
		return err
	}
	if _, err := conn.ExecContext(ctx, "VACUUM INTO ?", uri); err != nil {
		return fmt.Errorf("write the snapshot: %s", redact(err, hexKey))
	}
	return nil
}

// QuickCheck runs SQLite's structural check over the whole file: a database
// that fails it is not one to start a server on.
func QuickCheck(ctx context.Context, conn *sql.DB) error {
	rows, err := conn.QueryContext(ctx, "PRAGMA quick_check")
	if err != nil {
		return fmt.Errorf("check the database: %w", err)
	}
	defer func() { _ = rows.Close() }()
	var problems []string
	for rows.Next() {
		var line string
		if err := rows.Scan(&line); err != nil {
			return fmt.Errorf("check the database: %w", err)
		}
		if line != "ok" {
			problems = append(problems, line)
		}
	}
	if err := rows.Err(); err != nil {
		return fmt.Errorf("check the database: %w", err)
	}
	if len(problems) > 0 {
		return fmt.Errorf("the database fails its check: %s", strings.Join(problems, "; "))
	}
	return nil
}

// fileURI is the SQLite URI for the file at path. Absolute and escaped: a
// path with a space, a percent sign or a question mark in it is a file name,
// not the start of a query, and a relative one would read as a host.
func fileURI(path string, query url.Values) (string, error) {
	abs, err := filepath.Abs(path)
	if err != nil {
		return "", fmt.Errorf("resolve %q: %w", path, err)
	}
	p := filepath.ToSlash(abs)
	if !strings.HasPrefix(p, "/") {
		// A Windows path, C:/... - the URI form is file:///C:/...
		p = "/" + p
	}
	return (&url.URL{Scheme: "file", Path: p, RawQuery: query.Encode()}).String(), nil
}

// redact is err's message with secret taken out of it.
func redact(err error, secret string) string {
	return strings.ReplaceAll(err.Error(), secret, "[data key]")
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
