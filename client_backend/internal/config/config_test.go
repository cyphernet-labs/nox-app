package config

import (
	"io"
	"path/filepath"
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
			// The password that opens the server's data is entered on the page
			// or through it (047): a server with no page could never open.
			name:    "an empty status address is refused",
			args:    []string{"-status-addr", ""},
			getenv:  noEnv,
			wantErr: true,
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
			// stranger pairs a device with their server through the link the
			// page hands out.
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

// The two address parameters come from a flag or the environment, flag first,
// and arrive UNCHECKED: a malformed one must not stop the server (045, FR-003)
// - the server validates it when it applies it and keeps the stored address on
// a refusal.
func TestTheAddressParametersArriveRawFromAFlagOrTheEnvironment(t *testing.T) {
	noEnv := func(string) string { return "" }
	cfg, err := Load(nil, noEnv)
	if err != nil || cfg.PublicAddr != "" || cfg.OnionAddr != "" {
		t.Fatalf("defaults: public=%q onion=%q err=%v, want both empty", cfg.PublicAddr, cfg.OnionAddr, err)
	}

	env := func(k string) string {
		switch k {
		case "NOX_PUBLIC_ADDR":
			return "nox.example.org:8443"
		case "NOX_ONION_ADDR":
			return "env.onion"
		}
		return ""
	}
	cfg, err = Load(nil, env)
	if err != nil || cfg.PublicAddr != "nox.example.org:8443" || cfg.OnionAddr != "env.onion" {
		t.Fatalf("env: public=%q onion=%q err=%v", cfg.PublicAddr, cfg.OnionAddr, err)
	}
	cfg, err = Load([]string{"-public-addr", " 203.0.113.7:8443 ", "-onion-addr", "not an onion address"}, env)
	if err != nil {
		t.Fatalf("a malformed address parameter stopped the configuration: %v", err)
	}
	if cfg.PublicAddr != "203.0.113.7:8443" || cfg.OnionAddr != "not an onion address" {
		t.Fatalf("flags over env: public=%q onion=%q", cfg.PublicAddr, cfg.OnionAddr)
	}
}

// The usage text a mistyped flag brings up goes to stderr - the service's
// journal - and lists every flag's default. The address parameters have none,
// so the onion address the environment holds stays out of it (FR-022); it still
// arrives, and a flag still wins over it, even an empty one.
func TestTheUsageTextNeverCarriesTheAddressesOfTheEnvironment(t *testing.T) {
	const onion = "6bauzvyr6myctqykmykeuo3p3yc3iy7tilx5g3sxxpuifdwab54o56id.onion"
	env := func(k string) string {
		switch k {
		case "NOX_ONION_ADDR":
			return onion
		case "NOX_PUBLIC_ADDR":
			return "nox.example.org:8443"
		}
		return ""
	}
	for _, args := range [][]string{{"-h"}, {"-no-such-flag"}, {"-onion-addr"}} {
		var usage strings.Builder
		if _, err := load(args, env, &usage); err == nil {
			t.Fatalf("load(%q) succeeded", args)
		}
		if !strings.Contains(usage.String(), "-onion-addr") {
			t.Fatalf("load(%q) printed no usage, so this test proves nothing:\n%s", args, usage.String())
		}
		if strings.Contains(usage.String(), onion[:56]) || strings.Contains(usage.String(), "nox.example.org") {
			t.Fatalf("load(%q) printed an address of the environment:\n%s", args, usage.String())
		}
	}

	cfg, err := load(nil, env, io.Discard)
	if err != nil || cfg.OnionAddr != onion || cfg.PublicAddr != "nox.example.org:8443" {
		t.Fatalf("from the environment: onion=%q public=%q err=%v", cfg.OnionAddr, cfg.PublicAddr, err)
	}
	cfg, err = load([]string{"-onion-addr", "", "-public-addr="}, env, io.Discard)
	if err != nil || cfg.OnionAddr != "" || cfg.PublicAddr != "" {
		t.Fatalf("empty flags over the environment: onion=%q public=%q err=%v", cfg.OnionAddr, cfg.PublicAddr, err)
	}
}

// The server's own tor is gone (045). A unit file still carrying one of its
// flags was written by somebody who expects this server to run tor; the start
// fails and says where tor went, whatever spelling the flag was written in.
func TestTheRemovedTorFlagsFailWithAHint(t *testing.T) {
	noEnv := func(string) string { return "" }
	for _, args := range [][]string{
		{"-tor=false"},
		{"-tor", "false", "-addr", "0.0.0.0:8080"},
		{"-tor"},
		{"-db", "/data/nox.db", "-tor=true"},
		{"--tor=false"},
		{"-tor-bin", "/usr/bin/tor"},
		{"-tor-bin=/usr/bin/tor"},
		{"-tor-dir", "/var/lib/nox-tor"},
	} {
		_, err := Load(args, noEnv)
		if err == nil || !strings.Contains(err.Error(), "separate service") || !strings.Contains(err.Error(), "-onion-addr") {
			t.Errorf("Load(%q) = %v, want a refusal that says tor is a separate service now", args, err)
		}
	}
}

// The environment that configured the old tor is simply not read any more: the
// variables carry nothing the server could act on, and the flag above is what
// says so out loud.
func TestTheOldTorEnvironmentIsIgnored(t *testing.T) {
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
	cfg, err := Load(nil, env)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if want := (Config{Addr: "127.0.0.1:8080", DBPath: "nox.db", FilesPath: "nox.db-files", StatusAddr: "127.0.0.1:8081", Limits: DefaultLimits()}); cfg != want {
		t.Fatalf("Load = %+v, want the defaults", cfg)
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

// A stray word stops flag parsing where it stands, dropping every flag after
// it - and a fresh database would open in the working directory. Refused.
func TestAStrayArgumentIsRefusedRatherThanEndingTheFlags(t *testing.T) {
	noEnv := func(string) string { return "" }
	_, err := Load([]string{"-addr", "0.0.0.0:8080", "stray", "-db", "/data/nox.db"}, noEnv)
	if err == nil || !strings.Contains(err.Error(), `"stray"`) {
		t.Fatalf("err = %v, want a refusal that names the stray word", err)
	}
	if _, err := Load([]string{"extra"}, noEnv); err == nil {
		t.Fatal("a positional argument was accepted")
	}
}

// `noxd link` (046) finds the running server the way the server was told where
// to listen - flag, then NOX_STATUS_ADDR, then the default - and is held to
// loopback by the same rule: it asks for a link, and the answer must come from
// this machine.
func TestLoadLink(t *testing.T) {
	noEnv := func(string) string { return "" }
	env := func(k string) string {
		if k == "NOX_STATUS_ADDR" {
			return "127.0.0.1:9100"
		}
		return ""
	}
	for _, tc := range []struct {
		name    string
		args    []string
		getenv  func(string) string
		want    LinkConfig
		wantErr string
	}{
		{name: "the server's default page address", getenv: noEnv, want: LinkConfig{StatusAddr: "127.0.0.1:8081"}},
		{name: "the address the server was started with", getenv: env, want: LinkConfig{StatusAddr: "127.0.0.1:9100"}},
		{name: "the flag wins", args: []string{"-status-addr", "127.0.0.1:9200"}, getenv: env, want: LinkConfig{StatusAddr: "127.0.0.1:9200"}},
		{name: "localhost is loopback", args: []string{"-status-addr", "localhost:8081"}, getenv: noEnv, want: LinkConfig{StatusAddr: "localhost:8081"}},
		{name: "the code as well", args: []string{"-qr"}, getenv: noEnv, want: LinkConfig{StatusAddr: "127.0.0.1:8081", QR: true}},
		{name: "an address on a network", args: []string{"-status-addr", "192.168.1.10:8081"}, getenv: noEnv, wantErr: "loopback"},
		{name: "every interface", args: []string{"-status-addr", "0.0.0.0:8081"}, getenv: noEnv, wantErr: "loopback"},
		{name: "no page at all", args: []string{"-status-addr", ""}, getenv: noEnv, wantErr: "must name"},
		{name: "a stray word", args: []string{"now"}, getenv: noEnv, wantErr: `"now"`},
		{name: "a server flag", args: []string{"-db", "x.db"}, getenv: noEnv, wantErr: "flag provided but not defined"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got, err := LoadLink(tc.args, tc.getenv)
			if tc.wantErr != "" {
				if err == nil || !strings.Contains(err.Error(), tc.wantErr) {
					t.Fatalf("LoadLink = %+v, %v; want an error saying %q", got, err, tc.wantErr)
				}
				return
			}
			if err != nil || got != tc.want {
				t.Fatalf("LoadLink = %+v, %v; want %+v", got, err, tc.want)
			}
		})
	}
}

func TestTheKeyFileLiesBesideTheDatabase(t *testing.T) {
	cfg, err := Load([]string{"-db", "/srv/nox/nox.db"}, func(string) string { return "" })
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if got := cfg.KeyPath(); got != "/srv/nox/nox.db.key" {
		t.Fatalf("KeyPath() = %q, want the database path with .key", got)
	}
}

func TestLoadCommand(t *testing.T) {
	noEnv := func(string) string { return "" }
	env := func(k string) string {
		if k == "NOX_STATUS_ADDR" {
			return "127.0.0.1:9100"
		}
		return ""
	}
	tests := []struct {
		name    string
		args    []string
		getenv  func(string) string
		want    string
		wantErr string
	}{
		{name: "the server's default page address", getenv: noEnv, want: "127.0.0.1:8081"},
		{name: "the address the server was started with", getenv: env, want: "127.0.0.1:9100"},
		{name: "the flag wins", args: []string{"-status-addr", "127.0.0.1:9200"}, getenv: env, want: "127.0.0.1:9200"},
		{name: "an address on a network", args: []string{"-status-addr", "192.168.1.10:8081"}, getenv: noEnv, wantErr: "loopback"},
		{name: "no page at all", args: []string{"-status-addr", ""}, getenv: noEnv, wantErr: "must name"},
		{name: "a password on the command line", args: []string{"correct horse battery"}, getenv: noEnv, wantErr: "never given"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := LoadCommand("unlock", tt.args, tt.getenv)
			if tt.wantErr != "" {
				if err == nil || !strings.Contains(err.Error(), tt.wantErr) {
					t.Fatalf("LoadCommand(%q) = %v, want an error about %q", tt.args, err, tt.wantErr)
				}
				return
			}
			if err != nil || got.StatusAddr != tt.want {
				t.Fatalf("LoadCommand(%q) = %+v, %v; want %s", tt.args, got, err, tt.want)
			}
		})
	}
}

// The file may come before the flag or after it: the flag package stops at
// the first word that is not a flag, and a file named first would otherwise
// leave every flag after it unread - a restore landing in the working
// directory instead of where -db said.
func TestTheBackupFileMayComeBeforeOrAfterTheFlags(t *testing.T) {
	for _, args := range [][]string{
		{"/backups/nox.tar", "-db", "/srv/nox/nox.db"},
		{"-db", "/srv/nox/nox.db", "/backups/nox.tar"},
	} {
		got, err := LoadRestore(args)
		if err != nil {
			t.Fatalf("LoadRestore(%q): %v", args, err)
		}
		want := RestoreConfig{File: "/backups/nox.tar", DBPath: "/srv/nox/nox.db", FilesPath: "/srv/nox/nox.db-files"}
		if got != want {
			t.Fatalf("LoadRestore(%q) = %+v, want %+v", args, got, want)
		}
	}
	got, err := LoadRestore([]string{"b.tar", "-db", "/x/nox.db", "-files", "/data/files"})
	if err != nil || got.FilesPath != "/data/files" {
		t.Fatalf("LoadRestore with -files = %+v, %v", got, err)
	}
	for name, args := range map[string][]string{
		"no -db":       {"b.tar"},
		"no file":      {"-db", "/x/nox.db"},
		"two files":    {"a.tar", "b.tar", "-db", "/x/nox.db"},
		"an odd flag":  {"b.tar", "-db", "/x/nox.db", "-tor"},
		"an empty -db": {"b.tar", "-db", ""},
	} {
		if _, err := LoadRestore(args); err == nil {
			t.Errorf("%s: LoadRestore(%q) succeeded", name, args)
		}
	}
}

func TestLoadBackupMakesTheFileAbsolute(t *testing.T) {
	noEnv := func(string) string { return "" }
	t.Chdir(t.TempDir())
	got, err := LoadBackup([]string{"nox.tar", "-status-addr", "127.0.0.1:9100"}, noEnv)
	if err != nil {
		t.Fatalf("LoadBackup: %v", err)
	}
	if !filepath.IsAbs(got.File) || filepath.Base(got.File) != "nox.tar" {
		t.Fatalf("File = %q, want an absolute path", got.File)
	}
	if got.StatusAddr != "127.0.0.1:9100" {
		t.Fatalf("StatusAddr = %q", got.StatusAddr)
	}
	if _, err := LoadBackup(nil, noEnv); err == nil {
		t.Fatal("a backup with no file was accepted")
	}
}
