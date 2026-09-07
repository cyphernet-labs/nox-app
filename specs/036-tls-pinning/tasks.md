# Tasks: TLS с пиннингом по ключу сервера

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md)

**⚠️ Не начинать до живого прогона 034/035.** Причина — в [plan.md](./plan.md) §«Когда это делается».

## Phase 1: Контракт

- [ ] T001 Record in `docs/client-backend/protocol/contract-draft.md` §1 that the address is `wss` and that trust comes from the key in the pairing link rather than from a certificate authority — commands, events and codes are untouched
- [ ] T002 Record that the service page (035) stays plain HTTP on loopback: it has no network traffic, so TLS there is complexity with no purpose

## Phase 2: Сервер

- [ ] T003 Build a self-signed certificate from the machine's OWN Ed25519 identity key in `client_backend/internal/server/tls.go` — the key already in `server_identity`, never a new one: a new key would cut off every paired device, and a second key beside the first would be a second identity for one machine
- [ ] T004 Rebuild the certificate at every start and keep it in memory only in `client_backend/internal/server/tls.go` — storing it would be a second record of one fact, with an expiry to renew
- [ ] T005 Serve the main listener over TLS in `client_backend/internal/server/server.go`, and refuse a plain connection
- [ ] T006 Leave the status listener as plain HTTP on loopback in `client_backend/internal/server/server.go`
- [ ] T007 [P] Server test in `client_backend/internal/server/tls_test.go`: the certificate's public key equals the one the pairing link carries
- [ ] T008 [P] Server test: a restart produces a different certificate with the SAME key, and a client pinned to that key accepts it

## Phase 3: Клиент

- [ ] T009 Replace chain validation with a key comparison in `lib/data/remote/socket/server_key_check.dart` — the certificate's public key against the one stored at pairing
- [ ] T010 Wire the check into `lib/data/remote/socket/socket_channel_factory.dart` through an `HttpClient` whose bad-certificate callback answers only that question
- [ ] T011 Ignore the certificate's name, expiry and issuer in `lib/data/remote/socket/server_key_check.dart` — a server that sits in a flat changes address, and each of those three is a refusal nobody can repair
- [ ] T012 Build `wss` addresses in `lib/data/sync/live_session_starter.dart`, with no fallback to a clear channel
- [ ] T013 Tell a failed pin apart from a missing network in `lib/data/remote/socket/nox_socket_client.dart` and on the screen that shows it
- [ ] T014 [P] Client test: a certificate on another key is refused; the same key with a new certificate is accepted
- [ ] T015 [P] Client test: a session stored before this phase connects using the key it already holds

## Phase 4: Платформа

- [ ] T016 Remove `usesCleartextTraffic` from `android/app/src/debug/AndroidManifest.xml` — together with the reason it was added
- [ ] T017 Check the four other platforms open a pinned connection: macOS, Windows, Linux, iOS

## Phase 5: Polish

- [ ] T018 [P] Record the phase's invariants in `client_backend/CLAUDE.md`: one key for identity and for the channel, the certificate rebuilt every start, no fallback
- [ ] T019 [P] Mark 036 ☑ in `docs/client-backend/roadmap-stage2.md` and note that Q14 (ATS, App Review) stays open
- [ ] T020 Run `gofmt -l .`, `go vet ./...`, `go test -race ./...`, `make gate`, `make golden-verify`
- [ ] T021 Live: two devices and a real `noxd`, with a packet capture showing no message text, no name and no identifier
