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
			name:   "defaults apply when nothing is provided",
			args:   nil,
			getenv: noEnv,
			want:   Config{Addr: "127.0.0.1:8080", DBPath: "nox.db", Limits: DefaultLimits()},
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
			want: Config{Addr: "127.0.0.1:9999", DBPath: "/tmp/env.db", Limits: DefaultLimits()},
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
			want: Config{Addr: "127.0.0.1:7777", DBPath: "flag.db", Limits: DefaultLimits()},
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
