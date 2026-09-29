package config

import (
	"strings"
	"testing"
)

func TestLoad(t *testing.T) {
	noEnv := func(string) string { return "" }

	tests := []struct {
		name    string
		args    []string
		getenv  func(string) string
		wantErr bool
		want    Config
	}{
		{
			// Empty is not "unset": it removes the page and its listener with
			// it, so nothing holds the port and nothing answers on it.
			name:   "an empty status address disables the service page",
			args:   []string{"-status-addr", ""},
			getenv: noEnv,
			want:   Config{Addr: "127.0.0.1:8080", DBPath: "nox.db", FilesPath: "nox.db-files", StatusAddr: "", Limits: DefaultLimits(), Tor: true, TorDir: "nox.db-tor"},
		},
		{
			name:   "the service page port can be moved",
			args:   []string{"-status-addr", "127.0.0.1:9100"},
			getenv: noEnv,
			want:   Config{Addr: "127.0.0.1:8080", DBPath: "nox.db", FilesPath: "nox.db-files", StatusAddr: "127.0.0.1:9100", Limits: DefaultLimits(), Tor: true, TorDir: "nox.db-tor"},
		},
		{
			// The flag moves the port; it does not put the page on a network.
			// Somebody who tries has to learn it now rather than when a
			// stranger claims their server.
			name:    "a service page bound off loopback is refused",
			args:    []string{"-status-addr", "0.0.0.0:8081"},
			getenv:  noEnv,
			wantErr: true,
		},
		{
			name:    "a service page bound to a routable address is refused",
			args:    []string{"-status-addr", "192.168.1.10:8081"},
			getenv:  noEnv,
			wantErr: true,
		},
		{
			name:   "defaults apply when nothing is provided",
			args:   nil,
			getenv: noEnv,
			want:   Config{Addr: "127.0.0.1:8080", DBPath: "nox.db", FilesPath: "nox.db-files", StatusAddr: "127.0.0.1:8081", Limits: DefaultLimits(), Tor: true, TorDir: "nox.db-tor"},
		},
		{
			name: "environment overrides defaults",
			args: nil,
			getenv: func(k string) string {
				switch k {
				case "NOX_ADDR":
					return "127.0.0.1:9999"
				case "NOX_DB":
					return "/tmp/env.db"
				}
				return ""
			},
			want: Config{Addr: "127.0.0.1:9999", DBPath: "/tmp/env.db", FilesPath: "/tmp/env.db-files", StatusAddr: "127.0.0.1:8081", Limits: DefaultLimits(), Tor: true, TorDir: "/tmp/env.db-tor"},
		},
		{
			name: "flags win over environment",
			args: []string{"-addr", "127.0.0.1:7777", "-db", "flag.db"},
			getenv: func(k string) string {
				if k == "NOX_ADDR" {
					return "127.0.0.1:9999"
				}
				return ""
			},
			want: Config{Addr: "127.0.0.1:7777", DBPath: "flag.db", FilesPath: "flag.db-files", StatusAddr: "127.0.0.1:8081", Limits: DefaultLimits(), Tor: true, TorDir: "flag.db-tor"},
		},
		{
			name:    "address without port is rejected",
			args:    []string{"-addr", "localhost"},
			getenv:  noEnv,
			wantErr: true,
		},
		{
			name:    "empty db path is rejected",
			args:    []string{"-db", ""},
			getenv:  noEnv,
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := Load(tt.args, tt.getenv)
			if tt.wantErr {
				if err == nil {
					t.Fatalf("Load() = %+v, want error", got)
				}
				return
			}
			if err != nil {
				t.Fatalf("Load() error: %v", err)
			}
			if got != tt.want {
				t.Fatalf("Load() = %+v, want %+v", got, tt.want)
			}
		})
	}
}

