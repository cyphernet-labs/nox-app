# Tasks: приложение через Tor — дома напрямую, вне дома через встроенный Tor

**Input**: документы из `/specs/040-tor-app/`: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md.

**Tests**: обязательны. Каждая задача с кодом идёт с тестом. Экраны — с голденами обеих ширин, светлая и тёмная тема (конституция, Принципы III и VI).

**Organization**: по историям спеки. Исключение — US7 (замер): у неё P3, но FR-034 ставит её до встраивания, поэтому её фаза идёт сразу за подготовкой и запирает остальное.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: можно параллельно — разные файлы, нет незавершённых зависимостей.
- **[Story]**: US1–US7 из spec.md.

---

## Phase 1: Setup — пакет `nox_tor`, тулчейн, платформы

- [X] T001 Create the Rust crate `packages/nox_tor/rust/`:
  - `Cargo.toml`:
    - deps: `arti-client =0.47.0` with tokio, rustls, onion-service-client, static-sqlite, compression, keymgr, experimental-api, ephemeral-keystore; `tor-hscrypto`, `tor-llcrypto`, `tor-keymgr`, `tor-config` `=0.47.0`; tokio (rt-multi-thread, net, io-util, time, sync); rustls with ring; tracing; tracing-subscriber; sha3; data-encoding; subtle;
    - `crate-type = ["staticlib","cdylib"]`;
    - release profile: opt-level z, fat LTO, codegen-units 1, strip, panic abort.
  - `rust-toolchain.toml`: 1.93.1, targets aarch64/x86_64 apple darwin, aarch64-apple-ios, aarch64-apple-ios-sim, x86_64-apple-ios, aarch64/armv7/x86_64 android, x86_64/aarch64 windows msvc.
  - `Cargo.lock` with `libc` held at 0.2.189 (`cargo update -p libc --precise 0.2.189`).
  - Empty `src/lib.rs` that builds.
- [X] T002 Create the Dart package `packages/nox_tor/`:
  - `pubspec.yaml`: `resolution: workspace`; deps `hooks`, `code_assets`, `native_toolchain_rust: 1.0.4+0`, `ffi`; dev `test`.
  - `hook/build.dart`, per research decision 1:
    - `OS.linux` → no assets;
    - Android `CC_*`/`CXX_*`/`CARGO_TARGET_*_LINKER` → `<triple><targetNdkApi>-clang`;
    - iOS `IPHONEOS_DEPLOYMENT_TARGET=13.0`;
    - `Cargo.toml`, `Cargo.lock` and `rust-toolchain.toml` in `output.dependencies`.
  - Placeholders for `lib/nox_tor.dart` and `lib/src/nox_tor_bindings.dart`.
- [X] T003 Add `workspace: [packages/nox_tor]` and `nox_tor: {path: packages/nox_tor}` to the root `pubspec.yaml`, run `fvm flutter pub get`, and confirm in `pubspec.lock` that only `native_toolchain_rust`, `toml`, `hooks`, `code_assets` and `nox_tor` were added (mockito stays 5.6.4).
- [X] T004 [P] Update `Makefile`: the `format` target also covers `packages/nox_tor`; add a `tor-test` target (`cd packages/nox_tor/rust && cargo test` and `cd packages/nox_tor && fvm dart test`).
- [X] T005 [P] Platform files:
  - `NSLocalNetworkUsageDescription` "NOX connects to your server on your home network." in `ios/Runner/Info.plist` and `macos/Runner/Info.plist`;
  - `com.apple.security.network.server` in `macos/Runner/Release.entitlements`;
  - an explicit `android.permission.INTERNET` in `android/app/src/main/AndroidManifest.xml`.

**Checkpoint**: `fvm flutter pub get` passes, `cargo build` of the empty crate passes, `fvm flutter build macos --debug` builds with the empty library.

---

## Phase 2: User Story 7 — замер до встраивания (Priority: P3, но первым — FR-034) 🔒

**Goal**: the real module is built and measured on the four platforms; the +25 MB gate is checked before any integration into the app.

**Independent Test**: the numbers in `research.md` → «Замер» are repeatable by its method.

