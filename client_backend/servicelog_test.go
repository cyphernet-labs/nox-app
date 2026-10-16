package main

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestTheServiceLogIsAppendedToAcrossStarts(t *testing.T) {
	dir := t.TempDir()
	for _, line := range []string{"first start\n", "second start\n"} {
		f, _, err := openServiceLog(dir, 1<<20)
		if err != nil {
			t.Fatalf("openServiceLog: %v", err)
		}
		if _, err := f.WriteString(line); err != nil {
			t.Fatalf("write: %v", err)
		}
		if err := f.Close(); err != nil {
			t.Fatalf("close: %v", err)
		}
	}
	got, err := os.ReadFile(filepath.Join(dir, serviceLogName))
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if string(got) != "first start\nsecond start\n" {
		t.Fatalf("log = %q, want both starts in order", got)
	}
	if _, err := os.Stat(filepath.Join(dir, serviceLogName+".1")); !os.IsNotExist(err) {
		t.Fatalf("a log under the limit was set aside: %v", err)
	}
}

func TestAFullServiceLogIsSetAsideAtAStartAndReplacesTheOldOne(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, serviceLogName)
	if err := os.WriteFile(path+".1", []byte("the oldest\n"), 0o600); err != nil {
		t.Fatalf("seed: %v", err)
	}
	full := strings.Repeat("x", 64) + "\n"
	if err := os.WriteFile(path, []byte(full), 0o600); err != nil {
		t.Fatalf("seed: %v", err)
	}

	f, _, err := openServiceLog(dir, 64)
	if err != nil {
		t.Fatalf("openServiceLog: %v", err)
	}
	if _, err := f.WriteString("fresh\n"); err != nil {
		t.Fatalf("write: %v", err)
	}
	if err := f.Close(); err != nil {
		t.Fatalf("close: %v", err)
	}

	if got, _ := os.ReadFile(path); string(got) != "fresh\n" {
		t.Fatalf("the new log = %q, want only what this start wrote", got)
	}
	if got, _ := os.ReadFile(path + ".1"); string(got) != full {
		t.Fatalf("the set-aside log = %q, want the full one it replaced", got)
	}
}

func TestTheServiceLogIsReadableByItsOwnerOnly(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Windows keeps who may read a file in its ACL, which the folder's gives it, not in mode bits")
	}
	dir := t.TempDir()
	f, _, err := openServiceLog(dir, 1<<20)
	if err != nil {
		t.Fatalf("openServiceLog: %v", err)
	}
	_ = f.Close()
	info, err := os.Stat(filepath.Join(dir, serviceLogName))
	if err != nil {
		t.Fatalf("stat: %v", err)
	}
	if mode := info.Mode().Perm(); mode&0o077 != 0 {
		t.Fatalf("log mode = %v, want no access for others", mode)
	}
}

// A log that cannot be set aside - another program holds it on Windows - is
// no reason not to start: the server logs on into it and says why.
func TestALogThatCannotBeSetAsideStillOpens(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, serviceLogName)
	if err := os.WriteFile(path, []byte(strings.Repeat("x", 64)+"\n"), 0o600); err != nil {
		t.Fatalf("seed: %v", err)
	}
	// A folder where the set-aside copy goes: no rename lands on it.
	if err := os.MkdirAll(filepath.Join(path+".1", "held"), 0o700); err != nil {
		t.Fatalf("seed: %v", err)
	}
	f, aside, err := openServiceLog(dir, 64)
	if err != nil {
		t.Fatalf("openServiceLog: %v", err)
	}
	if aside == nil {
		t.Fatal("a log that was not set aside was not reported")
	}
	if _, err := f.WriteString("on\n"); err != nil {
		t.Fatalf("write: %v", err)
	}
	_ = f.Close()
	if got, _ := os.ReadFile(path); !strings.HasSuffix(string(got), "\non\n") {
		t.Fatalf("the log = %q, want this start's line after the old ones", got)
	}
}
