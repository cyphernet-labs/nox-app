package config

import "testing"

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
			want:   Config{Addr: "127.0.0.1:8080", DBPath: "nox.db", FilesPath: "nox.db-files", StatusAddr: "", Limits: DefaultLimits()},
		},
		{
			name:   "the service page port can be moved",
			args:   []string{"-status-addr", "127.0.0.1:9100"},
			getenv: noEnv,
			want:   Config{Addr: "127.0.0.1:8080", DBPath: "nox.db", FilesPath: "nox.db-files", StatusAddr: "127.0.0.1:9100", Limits: DefaultLimits()},
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
			want:   Config{Addr: "127.0.0.1:8080", DBPath: "nox.db", FilesPath: "nox.db-files", StatusAddr: "127.0.0.1:8081", Limits: DefaultLimits()},
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
			want: Config{Addr: "127.0.0.1:9999", DBPath: "/tmp/env.db", FilesPath: "/tmp/env.db-files", StatusAddr: "127.0.0.1:8081", Limits: DefaultLimits()},
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
			want: Config{Addr: "127.0.0.1:7777", DBPath: "flag.db", FilesPath: "flag.db-files", StatusAddr: "127.0.0.1:8081", Limits: DefaultLimits()},
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