- [X] T006 [US7] Implement the engine in `packages/nox_tor/rust/src/engine.rs` and `src/status.rs`:
  - an owned tokio runtime on its own thread;
  - `start(state_dir, cache_dir)`: install the rustls ring provider, `TorClientConfigBuilder::from_directories`, ephemeral primary keystore, `create_bootstrapped` within a 90 s budget;
  - `stop()`;
  - a status snapshot under a short lock (`NoxTorStatus` from contracts/ffi.md);
  - bootstrap progress from `bootstrap_status()`;
  - `set_dormant`.
- [X] T007 [US7] Implement target, key and bridge in `packages/nox_tor/rust/src/bridge.rs`:
  - `set_target(onion, port, key32)`: remove the previous key via `remove_service_discovery_key`, then `insert_service_discovery_key`;
  - bind `127.0.0.1:0` and draw a new 32-byte secret;
  - per connection: read the secret within 5 s and compare it in constant time (`subtle`), `TorClient::connect((onion, port))` within 45 s, then `copy_bidirectional`;
  - record `missing_client_auth`, `wrong_client_auth`, `timeout` or `network` in the snapshot;
  - `clear_target()`.
- [X] T008 [P] [US7] Implement the remaining modules:
  - `packages/nox_tor/rust/src/onion.rs`: `onion_from_pubkey` per rend-spec-v3 (SHA3-256 checksum, base32 lowercase, `.onion`);
  - `packages/nox_tor/rust/src/obsolete.rs`: a `tracing-subscriber` layer that turns a WARN+ event from target `arti_client::protostatus` into `obsolete` and asks the control thread to `shutdown_background` the runtime (research decision 6); `SoftwareDeprecated` at bootstrap → `obsolete`.
- [X] T009 [US7] Export the C ABI from contracts/ffi.md in `packages/nox_tor/rust/src/lib.rs`:
  - functions: `nox_tor_start`, `stop`, `set_target`, `clear_target`, `set_dormant`, `status`, `bridge_secret`, `onion_from_pubkey`, `version`;
  - no panic crosses the boundary (`catch_unwind` → `internal`);
  - `#[cfg(test)]` tests:
    - the bridge refuses a wrong or short secret and closes;
    - status encoding round-trips;
    - the onion vector from 039 (RFC 8032 seed → `25njqamcweflpvkl73j4szahhihoc4xt3ktcgjnpaingr5yhkenl5sid`);
    - a synthetic `arti_client::protostatus` ERROR event sets `obsolete` and triggers the shutdown;
    - `set_target` rejects a non-onion host and a short key.
- [X] T010 [US7] Implement the Dart wrapper:
  - `packages/nox_tor/lib/src/nox_tor_bindings.dart`: `@Native` externals for every function;
  - `packages/nox_tor/lib/nox_tor.dart`: `NoxTor` with `isSupported` (false on Linux or when the symbol lookup fails), `NoxTorSnapshot` and the typed codes;
  - `packages/nox_tor/test/hook_test.dart`: `testCodeBuildHook(targetOS: OS.linux)` yields no assets.
- [X] T011 [US7] Add the timing harness `packages/nox_tor/rust/examples/bootstrap.rs`:
  - cold and warm bootstrap time;
  - first and repeated keyed connect time against an onion and key given on the command line (a local `noxd` with Tor, 039);
  - process RSS.
- [X] T012 [US7] Measure per research decision 14 and quickstart «Замер»:
  - release APK arm64 with and without `nox_tor`;
  - iOS release `nox_tor.framework`;
  - macOS framework size;
  - timings and RSS from T011 on macOS.

  Write the numbers into `specs/040-tor-app/research.md` → «Замер». **STOP and report to the owner if any platform adds more than 25 MB to the download size.**

**Checkpoint (gate)**: size within budget on every platform → continue; otherwise stop.

---

## Phase 3: Foundational — общая основа для всех историй

**⚠️ CRITICAL**: no user-story phase starts before this one is done.

- [X] T013 [P] Domain models in `lib/domain/model/connection/` and `lib/domain/model/device/device_invite.dart`, per data-model.md, with `freezed` where the neighbours use it:
  - `server_addresses.dart`: `ServerAddresses` with `candidates(linkAddress)`;
  - `connection_path.dart`;
  - `connection_status.dart`: `ConnectionStatus`, `ConnectionState`, with derived `isOffline`, `isServerMismatch`, `showsTorBadge`;
  - `tor_status.dart`: `TorStatus`, `TorState`, `TorError`;
  - `DeviceInvite`.

  Unit tests in `test/domain/model/connection/`.
