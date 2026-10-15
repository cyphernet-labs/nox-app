#!/usr/bin/env bash
# Builds RustSecureBox as WebAssembly and translates it into Go source for the
# server (specs/050-rust-secure-box, research R1): the server runs the very
# code the app runs, with no cgo and no Rust on the machine that builds it.
#
#   build-wasm.sh [absolute output directory]
#
# The default output is client_backend/internal/securebox/boxwasm, which is
# committed; `make box-verify` builds into a temporary directory and compares.
# Needs the toolchain of rust-toolchain.toml (with wasm32-unknown-unknown) and
# Go; wasm2go is fetched by `go run` at the pinned version and never enters the
# server's go.mod.
set -euo pipefail

cd -P -- "$(dirname -- "$0")"

OUT="${1:-$PWD/../../client_backend/internal/securebox/boxwasm}"
WASM2GO=github.com/ncruces/wasm2go@v0.4.15
WASM=target/wasm32-unknown-unknown/release/rust_secure_box.wasm

cargo rustc --locked --release --target wasm32-unknown-unknown --crate-type cdylib
mkdir -p "$OUT"
go run "$WASM2GO" -embed -pkg boxwasm -o "$OUT/box.go" "$WASM"
# wasm2go leaves one blank line out; the server's gate wants gofmt's layout.
gofmt -w "$OUT/box.go"
