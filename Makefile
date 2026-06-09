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