- [X] T014 [P] Domain interfaces:
  - `lib/domain/service/tor_service.dart`: start, stop, setTarget, clearTarget, setDormant, status stream, bridge port and secret, onionFromPublicKey, isSupported;
  - `lib/domain/service/connection_status_service.dart`;
  - `lib/domain/service/app_lifecycle_service.dart`;
  - `lib/domain/repository/connection/server_addresses_repository.dart`;
  - `lib/domain/repository/connection/access_key_repository.dart`;
  - `lib/domain/service/network_change_service.dart`: `NetworkChangeService.watchChanges()`, implemented in `lib/data/service/network_change_service_impl.dart` (connectivity_plus result changes; a quiet one for the test env). It is a service of its own rather than a new method on `ConnectivityService`, whose interface three private test fakes implement.
- [X] T015 Implement the Tor services in `lib/data/service/tor/`:
  - `native_tor_service.dart`, `@LazySingleton(env: [dev, prod])`: over `NoxTor`, the status stream polled every 250 ms while bootstrapping and every 2 s otherwise, state and cache dirs from `path_provider` (support/`nox_tor_state`, cache/`nox_tor_cache`);
  - `fake_tor_service.dart`, `env: [test]`: scriptable;
  - `tor_capability.dart`: false on Linux, like `VideoPlaybackCapability`.

  When the module reports `obsolete`, the native service writes `tor.obsolete_build` = the app build number to `SharedPreferences` (FR-026).

  Run `make generate`. Tests: `test/data/service/tor/native_tor_service_test.dart` with an injected `NoxTor` facade fake.
- [X] T016 Implement the repositories in `lib/data/repository/connection/`:
  - `server_addresses_repository_impl.dart`: `session.server_addresses` JSON;
  - `access_key_repository_impl.dart`: X25519 via `cryptography`, `session.access_key`, `session.access_key_registered`, `session.invite_onion`, `session.invite_access_key`.

  The private keys are written with `IOSOptions`/`MacOsOptions(accessibility: KeychainAccessibility.unlocked_this_device)`, so no backup carries them to another device (FR-014).

  Add every new key to `clear()` and to `discardSignIn()` (except `session.access_key`) in `lib/data/repository/app/session_repository_impl.dart`. Tests: `test/data/repository/connection/server_addresses_repository_impl_test.dart`, `access_key_repository_impl_test.dart`, `test/data/repository/app/session_repository_impl_test.dart` (clear removes the new keys).
- [X] T017 [P] Implement `lib/data/service/app_lifecycle_service_impl.dart` (`AppLifecycleListener` → `Stream<AppLifecycleState>`, dev/prod) and a test-env fake; tests in `test/data/service/app_lifecycle_service_impl_test.dart`.
- [X] T018 Read the server's addresses:
  - in `lib/data/remote/socket/nox_socket_client.dart`: parse `addresses` from the greeting reply into a `ServerAddresses` stream, cleared in `_teardown`, and expose the greeting's capability flag (`supportsAccessKeys`);
  - in `lib/data/sync/sync_service.dart`: handle the seq-0 `server.addresses` event next to `device.revoked`/`identity.updated`, saving through `ServerAddressesRepository` without touching the cursor.

  Rewrite the 039 compatibility tests: group 'a server from phase 039' in `test/data/remote/socket/nox_socket_client_test.dart` and the `server.addresses` test in `test/data/sync/sync_service_test.dart`. They now assert the addresses are read and stored, and the cursor is still untouched.
- [X] T019 Let the socket ask for a target before each attempt:
  - `NoxSocketClient.start` takes a `SocketTargetProvider` (async: next `Uri` or none);
  - `_openOnce` asks it on every attempt;
  - add a `connectTimeout` in `lib/data/remote/socket/socket_channel_factory.dart`: 45 s for `.onion`, 10 s otherwise;
  - make the pin-refusal attribution per connection rather than a process-wide counter delta.

  Tests in `test/data/remote/socket/nox_socket_client_test.dart` with `FakeSocketFactory`: the target is asked per attempt; none → backoff; onion refusal → `serverMismatch`.
- [X] T020 Dial onion hosts through the bridge in `lib/data/remote/pinned_http_client.dart`:
  - a host ending in `.onion` → `Socket.connect(127.0.0.1, bridgePort)` → write the 32-byte secret → `SecureSocket.secure(socket, host: onion, supportedProtocols: ['http/1.1'])` → the existing leaf `ServerPin.matches`;
  - the bridge port and secret come from an injected `TorBridgeEndpoint` read at handshake time.

  Tests in `test/data/remote/pinned_http_client_onion_test.dart` with a loopback fake bridge in front of the honest and hostile TLS fixtures: the honest one passes, the hostile one is refused, a wrong secret closes.
