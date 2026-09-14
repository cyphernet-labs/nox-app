# Tasks: TLS с пиннингом по ключу сервера

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md)

**Гейт снят 2026-09-14.** Прежнее «не начинать до живого прогона 034/035» относилось к отменённой фазе и к двум смерженным; ничего из того, что оно защищало, больше не ждёт.

## Phase 1: Контракт (первым — Принцип VII)

- [ ] T001 Record in `docs/client-backend/protocol/contract-draft.md` §1 that the address is `wss` and the bytes are `https`, and that trust comes from the pairing link rather than from a certificate authority — commands, events and codes are untouched
- [ ] T002 Record in §3 that the link's 32 bytes are a FINGERPRINT — `sha256(SubjectPublicKeyInfo)` of the server's ECDSA P-256 identity key — not a public key, and rename the field accordingly
- [ ] T003 Record that the service page (035) stays plain HTTP on loopback: it has no network traffic, so TLS there is complexity with no purpose

## Phase 2: Ключ сервера

- [ ] T004 Mint the machine identity as ECDSA P-256 in `client_backend/internal/store/serverkey.go` — Ed25519 is refused by the client outright (research.md, decision 1). Device keys stay Ed25519 and are not touched
- [ ] T005 Store the private half as PKCS#8 and the public half as SPKI, both base64, in `client_backend/internal/store/serverkey.go` — a raw scalar carries no curve and silently changes meaning when written without left padding
- [ ] T006 Expose the private half through a narrow accessor returning a `crypto.Signer`, NOT through a field on `ServerIdentity` in `client_backend/internal/store/serverkey.go` — that struct is returned to the status page and to `device.invite`, two paths a secret must not reach
- [ ] T007 Derive the fingerprint when reading, never store it, in `client_backend/internal/store/serverkey.go` — a stored derivative is a second copy of one fact
- [ ] T008 Fix the doc comment on `ServerIdentity` in `client_backend/internal/store/serverkey.go`: it describes a `PrivateKey` field that does not exist and a form that is about to change
- [ ] T009 [P] Store test in `client_backend/internal/store/serverkey_test.go`: the stored private half parses as a P-256 key, the public half parses as its SPKI, the two agree, and the fingerprint survives a restart

## Phase 3: Сертификат и слушатель

- [ ] T010 Build a self-signed certificate from the identity key in `client_backend/internal/server/tls.go` — no SAN (the client ignores names, FR-004a), `NotBefore` a day back (home clocks lie), a far `NotAfter` (an expiry must never become an unrepairable refusal, FR-006), and `Leaf` filled so the DER is parsed once rather than per handshake
- [ ] T011 Rebuild the certificate at every start and keep it in memory only in `client_backend/internal/server/tls.go` — storing it is a second record of one fact that can drift from the key, and a drifted certificate is indistinguishable from a man in the middle
- [ ] T012 Serve the main listener over TLS in `client_backend/internal/server/server.go`, and refuse a plain connection — with no `-tls=false` escape, which would be a way to bypass the whole phase (FR-010b)
- [ ] T013 Leave the status listener as plain HTTP on loopback in `client_backend/internal/server/server.go`, and say so in the startup log lines
- [ ] T014 Put the fingerprint into the pairing link in `client_backend/internal/server/pairing_link.go` and at its three call sites (startup, status page, `device.invite`)
- [ ] T015 [P] Server test in `client_backend/internal/server/tls_test.go`: the certificate's SPKI fingerprint equals the one the pairing link carries
- [ ] T016 [P] Server test in `client_backend/internal/server/tls_test.go`: a restart produces a DIFFERENT certificate over the SAME key, and a client pinned to that fingerprint accepts it
- [ ] T017 Dial TLS from the test helpers in `client_backend/internal/server/server_test.go` using the server's own `tls.Config` — NOT `httptest.NewTLSServer`, whose stock certificate would make T015 vacuous

## Phase 4: Клиент — сверка

