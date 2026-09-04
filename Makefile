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
.PHONY: deps generate format analyze test golden-update golden-verify gate

deps:
	fvm flutter pub get

generate:
	fvm dart run build_runner build --delete-conflicting-outputs
	fvm flutter gen-l10n

format:
	fvm dart format -l 140 lib test

analyze:
	fvm flutter analyze

test:
	fvm flutter test --exclude-tags "golden || live" $(FILE)

# Golden (snapshot) tests — LOCAL ONLY (Apple Silicon / macOS), excluded from CI via the `golden` tag.
# See .claude/commands/golden-test.md. Narrow with FILE=test/presentation/pages/<page>/<x>_golden_test.dart.
golden-update:
	fvm flutter test --tags golden --update-goldens $(FILE)

golden-verify:
	fvm flutter test --tags golden $(FILE)

gate: generate format analyze test