- [X] T021 Key the epoch on the fingerprint in `lib/data/sync/live_session_starter.dart`: `fp:<fingerprint>`. Migrate a stored `live:` epoch without wiping it (`lib/data/local/sync/sync_dao.dart` if a helper is needed). Tests in `test/data/sync/live_session_starter_test.dart`:
  - a `live:` epoch migrates and the chats stay;
  - a different `fp:` wipes;
  - the same `fp:` is a no-op.
- [X] T022 Implement `lib/data/sync/connection/access_key_registrar.dart`:
  - `pair` always sends `access_key` (own public), in `nox_socket_client.dart` `pair()` and `lib/data/sync/live_identity_handshake.dart`;
  - after the first greeting with `addresses` while not registered → `device.setAccessKey`; success → registered;
  - `invalid_request` → new key, at most 3 per session;
  - `unauthenticated` → the existing revocation path.

  Tests in `test/data/sync/connection/access_key_registrar_test.dart` and the handshake test.
- [ ] T023 Implement `ConnectionStatusService`:
  - `lib/data/sync/connection/connection_status_service_impl.dart` (dev): socket phase plus selector events, path, `torObsolete` from `tor.obsolete_build`; offline smoothing per research decision 12;
  - `lib/data/service/phase_connection_status_service.dart` (prod/test): from `SessionPhaseService`.

  Tests in `test/data/sync/connection/connection_status_service_impl_test.dart`: smoothing — the first failed round → offline, retries keep offline, success clears it.

**Checkpoint**: `make gate` green; nothing user-visible has changed yet.

---

## Phase 4: User Story 1 — переписка вне дома (Priority: P1) 🎯 MVP

**Goal**: when the direct path does not answer, the app connects through Tor and the conversation works.

**Independent Test**: quickstart scenario 2 (`nox.forceTor=true`) on macOS: messages and a file go through Tor.

- [X] T024 [P] [US1] Implement `lib/data/sync/connection/direct_prober.dart`:
  - its own `PinnedHttpClient`, TLS + leaf pin + `GET /health` per candidate;
  - 2.5 s per attempt; the first candidate at once, the rest after 300 ms in parallel; first success wins; 5 s budget;
  - a pin refusal marks the candidate «not home» (FR-005).

  Tests in `test/data/sync/connection/direct_prober_test.dart` with loopback honest and hostile TLS servers.
- [X] T025 [US1] Implement `lib/data/sync/connection/connection_path_selector.dart`:
  - direct candidates via the prober, else Tor when available: platform, onion known, key registered or invite key, not obsolete for this build;
  - `TorService.start` + `setTarget(onion, 443, key)`, wait for ready ≤ 90 s, yield `wss://<onion>:443/ws`;
  - publish path events for `ConnectionStatusService`;
  - the debug-only `nox.forceTor` define skips direct candidates (`kDebugMode` guard).

  Tests in `test/data/sync/connection/connection_path_selector_test.dart` with fake prober, Tor and clock:
  - direct wins;
  - Tor fallback;
  - no onion → none;
  - Linux → direct only;
  - obsolete → no Tor;
  - forceTor ignored in release mode.
- [X] T026 [US1] Wire the selector into `lib/data/sync/live_session_starter.dart`:
  - start the socket with the selector as target provider;
  - `ApiClient.initBase` follows the selected path;
  - `TorBridgeEndpoint` is fed from `TorService`.

  Tests in `test/data/sync/live_session_starter_test.dart`: the socket gets the onion URL when direct fails; file base URL follows.
- [X] T027 [US1] Make sure commands sent while the path comes up wait instead of failing: the outbox drains on live, and interactive commands surface `connection` only after the bring-up budget (`lib/data/sync/outbox_service.dart` and the socket send path). Test in `test/data/sync/outbox_service_test.dart`.

**Checkpoint**: US1 works with `nox.forceTor` on macOS against a local `noxd` with Tor.

---

## Phase 5: User Story 2 — дома напрямую, Tor выключен (Priority: P1)

**Goal**: back on the direct path when it works; Tor stopped; nothing lost.