- [ ] T018 Write the pure check in `lib/general/pairing/server_pin.dart`: find the fixed 26-byte P-256 SPKI header in `cert.der`, take 91 bytes, `sha256`, compare against the stored fingerprint. First match only, require 91 bytes to remain, and RETURN false rather than throw on anything unexpected — the callback runs inside BoringSSL
- [ ] T019 Ignore the certificate's name, expiry and issuer in `lib/general/pairing/server_pin.dart` — a server that sits in a flat changes address, and each of those three is a refusal nobody can repair
- [ ] T020 Rename the link field from key to fingerprint in `lib/general/pairing/pairing_link.dart` and at every call site — a field named "key" holding a hash lies to its first reader
- [ ] T021 Add a reader for the stored fingerprint to `lib/domain/repository/app/session_repository.dart` and its impl — today `saveServer` writes it and nothing ever reads it back
- [ ] T022 Hold ONE `HttpClient` on `lib/data/remote/socket/socket_channel_factory.dart` and pass it to `IOWebSocketChannel.connect(customClient:)` — `WebSocket.connect` does not close the client it is given, so one per connect leaks on every reconnect of an infinite ladder
- [ ] T023 Give Dio the same pinned client through `IOHttpClientAdapter` in `lib/data/remote/api_client.dart` — the file bytes have gone over plain HTTP since 028 and are half of SC-007
- [ ] T024 Build `wss` and `https` addresses in `lib/data/sync/live_session_starter.dart` and `lib/data/remote/api_client.dart`, with no fallback to a clear channel
- [ ] T025 Stop treating `AppConfig.apiUrl` as a live fallback in `lib/data/sync/live_session_starter.dart` — an address from the build has no fingerprint and can never be checked (FR-013)
- [ ] T026 [P] Client test in `test/general/pairing/server_pin_test.dart`: a certificate on another key is refused, the same key with a new certificate is accepted, a truncated or headerless DER is refused without throwing

## Phase 5: Клиент — отказ, который читается

- [ ] T027 Add a terminal phase for "this is not your server" in `lib/domain/model/session/session_phase.dart`, separate from `unauthenticated`
- [ ] T028 Route a pin refusal to that phase in `lib/data/remote/socket/nox_socket_client.dart` WITHOUT the retry ladder (FR-007a) and WITHOUT the forced-logout path (FR-007b) — routing it through `unauthenticated` would hand an interposed server a remote wipe of every device
- [ ] T029 Carry the phase, not a boolean, into the three blocs that render the connection strip — `chats_list_bloc.dart`, `chat_thread_bloc.dart`, `chat_card_bloc.dart`: today every consumer reduces it through `isCurrent`, which is why a refusal is indistinguishable from a dead network
- [ ] T030 Add two l10n keys to `lib/l10n/app_en.arb` and `app_uk.arb` — one for the paired case, one for the pairing screen, where the relationship does not exist yet
- [ ] T031 Show the refusal on 5.1, 5.2 and 5.4 through the existing `AppNoticeStripWidget` with the stock `error` glyph — no new widget, no new asset
- [ ] T032 Show the refusal on the login screen in `lib/presentation/pages/login_page/` — at pairing time the fingerprint comes from the link being scanned, not from the session
- [ ] T033 [P] Bloc tests: a refusal raises the notice, stops the ladder, and wipes nothing — mutation-check the non-consequence as firmly as the consequence
- [ ] T034 [P] Goldens for the refusal on both widths wherever the screen already has them

## Phase 6: Платформа

- [ ] T035 Remove `usesCleartextTraffic` from `android/app/src/debug/AndroidManifest.xml` — together with the reason it was added
- [ ] T036 Check the four other platforms open a pinned connection: macOS, Windows, Linux, iOS

## Phase 7: Стенд, смоук, живой прогон

- [ ] T037 Teach `cmd/smoke` to read the fingerprint out of the link and dial `wss` with it in `client_backend/cmd/smoke/main.go` — it currently skips those 32 bytes with a comment that says TLS will check them
- [ ] T038 Replace the `sleep 2` in `scripts/demo-stand.sh` with a readiness poll and say in the banner that a fresh stand means a fresh key, so every earlier link is dead
- [ ] T039 Pass the fingerprint into the four probes under `test/live/` — they dial `ws://127.0.0.1:8080` directly and never pair, so they hold no stored fingerprint
- [ ] T040 Write `specs/036-tls-pinning/quickstart.md` the way 038's is written: the stand, two devices, a packet capture proving no text on the wire, and a deliberately wrong fingerprint proving the refusal is real

## Phase 8: Polish

- [ ] T041 [P] Record the phase's invariants in `client_backend/CLAUDE.md`: one key for identity and for the channel, ECDSA because the client refuses Ed25519, the certificate rebuilt every start, no fallback
- [ ] T042 [P] Mark 036 ☑ in `docs/client-backend/roadmap-stage2.md` and note that Q14 (ATS, App Review) stays open
- [ ] T043 Run `gofmt -l .`, `go vet ./...`, `go test -race ./...`, `make gate`, `make golden-verify`
- [ ] T044 Live run by the owner per [quickstart.md](./quickstart.md)
