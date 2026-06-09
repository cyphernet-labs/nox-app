# NOX — build/secrets wrappers over mise tasks (blueprint 09).
# Dev-helper targets (generate/format/analyze/test) are added in US3 (T052).

.PHONY: build-macos-stage build-macos-prod build-windows-stage build-linux-stage

build-macos-stage:
	mise run build:macos:stage

build-macos-prod:
	mise run build:macos:prod

build-windows-stage:
	mise run build:windows:stage

build-linux-stage:
	mise run build:linux:stage

# --- dev helpers (US3 / blueprint 12) ---
.PHONY: deps generate format analyze test gate

deps:
	fvm flutter pub get

generate:
	fvm dart run build_runner build --delete-conflicting-outputs

format:
	fvm dart format -l 140 lib test

analyze:
	fvm flutter analyze

test:
	fvm flutter test

gate: generate format analyze test