**Independent Test**: quickstart scenario 3; the selector tests with a fake clock.

- [X] T028 [US2] Return to the direct path in `connection_path_selector.dart`:
  - while on Tor: on `watchNetworkChanges` and every 2 min, probe direct candidates;
  - when one answers: switch the socket to it (probe verified first), then `TorService.clearTarget` + `stop` once the new connection is live (≤ 10 s).

  Tests with a fake clock and fake network events:
  - switch happens;
  - Tor stops within 10 s;
  - no switch on a hostile direct answer.
- [X] T029 [US2] On the direct path, a network change probes the current address; if it does not answer, reconnect through the selector. Test in the same file.
- [X] T030 [US2] Background (iOS/Android) via `AppLifecycleService`:
  - paused → `setDormant(true)`;
  - resumed → `setDormant(false)` and an immediate reconnect when not live;
  - a Tor client not ready within 10 s → stop + start from the same dirs.

  Desktop ignores it. Tests in `connection_path_selector_test.dart` with a fake lifecycle.
- [ ] T031 [US2] Lossless switch test in `test/data/sync/live_session_starter_test.dart`, run over 20 switches (SC-005): a message sent during each switch goes out once (outbox idempotency + replay `since`) and incoming events are not duplicated (seq de-dup).

---

## Phase 6: User Story 3 — смена адреса ничего не стирает (Priority: P1)

**Goal**: a new server address is learned (through Tor if needed) and the direct path resumes on it; history intact.

**Independent Test**: quickstart scenario 8; selector scenario test.

- [X] T032 [US3] Record `last_good` in `ServerAddressesRepository` on every successful direct connection (`connection_path_selector.dart`). Candidate order is `last_good`, then the server list, then the link address. Tests in the repository and selector tests.
- [X] T033 [US3] Scenario test in `test/data/sync/connection/connection_path_selector_test.dart`: the old address is dead → Tor → `server.addresses` brings a new direct address → the next probe switches to it; the epoch does not change (fingerprint), so no wipe.

---

## Phase 7: User Story 4 — второе устройство из другой сети (Priority: P2)

**Goal**: version 2 links pair from another network; invites ask for onion; home-only invites say so.

**Independent Test**: quickstart scenarios 4–6.

- [X] T034 [P] [US4] Support version 2 in `lib/general/pairing/pairing_link.dart`: `onionPub`, `onionPort`, `oneTimePriv`; lengths 122/134/119+N. Tests in `test/general/pairing/pairing_link_test.dart`:
  - replace 'a future version is refused' with v2 vectors built like the server's (IPv4, IPv6, DNS);
  - version 3 is still refused;
  - v1 is unchanged.
- [ ] T035 [US4] Sign in with a v2 link in `lib/data/repository/app/auth_repository_impl.dart` `signIn` and `lib/data/sync/live_identity_handshake.dart`:
  - store `session.invite_onion` (derived through `TorService.onionFromPublicKey`; skipped where Tor is unsupported) and `session.invite_access_key`;
  - the selector uses the invite key when the device has no registered key;
  - after the `pair` reply, success or not, erase both invite records and switch the Tor target to the own key.

  Tests in `test/data/repository/app/auth_repository_impl_test.dart` and the handshake test.
- [X] T036 [US4] Request onion invites:
  - `DeviceRepository.inviteDevice` returns `DeviceInvite` and sends `{"onion": true}` (`lib/domain/repository/device/device_repository.dart`, `lib/data/repository/device/device_repository_impl.dart`);
  - `DevicesBloc` and `DevicesState` carry `inviteHomeOnly` (`lib/presentation/pages/devices_page/bloc/`);
  - `AppInviteCardWidget` shows `devicesInviteHomeOnly` when home-only (`lib/presentation/widgets/settings/app_invite_card_widget.dart`);
  - ARB EN/UK.

  Tests: `device_repository_impl_test.dart`, `devices_bloc_test.dart`, `app_invite_card_widget_test.dart`. Goldens: the invite card widget with and without the note, plus the devices page mobile and desktop with the note.
- [X] T037 [US4] Login: a v1 link whose server does not answer, or answers with a key the link does not name, shows `loginHomeNetworkOnly` (`lib/presentation/pages/login_page/bloc/login_bloc.dart`, `login_page.dart`, ARB EN/UK). Tests in `test/presentation/pages/login_page/bloc/login_bloc_test.dart`.

---