func TestTorIsOnByDefaultAndCanBeTurnedOff(t *testing.T) {
	noEnv := func(string) string { return "" }

	cfg, err := Load(nil, noEnv)
	if err != nil || !cfg.Tor || cfg.TorBin != "" || cfg.TorDir != "nox.db-tor" {
		t.Fatalf("defaults: tor=%v bin=%q dir=%q err=%v, want on, no explicit binary, <db>-tor", cfg.Tor, cfg.TorBin, cfg.TorDir, err)
	}

	cfg, err = Load([]string{"-tor=false"}, noEnv)
	if err != nil || cfg.Tor {
		t.Fatalf("-tor=false: tor=%v err=%v, want off", cfg.Tor, err)
	}

	env := func(k string) string {
		switch k {
		case "NOX_TOR":
			return "false"
		case "NOX_TOR_BIN":
			return "/opt/tor/bin/tor"
		case "NOX_TOR_DIR":
			return "/var/lib/nox-tor"
		}
		return ""
	}
	cfg, err = Load(nil, env)
	if err != nil || cfg.Tor || cfg.TorBin != "/opt/tor/bin/tor" || cfg.TorDir != "/var/lib/nox-tor" {
		t.Fatalf("env: tor=%v bin=%q dir=%q err=%v", cfg.Tor, cfg.TorBin, cfg.TorDir, err)
	}
	cfg, err = Load([]string{"-tor=true", "-tor-bin", "/flag/tor", "-tor-dir", "/flag/dir"}, env)
	if err != nil || !cfg.Tor || cfg.TorBin != "/flag/tor" || cfg.TorDir != "/flag/dir" {
		t.Fatalf("flags over env: tor=%v bin=%q dir=%q err=%v", cfg.Tor, cfg.TorBin, cfg.TorDir, err)
	}

	// A typo must not quietly decide either way.
	if _, err := Load(nil, func(k string) string {
		if k == "NOX_TOR" {
			return "nope"
		}
		return ""
	}); err == nil {
		t.Fatal("NOX_TOR=nope was accepted")
	}
}

func TestFilesPathDefaultsAndOverrides(t *testing.T) {
	noEnv := func(string) string { return "" }

	cfg, err := Load([]string{"-db", "/data/nox.db"}, noEnv)
	if err != nil || cfg.FilesPath != "/data/nox.db-files" {
		t.Fatalf("default files path = %q err=%v, want <db>-files", cfg.FilesPath, err)
	}

	cfg, err = Load([]string{"-files", "/mnt/blob"}, noEnv)
	if err != nil || cfg.FilesPath != "/mnt/blob" {
		t.Fatalf("flag files path = %q err=%v", cfg.FilesPath, err)
	}

	env := func(k string) string {
		if k == "NOX_FILES" {
			return "/env/blob"
		}
		return ""
	}
	cfg, err = Load(nil, env)
	if err != nil || cfg.FilesPath != "/env/blob" {
		t.Fatalf("env files path = %q err=%v", cfg.FilesPath, err)
	}
	cfg, err = Load([]string{"-files", "/flag/blob"}, env)
	if err != nil || cfg.FilesPath != "/flag/blob" {
		t.Fatalf("flag-over-env files path = %q err=%v", cfg.FilesPath, err)
	}
}

// "-tor false" is the spelling the usage text invites, and a boolean flag does
// not consume the next word: tor would stay on and parsing would stop there,
// dropping every flag after it. A stray argument is refused instead.
func TestAStrayArgumentIsRefusedRatherThanEndingTheFlags(t *testing.T) {
	noEnv := func(string) string { return "" }
	_, err := Load([]string{"-tor", "false", "-addr", "0.0.0.0:8080", "-db", "/data/nox.db"}, noEnv)
	if err == nil || !strings.Contains(err.Error(), "-tor=false") {
		t.Fatalf("err = %v, want a refusal that shows the right spelling", err)
	}
	if _, err := Load([]string{"extra"}, noEnv); err == nil {
		t.Fatal("a positional argument was accepted")
	}
}
