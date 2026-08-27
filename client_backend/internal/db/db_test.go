package db

import (
	"context"
	"os"
	"path/filepath"
	"testing"
)

func openMigrated(t *testing.T) *DB {
	t.Helper()
	path := filepath.Join(t.TempDir(), "test.db")
	d, err := Open(path)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	t.Cleanup(func() { _ = d.Close() })
	if _, err := Migrate(context.Background(), d.Write, os.DirFS("../../migrations")); err != nil {
		t.Fatalf("Migrate: %v", err)
	}
	return d
}

func TestMigrateFromZeroSetsVersionAndSchema(t *testing.T) {
	d := openMigrated(t)

	var version int
	if err := d.Read.QueryRow("PRAGMA user_version").Scan(&version); err != nil {
		t.Fatalf("user_version: %v", err)
	}
	if version != 1 {
		t.Fatalf("user_version = %d, want 1", version)
	}

	for _, table := range []string{"chats", "messages", "events"} {
		var name string
		err := d.Read.QueryRow(
			"SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?", table,
		).Scan(&name)
		if err != nil {
			t.Fatalf("table %s missing: %v", table, err)
		}
	}
}

func TestMigrateIsIdempotent(t *testing.T) {
	d := openMigrated(t)

	version, err := Migrate(context.Background(), d.Write, os.DirFS("../../migrations"))
	if err != nil {
		t.Fatalf("second Migrate: %v", err)
	}
	if version != 1 {
		t.Fatalf("version after re-run = %d, want 1", version)
	}
}

func TestPragmasApplied(t *testing.T) {
	d := openMigrated(t)

	var journal string
	if err := d.Write.QueryRow("PRAGMA journal_mode").Scan(&journal); err != nil {
		t.Fatalf("journal_mode: %v", err)
	}
	if journal != "wal" {
		t.Fatalf("journal_mode = %q, want wal", journal)
	}

	var fk int
	if err := d.Write.QueryRow("PRAGMA foreign_keys").Scan(&fk); err != nil {
		t.Fatalf("foreign_keys: %v", err)
	}
	if fk != 1 {
		t.Fatalf("foreign_keys = %d, want 1", fk)
	}
}

func TestSplitStatements(t *testing.T) {
	script := "CREATE TABLE a (x INT);\n\nCREATE INDEX i ON a (x);\n"
	got := splitStatements(script)
	if len(got) != 2 {
		t.Fatalf("statements = %d, want 2: %q", len(got), got)
	}
}