## Phase 8: User Story 5 — ключ доступа живёт только на устройстве (Priority: P2)

**Goal**: the key is created and kept on the device, re-registered when refused, and wiped on logout with all Tor state.

**Independent Test**: registrar tests; logout tests; quickstart scenario 7.

- [ ] T038 [US5] Wipe on logout in `lib/data/repository/app/auth_repository_impl.dart`: right after `LiveSessionStarter.stop`, call `TorService.stop()` and delete the Tor state and cache directories. `clear()` already covers the keys and addresses (T016). Tests in `test/data/repository/app/auth_repository_impl_test.dart`: Tor stopped, dirs deleted, keys gone (SC-007).
- [X] T039 [US5] Handle a key the service does not know: a `wrong_client_auth` from the bridge marks the key unregistered, so the next direct greeting re-registers it, and the selector stops retrying Tor until then (`access_key_registrar.dart`, `connection_path_selector.dart`). Tests in both test files.

---

## Phase 9: User Story 6 — видно, каким путём идёт связь (Priority: P2)

**Goal**: only deviations are shown — a `Tor` badge and `Connecting…` — in the corner on both widths, EN/UK. «No connection» is smoothed; there is an update prompt for an obsolete client.

**Independent Test**: indicator goldens and widget tests; quickstart scenarios 2–3 visually.

- [X] T040 [P] [US6] Add the keys from contracts/ui-states.md to `lib/l10n/app_en.arb` and `lib/l10n/app_uk.arb` (same key sets), then run `make generate`.
- [ ] T041 [US6] Implement the indicator:
  - `ConnectionIndicatorBloc` (Freezed, over `ConnectionStatusService`): `lib/presentation/widgets/state/connection_indicator/bloc/`;
  - `AppConnectionIndicatorWidget`: `lib/presentation/widgets/state/app_connection_indicator_widget.dart`, per contracts/ui-states.md:
    - states: nothing / `Tor` / `Connecting…` / `Connecting…` + `Tor`;
    - tokens only;
    - semantics label; 48×48 tap target;
    - tap → bottom sheet on narrow, dialog on wide, with `connectionInfo*`; the local-network line on iOS and macOS only.

  Tests:
  - widget tests in `test/presentation/widgets/state/app_connection_indicator_widget_test.dart`, including one under the `uk` locale (SC-006);
  - bloc test;
  - widget goldens: four states, light and dark;
  - accessibility checks next to `test/presentation/widgets/accessibility_test.dart`.
- [ ] T042 [US6] Place the indicator:
  - narrow: chats list app bar before the account avatar (`lib/presentation/pages/chats_list_page/chats_list_page.dart`) and chat thread app bar before the invite action (`lib/presentation/pages/chat_thread_page/chat_thread_page.dart`);
  - wide: an optional `trailing` on `AppWindowTitlebarWidget` (`lib/presentation/widgets/shell/app_window_titlebar_widget.dart`), filled by `TabBarShell` (`lib/presentation/widgets/shell/tab_bar_shell_widget.dart`).

  Tests in `app_window_titlebar_widget_test.dart` and the shell test. Page goldens:
  - 5.1 and 5.2 mobile with `online(tor)` and `connecting(tor)`;
  - shell desktop with the same two states.
- [ ] T043 [US6] Drive banners from `ConnectionStatusService` instead of `!phase.isCurrent` in `ChatsListBloc`, `ChatThreadBloc` (the outbox flush edge stays on «became current») and `ChatCardBloc`. Update their tests and fakes. The «No connection» banner shows only for `offline`.
- [ ] T044 [US6] Show `connectionTorObsolete` as a notice strip on 5.1 (both widths) when `torObsolete`. Tests plus goldens mobile and desktop.

**Checkpoint**: `make gate` and `make golden-verify` green; all user stories work independently.

---

## Phase 10: Polish & Cross-Cutting Concerns

- [ ] T045 [P] Update the blueprints in `docs/blueprints/mobile/`:
  - `14-networking-and-auth.md`: path selection, Tor transport, bridge, lifecycle, network changes;
  - `04-data-layer.md`: onion dial in §7а pinning;
  - `02-dependency-injection.md`: new registrations and env splits;
  - `01-stack-and-tooling.md`: Rust toolchain, native assets, workspace package;
  - `09-build-and-secrets-infra.md`: Rust prerequisite, NDK, CI compile-check needs rustup.
- [ ] T046 [P] Update the design docs:
  - `docs/design/spec/` (5.1, 5.2, devices invite, shell titlebar; decisions table);
  - `docs/design/system/nox-mobile-screens/screens/5-1-chats.md`, `5-2-thread.md`, `7-8-devices.md`;
  - `docs/design/system/nox-desktop-screens/screens/01-chats.md`, `09-devices.md`.

  Content: indicator states and placement, the home-only invite note, the obsolete strip.
- [ ] T047 [P] Update `CLAUDE.md` (implementation notes: Tor transport, path selection, epoch by fingerprint, access key, build prerequisites) and `docs/client-backend/roadmap-tor.md` (stage 2 status).
- [ ] T048 Run the quickstart end-to-end scenarios on macOS, the iOS simulator and the Android emulator against a local `noxd` with Tor. Record bring-up timings and memory in `research.md` «Замер», and note anything that differs.
- [ ] T049 Run the gates: `make gate`, `make golden-verify`, `make tor-test`. The Go gate is not touched: no Go changes.
- [ ] T050 Keep the onion address and keys out of the logs (FR-013, SC-008, Constitution I):
  - Audit every `logRepository` call in `lib/data/remote/socket/`, `lib/data/remote/pinned_http_client.dart`, `lib/data/sync/connection/` and `lib/data/service/tor/`.
  - Hosts ending in `.onion` are logged as `[onion]`; keys and secrets are never logged.
  - Test in `test/data/sync/connection/log_redaction_test.dart`: capture `LogRepository` output through a selector run with Tor, a pairing with a v2 link, and a bridge failure; assert there is no `.onion` and no base64 key material.
- [ ] T051 [P] Prepare CI for the native package for when the paused workflows are re-enabled:
  - `.github/workflows/compile-check.yml`: install rustup with the toolchain from `packages/nox_tor/rust/rust-toolchain.toml`; on Android, also NDK 28.2 before the build. The Linux job needs nothing.
  - `.github/workflows/ci.yml`: the macOS gate job needs rustup too, because `flutter test` runs the hook.
- [ ] T052 Put the owner's device checks (quickstart «Проверки на устройстве») into the PR description: iOS local-network prompt and background, mobile network away from home, Windows build and bootstrap.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (1)** — no dependencies.
- **US7 Замер (2)** — after Setup. **Gates everything after it** (+25 MB).
- **Foundational (3)** — after the gate. Blocks all stories.
- **US1 (4)** — after Foundational. US2 and US3 build on the selector from US1.
- **US2 (5), US3 (6)** — after US1; independent of each other.
- **US4 (7), US5 (8)** — after Foundational and US1 (they use the selector); independent of each other.
- **US6 (9)** — after Foundational (`ConnectionStatusService`); can go in parallel with US2–US5.
- **Polish (10)** — after the stories.

### Within Each User Story

Tests come with each task, in the same change. Models come before services, and services before UI. The gates (`make gate` + `make golden-verify`) run before every commit that touches Dart.

### Parallel Opportunities

- T004 and T005 in Setup.
- T008 in Phase 2, beside T006 and T007 in separate files.
- T013, T014 and T017 in Foundational.
- T024 in US1 (independent file).
- T034 in US4.
- T040 in US6.
- T045, T046, T047 and T051 in Polish.

## Parallel Example: User Story 6

```text
Task: "T040 Add the connection keys to app_en.arb and app_uk.arb"
Task (after T040): "T041 Implement ConnectionIndicatorBloc and AppConnectionIndicatorWidget"
Task (after T041): "T042 Place the indicator on chats list, thread and the window titlebar"
Task (independent of T041): "T043 Drive the banners from ConnectionStatusService"
```

## Implementation Strategy

### MVP First

Setup → measurement gate → Foundational → US1. That gives the conversation through Tor away from home with `nox.forceTor` on macOS.

### Incremental Delivery

1. US2 + US3: the path returns home, and addresses change safely.
2. US4 + US5: pairing from another network; key lifecycle.
3. US6: the visible connection state.
4. Polish: docs, end-to-end runs and the owner's device checks.

Each phase ends with green gates and its own commit.

## Notes

- Windows is not buildable from this machine: `cargo check` for MSVC fails on C headers. Its verification is in T052 for the owner.
- Device-only checks (iOS background, the local-network prompt, a real mobile network) are listed for the owner in T052.
- Commit after each phase. Never commit with red gates.
