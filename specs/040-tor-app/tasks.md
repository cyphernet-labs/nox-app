# Tasks: приложение через Tor — дома напрямую, вне дома через встроенный Tor

**Input**: документы из `/specs/040-tor-app/`: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md.

**Tests**: обязательны. Каждая задача с кодом идёт с тестом. Экраны — с голденами обеих ширин, светлая и тёмная тема (конституция, Принципы III и VI).

**Organization**: по историям спеки. Исключение — US7 (замер): у неё P3, но FR-034 ставит её до встраивания, поэтому её фаза идёт сразу за подготовкой и запирает остальное.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: можно параллельно — разные файлы, нет незавершённых зависимостей.
- **[Story]**: US1–US7 из spec.md.

---

## Phase 1: Setup — пакет `nox_tor`, тулчейн, платформы

- [X] T001 Создать Rust-крейт `packages/nox_tor/rust/`:
  - `Cargo.toml`:
    - зависимости: `arti-client =0.47.0` с возможностями tokio, rustls, onion-service-client, static-sqlite, compression, keymgr, experimental-api, ephemeral-keystore; `tor-hscrypto`, `tor-llcrypto`, `tor-keymgr`, `tor-config` `=0.47.0`; tokio (rt-multi-thread, net, io-util, time, sync); rustls с ring; tracing; tracing-subscriber; sha3; data-encoding; subtle;
    - `crate-type = ["staticlib","cdylib","rlib"]` (`rlib` — для примера `examples/bootstrap.rs`);
    - профиль release: opt-level z, fat LTO, codegen-units 1, strip, panic unwind — не abort: без раскрутки стека не работает `catch_unwind`, под которым идёт каждая экспортируемая функция.
  - `rust-toolchain.toml`: 1.93.1, цели aarch64/x86_64 apple darwin, aarch64-apple-ios, aarch64-apple-ios-sim, x86_64-apple-ios, aarch64/armv7/x86_64 android, x86_64/aarch64 windows msvc.
  - `Cargo.lock` с `libc`, закреплённым на 0.2.189 (`cargo update -p libc --precise 0.2.189`).
  - Пустой `src/lib.rs`, который собирается.
- [X] T002 Создать Dart-пакет `packages/nox_tor/`:
  - `pubspec.yaml`: `resolution: workspace`; зависимости `hooks`, `code_assets`, `native_toolchain_rust: 1.0.4+0`, `ffi`; dev-зависимость `test`.
  - `hook/build.dart` по research, решение 1:
    - `OS.linux` → без ассетов;
    - Android `CC_*`/`CXX_*`/`CARGO_TARGET_*_LINKER` → `<triple><targetNdkApi>-clang`;
    - iOS `IPHONEOS_DEPLOYMENT_TARGET=13.0`;
    - `Cargo.toml`, `Cargo.lock` и `rust-toolchain.toml` в `output.dependencies`.
  - Заготовки `lib/nox_tor.dart` и `lib/src/nox_tor_bindings.dart`.
- [X] T003 Добавить `workspace: [packages/nox_tor]` и `nox_tor: {path: packages/nox_tor}` в корневой `pubspec.yaml`, выполнить `fvm flutter pub get` и убедиться по `pubspec.lock`, что добавились только `native_toolchain_rust`, `toml`, `hooks`, `code_assets` и `nox_tor` (mockito остаётся на 5.6.4).
- [X] T004 [P] Обновить `Makefile`: цель `format` охватывает и `packages/nox_tor`; добавить цель `tor-test` (`cd packages/nox_tor/rust && cargo test` и `cd packages/nox_tor && fvm dart test`).
- [X] T005 [P] Файлы платформ:
  - `NSLocalNetworkUsageDescription` "NOX connects to your server on your home network." в `ios/Runner/Info.plist` и `macos/Runner/Info.plist`;
  - `com.apple.security.network.server` в `macos/Runner/Release.entitlements`;
  - явное `android.permission.INTERNET` в `android/app/src/main/AndroidManifest.xml`.

**Checkpoint**: `fvm flutter pub get` проходит, `cargo build` пустого крейта проходит, `fvm flutter build macos --debug` собирается с пустой библиотекой.

---

## Phase 2: User Story 7 — замер до встраивания (Priority: P3, но первым — FR-034) 🔒

**Goal**: настоящий модуль собран и измерен на четырёх платформах; гейт +25 МБ проверен до любого встраивания в приложение.

**Independent Test**: числа в `research.md` → «Замер» воспроизводятся по описанной там методике.

- [X] T006 [US7] Реализовать движок в `packages/nox_tor/rust/src/engine.rs` и `src/status.rs`:
  - собственный tokio-runtime в отдельном потоке;
  - `start(state_dir, cache_dir)`: установить провайдер ring для rustls, `TorClientConfigBuilder::from_directories`, эфемерное основное хранилище ключей, `create_bootstrapped` в пределах 90 с;
  - `stop()`;
  - снимок статуса под коротким замком (`NoxTorStatus` из contracts/ffi.md);
  - ход подъёма из `bootstrap_status()`;
  - `set_dormant`.
- [X] T007 [US7] Реализовать цель, ключ и мост в `packages/nox_tor/rust/src/bridge.rs`:
  - `set_target(onion, port, key32)`: убрать прежний ключ через `remove_service_discovery_key`, затем `insert_service_discovery_key`;
  - привязать слушатель к `127.0.0.1:0` и сгенерировать новый 32-байтный секрет;
  - на каждое соединение: прочитать секрет в пределах 5 с и сравнить его за постоянное время (`subtle`), `TorClient::connect((onion, port))` в пределах 45 с, затем `copy_bidirectional`;
  - записывать в снимок `missing_client_auth`, `wrong_client_auth`, `timeout` или `network`;
  - `clear_target()`.
- [X] T008 [P] [US7] Реализовать остальные модули:
  - `packages/nox_tor/rust/src/onion.rs`: `onion_from_pubkey` по rend-spec-v3 (контрольная сумма SHA3-256, base32 в нижнем регистре, `.onion`);
  - `packages/nox_tor/rust/src/obsolete.rs`: слой `tracing-subscriber`, который по событию уровня WARN и выше от цели `arti_client::protostatus` выставляет `obsolete` и просит управляющий поток свернуть tokio-runtime через `shutdown_background` (research, решение 6); `SoftwareDeprecated` при подъёме → `obsolete`.
- [X] T009 [US7] Экспортировать C ABI из contracts/ffi.md в `packages/nox_tor/rust/src/lib.rs`:
  - функции: `nox_tor_start`, `stop`, `set_target`, `clear_target`, `set_dormant`, `status`, `bridge_secret`, `onion_from_pubkey`, `version`;
  - ни одна паника не пересекает границу (`catch_unwind` → `internal`);
  - тесты `#[cfg(test)]`:
    - мост отвергает неверный или короткий секрет и закрывает соединение;
    - статус кодируется и декодируется без потерь;
    - вектор onion из 039 (seed RFC 8032 → `25njqamcweflpvkl73j4szahhihoc4xt3ktcgjnpaingr5yhkenl5sid`);
    - синтетическое событие ERROR от `arti_client::protostatus` выставляет `obsolete` и запускает остановку;
    - `set_target` отвергает хост, не являющийся onion-адресом, и короткий ключ.
- [X] T010 [US7] Реализовать обёртку на Dart:
  - `packages/nox_tor/lib/src/nox_tor_bindings.dart`: внешние объявления `@Native` для каждой функции;
  - `packages/nox_tor/lib/nox_tor.dart`: `NoxTor` с `isSupported` (false на Linux или если поиск символа не удался), `NoxTorSnapshot` и типизированные коды;
  - `packages/nox_tor/test/hook_test.dart`: `testCodeBuildHook(targetOS: OS.linux)` не выдаёт ассетов.
- [X] T011 [US7] Добавить обвязку для замеров `packages/nox_tor/rust/examples/bootstrap.rs`:
  - время холодного и тёплого подъёма;
  - время первого и повторного подключения с ключом к onion-адресу; адрес и ключ задаются в командной строке (локальный `noxd` с Tor, 039);
  - RSS процесса.
- [X] T012 [US7] Провести замер по research, решение 14, и quickstart, раздел «Замер»:
  - release APK arm64 с `nox_tor` и без него;
  - `nox_tor.framework` в release-сборке iOS;
  - размер фреймворка на macOS;
  - время и RSS из T011 на macOS.

  Записать числа в `specs/040-tor-app/research.md` → «Замер». **Если хоть одна платформа прибавляет к размеру загрузки больше 25 МБ — ОСТАНОВИТЬСЯ и сообщить владельцу.**

**Checkpoint (гейт)**: размер в пределах бюджета на каждой платформе → продолжать; иначе — стоп.

---

## Phase 3: Foundational — общая основа для всех историй

**⚠️ CRITICAL**: ни одна фаза историй не начинается, пока эта не закончена.

- [X] T013 [P] Доменные модели в `lib/domain/model/connection/` и `lib/domain/model/device/device_invite.dart` по data-model.md, на `freezed` там, где его используют соседние модели:
  - `server_addresses.dart`: `ServerAddresses` с `candidates(linkAddress)`;
  - `connection_path.dart`;
  - `connection_status.dart`: `ConnectionStatus`, `LinkState`, с вычисляемыми `isOffline`, `isServerMismatch`, `showsTorBadge`;
  - `tor_status.dart`: `TorStatus`, `TorState`, `TorError`;
  - `DeviceInvite`.

  Модульные тесты в `test/domain/model/connection/`.
- [X] T014 [P] Доменные интерфейсы:
  - `lib/domain/service/tor_service.dart`: start, stop, setTarget, clearTarget, setDormant, поток статуса, порт и секрет моста, onionFromPublicKey, isSupported;
  - `lib/domain/service/connection_status_service.dart`;
  - `lib/domain/service/app_lifecycle_service.dart`;
  - `lib/domain/repository/connection/server_addresses_repository.dart`;
  - `lib/domain/repository/connection/access_key_repository.dart`;
  - `lib/domain/service/network_change_service.dart`: `NetworkChangeService.watchChanges()`, реализация — `lib/data/service/network_change_service_impl.dart` (изменения результата connectivity_plus; для тестового окружения — молчащая). Это отдельный сервис, а не новый метод `ConnectivityService`, чей интерфейс реализуют три приватных фейка в тестах.
- [X] T015 Реализовать сервисы Tor в `lib/data/service/tor/`:
  - `native_tor_service.dart`, `@LazySingleton(env: [dev, prod])`: поверх `NoxTor`; поток статуса опрашивается каждые 250 мс во время подъёма и каждые 2 с в остальное время; каталоги состояния и кэша — из `path_provider` (support/`nox_tor_state`, cache/`nox_tor_cache`);
  - `fake_tor_service.dart`, `env: [test]`: управляется из теста;
  - `tor_capability.dart`: false на Linux, как `VideoPlaybackCapability`.

  Когда модуль сообщает `obsolete`, нативный сервис записывает `tor.obsolete_client` = версию Tor-клиента из библиотеки в `SharedPreferences` (FR-026); номер сборки приложения для этого не годится — он не меняется с каждым выпуском.

  Выполнить `make generate`. Тесты: `test/data/service/tor/native_tor_service_test.dart` с внедрённым фейком фасада `NoxTor`.
- [X] T016 Реализовать репозитории в `lib/data/repository/connection/`:
  - `server_addresses_repository_impl.dart`: JSON в `session.server_addresses`;
  - `access_key_repository_impl.dart`: X25519 через `cryptography`, `session.access_key`, `session.access_key_registered`; `storedDeviceKey()` читает ключ, не создавая его. Одноразовый ключ ссылки v2 здесь не хранится — только в памяти селектора (FR-021).

  Закрытые ключи пишутся с `IOSOptions`/`MacOsOptions(accessibility: KeychainAccessibility.unlocked_this_device)`, чтобы ни одна резервная копия не перенесла их на другое устройство (FR-014).

  Добавить каждый новый ключ в `clear()` и в `discardSignIn()` (кроме `session.access_key`) в `lib/data/repository/app/session_repository_impl.dart`. Тесты: `test/data/repository/connection/server_addresses_repository_impl_test.dart`, `access_key_repository_impl_test.dart`, `test/data/repository/app/session_repository_impl_test.dart` (clear удаляет новые ключи).
- [X] T017 [P] Реализовать `lib/data/service/app_lifecycle_service_impl.dart` (`AppLifecycleListener` → `Stream<AppLifecycleState>`, dev/prod) и фейк для тестового окружения; тесты в `test/data/service/app_lifecycle_service_impl_test.dart`.
- [X] T018 Читать адреса сервера:
  - в `lib/data/remote/socket/nox_socket_client.dart`: разбирать `addresses` из ответа на приветствие в поток `ServerAddresses`, который очищается в `_teardown`, и отдавать наружу признак поддержки из приветствия (`supportsAccessKeys`);
  - в `lib/data/sync/sync_service.dart`: обрабатывать событие `server.addresses` с seq 0 рядом с `device.revoked`/`identity.updated` и сохранять адреса через `ServerAddressesRepository`, не трогая курсор.

  Переписать тесты совместимости с 039: группу 'a server from phase 039' в `test/data/remote/socket/nox_socket_client_test.dart` и тест `server.addresses` в `test/data/sync/sync_service_test.dart`. Теперь они проверяют, что адреса прочитаны и сохранены, а курсор по-прежнему не тронут.
- [X] T019 Научить сокет запрашивать цель перед каждой попыткой:
  - `NoxSocketClient.start` принимает `SocketTargetProvider` (асинхронный: следующий `Uri` или ничего);
  - `_openOnce` обращается к нему на каждой попытке;
  - добавить `connectTimeout` в `lib/data/remote/socket/socket_channel_factory.dart`: 45 с для `.onion`, 10 с для остальных;
  - отказ по пину относить к конкретному соединению, а не вычислять по приращению счётчика, общего на весь процесс.

  Тесты в `test/data/remote/socket/nox_socket_client_test.dart` с `FakeSocketFactory`: цель запрашивается на каждой попытке; нет цели → нарастающая пауза; отказ на onion → `serverMismatch`.
- [X] T020 Подключаться к onion-хостам через мост в `lib/data/remote/pinned_http_client.dart`:
  - хост, оканчивающийся на `.onion`, → `Socket.connect(127.0.0.1, bridgePort)` → записать 32-байтный секрет → `SecureSocket.secure(socket, host: onion, supportedProtocols: ['http/1.1'])` → существующая проверка листового сертификата `ServerPin.matches`;
  - порт и секрет моста берутся из внедрённого `TorBridgeEndpoint`, который читается в момент рукопожатия.

  Тесты в `test/data/remote/pinned_http_client_onion_test.dart` с подставным мостом на loopback перед честной и враждебной TLS-фикстурами: честная проходит, враждебная отвергается, при неверном секрете соединение закрывается.
- [X] T021 Привязать эпоху к отпечатку в `lib/data/sync/live_session_starter.dart`: `fp:<fingerprint>`. Сохранённую эпоху `live:` перенести без стирания (`lib/data/local/sync/sync_dao.dart`, если нужен помощник). Тесты в `test/data/sync/live_session_starter_test.dart`:
  - эпоха `live:` переносится, чаты остаются;
  - другой `fp:` — стирание;
  - тот же `fp:` ничего не меняет.
- [X] T022 Реализовать `lib/data/sync/connection/access_key_registrar.dart`:
  - `pair` всегда отправляет `access_key` (свой открытый ключ) — в `nox_socket_client.dart` `pair()` и в `lib/data/sync/live_identity_handshake.dart`;
  - после первого приветствия с `addresses`, пока ключ не зарегистрирован, → `device.setAccessKey`; успех → ключ зарегистрирован;
  - `invalid_request` → новый ключ, не больше 3 за сессию;
  - `unauthenticated` → существующий путь отзыва.

  Тесты в `test/data/sync/connection/access_key_registrar_test.dart` и в тесте рукопожатия.
- [X] T023 Реализовать `ConnectionStatusService`:
  - `lib/data/sync/connection/connection_status_service_impl.dart` (dev): фаза сокета плюс события селектора, путь, `torObsolete` из `tor.obsolete_client`; сглаживание офлайна по research, решение 12;
  - `lib/data/service/phase_connection_status_service.dart` (prod/test): из `SessionPhaseService`.

  Тесты в `test/data/sync/connection/connection_status_service_impl_test.dart`: сглаживание — первый неудачный раунд → офлайн, повторные попытки его сохраняют, успех снимает.

**Checkpoint**: `make gate` зелёный; для пользователя пока ничего не изменилось.

---

## Phase 4: User Story 1 — переписка вне дома (Priority: P1) 🎯 MVP

**Goal**: когда прямой путь не отвечает, приложение подключается через Tor, и переписка работает.

**Independent Test**: сценарий 2 из quickstart (`nox.forceTor=true`) на macOS: сообщения и файл идут через Tor.

- [X] T024 [P] [US1] Реализовать `lib/data/sync/connection/direct_prober.dart`:
  - собственный `PinnedHttpClient`, TLS + пин листового сертификата + `GET /health` для каждого кандидата;
  - 2,5 с на попытку; первый кандидат сразу, остальные через 300 мс параллельно; побеждает первый успех; бюджет 5 с;
  - отказ по пину помечает кандидата как «не дома» (FR-005).

  Тесты в `test/data/sync/connection/direct_prober_test.dart` с честным и враждебным TLS-серверами на loopback.
- [X] T025 [US1] Реализовать `lib/data/sync/connection/connection_path_selector.dart`:
  - прямые кандидаты через пробник, иначе Tor, если он доступен: платформа, onion известен, ключ зарегистрирован или есть ключ приглашения, эта сборка не признана устаревшей;
  - `TorService.start` + `setTarget(onion, 443, key)`, ждать готовности ≤ 90 с, выдать `wss://<onion>:443/ws`;
  - публиковать события пути для `ConnectionStatusService`;
  - ключ сборки `nox.forceTor`, действующий только в debug, пропускает прямых кандидатов (проверка `kDebugMode`).

  Тесты в `test/data/sync/connection/connection_path_selector_test.dart` с подставными пробником, Tor и часами:
  - побеждает прямой путь;
  - запасной путь через Tor;
  - нет onion → ничего;
  - Linux → только прямой путь;
  - сборка устарела → без Tor;
  - forceTor в release игнорируется.
- [X] T026 [US1] Встроить селектор в `lib/data/sync/live_session_starter.dart`:
  - запускать сокет с селектором в роли поставщика цели;
  - `ApiClient.initBase` следует за выбранным путём;
  - `TorBridgeEndpoint` получает данные от `TorService`.

  Тесты в `test/data/sync/live_session_starter_test.dart`: сокет получает onion-URL, когда прямой путь не отвечает; базовый URL для файлов следует за ним.
- [X] T027 [US1] Добиться, чтобы команды, отправленные во время подъёма пути, ждали, а не завершались ошибкой: очередь отправки разбирается, когда соединение становится живым, а интерактивные команды возвращают `connection` только после истечения бюджета подъёма (`lib/data/sync/outbox_service.dart` и путь отправки через сокет). Тест в `test/data/sync/outbox_service_test.dart`.

**Checkpoint**: US1 работает с `nox.forceTor` на macOS; сервер — локальный `noxd` с Tor.

---

## Phase 5: User Story 2 — дома напрямую, Tor выключен (Priority: P1)

**Goal**: возврат на прямой путь, как только он работает; Tor остановлен; ничего не потеряно.

**Independent Test**: сценарий 3 из quickstart; тесты селектора с подставными часами.

- [X] T028 [US2] Возвращаться на прямой путь в `connection_path_selector.dart`:
  - пока связь идёт через Tor: по `watchNetworkChanges` и каждые 2 мин проверять прямых кандидатов;
  - когда один из них отвечает: переключить на него сокет (после проверки пробником), затем `TorService.clearTarget` + `stop`, как только новое соединение живо (≤ 10 с).

  Тесты с подставными часами и подставными событиями сети:
  - переключение происходит;
  - Tor останавливается в пределах 10 с;
  - на враждебный прямой ответ переключения нет.
- [X] T029 [US2] На прямом пути смена сети запускает проверку текущего адреса; если он не отвечает — переподключение через селектор. Тест в том же файле.
- [X] T030 [US2] Фоновый режим (iOS/Android) через `AppLifecycleService`:
  - paused → `setDormant(true)`;
  - resumed → `setDormant(false)` и немедленное переподключение, если соединение не живо;
  - Tor-клиент не готов в пределах 10 с → stop + start из тех же каталогов.

  На десктопе это не действует. Тесты в `connection_path_selector_test.dart` с подставным жизненным циклом.
- [X] T031 [US2] Тест переключения без потерь в `test/data/sync/connection/lossless_switch_test.dart` (настоящие сокет, селектор, код применения журнала, очередь отправки и репозиторий сообщений поверх подставного сервера), прогон на 20 переключениях (SC-005): сообщение, отправленное во время каждого переключения, уходит один раз (идемпотентность очереди отправки + повтор журнала с `since`), а входящие события не дублируются (дубли отбрасываются по seq).

---

## Phase 6: User Story 3 — смена адреса ничего не стирает (Priority: P1)

**Goal**: новый адрес сервера становится известен (при необходимости через Tor), и прямой путь возобновляется по нему; история цела.

**Independent Test**: сценарий 8 из quickstart; сценарный тест селектора.

- [X] T032 [US3] Записывать `last_good` в `ServerAddressesRepository` при каждом успешном прямом соединении (`connection_path_selector.dart`). Порядок кандидатов: `last_good`, затем список сервера, затем адрес из ссылки. Тесты — в тестах репозитория и селектора.
- [X] T033 [US3] Сценарный тест в `test/data/sync/connection/connection_path_selector_test.dart`: старый адрес мёртв → Tor → `server.addresses` приносит новый прямой адрес → следующая проверка переключает на него; эпоха не меняется (отпечаток), поэтому стирания нет.

---

## Phase 7: User Story 4 — второе устройство из другой сети (Priority: P2)

**Goal**: по ссылкам версии 2 спаривание проходит из другой сети; приглашения запрашиваются с onion; приглашения «только дома» прямо об этом говорят.

**Independent Test**: сценарии 4–6 из quickstart.

- [X] T034 [P] [US4] Поддержать версию 2 в `lib/general/pairing/pairing_link.dart`: `onionPub`, `onionPort`, `oneTimePriv`; длины 122/134/119+N. Тесты в `test/general/pairing/pairing_link_test.dart`:
  - заменить 'a future version is refused' векторами v2, построенными так же, как на сервере (IPv4, IPv6, DNS);
  - версия 3 по-прежнему отвергается;
  - v1 не изменилась.
- [X] T035 [US4] Вход по ссылке v2 в `lib/data/repository/app/auth_repository_impl.dart` `signIn` и `lib/data/sync/live_identity_handshake.dart`:
  - одалживать селектору onion-адрес (выводится через `TorService.onionFromPublicKey`; там, где Tor не поддерживается, пропускается) и одноразовый ключ — только в памяти, `ConnectionPathSelector.lendInvite`; на диск они не пишутся (FR-021);
  - селектор использует ключ приглашения, если у устройства нет зарегистрированного ключа;
  - после ответа на `pair`, успешного или нет, забрать одолженное (`forgetLentKey`: ключ уходит из Tor-клиента, копия затирается) и переключить цель Tor на собственный ключ.

  Тесты в `test/data/repository/app/auth_repository_impl_test.dart` и в тесте рукопожатия.
- [X] T036 [US4] Запрашивать приглашения с onion:
  - `DeviceRepository.inviteDevice` возвращает `DeviceInvite` и отправляет `{"onion": true}` (`lib/domain/repository/device/device_repository.dart`, `lib/data/repository/device/device_repository_impl.dart`);
  - `DevicesBloc` и `DevicesState` несут `inviteHomeOnly` (`lib/presentation/pages/devices_page/bloc/`);
  - `AppInviteCardWidget` показывает `devicesInviteHomeOnly` для приглашения «только дома» (`lib/presentation/widgets/settings/app_invite_card_widget.dart`);
  - ARB EN/UK.

  Тесты: `device_repository_impl_test.dart`, `devices_bloc_test.dart`, `app_invite_card_widget_test.dart`. Голдены: виджет карточки приглашения с пометкой и без неё, а также страница устройств, мобильная и десктопная, с пометкой.
- [X] T037 [US4] Вход: если сервер ссылки v1 не отвечает или отвечает ключом, которого ссылка не называет, показывается `loginHomeNetworkOnly` (`lib/presentation/pages/login_page/bloc/login_bloc.dart`, `login_page.dart`, ARB EN/UK). Тесты в `test/presentation/pages/login_page/bloc/login_bloc_test.dart`.

---

## Phase 8: User Story 5 — ключ доступа живёт только на устройстве (Priority: P2)

**Goal**: ключ создаётся и хранится на устройстве, при отказе регистрируется заново, а при выходе стирается вместе со всем состоянием Tor.

**Independent Test**: тесты регистратора; тесты выхода; сценарий 7 из quickstart.

- [X] T038 [US5] Стирание при выходе в `lib/data/repository/app/auth_repository_impl.dart`: сразу после `LiveSessionStarter.stop` вызвать `TorService.stop()` и удалить каталоги состояния и кэша Tor. `clear()` уже покрывает ключи и адреса (T016). Тесты в `test/data/repository/app/auth_repository_impl_test.dart`: Tor остановлен, каталоги удалены, ключей нет (SC-007).
- [X] T039 [US5] Обработать ключ, которого сервис не знает: `wrong_client_auth` от моста, не прекращающийся 5 минут подряд, помечает ключ незарегистрированным (раньше — нет: только что принятый ключ появляется в описании сервиса с задержкой; серию обрывает любое приветствие и новый ключ), чтобы следующее прямое приветствие зарегистрировало его заново, а селектор до тех пор не повторяет попытки через Tor (`access_key_registrar.dart`, `connection_path_selector.dart`). Тесты в обоих тестовых файлах.

---

## Phase 9: User Story 6 — видно, каким путём идёт связь (Priority: P2)

**Goal**: показываются только отклонения — бейдж `Tor` и `Connecting…` — в углу на обеих ширинах, EN/UK. Баннер «No connection» сглажен; при устаревшем клиенте — просьба обновиться.

**Independent Test**: голдены и виджет-тесты индикатора; сценарии 2–3 из quickstart — визуально.

- [X] T040 [P] [US6] Добавить ключи из contracts/ui-states.md в `lib/l10n/app_en.arb` и `lib/l10n/app_uk.arb` (одинаковые наборы ключей), затем выполнить `make generate`.
- [X] T041 [US6] Реализовать индикатор:
  - `ConnectionIndicatorBloc` (Freezed, поверх `ConnectionStatusService`): `lib/presentation/widgets/state/connection_indicator/bloc/`;
  - `AppConnectionIndicatorWidget`: `lib/presentation/widgets/state/app_connection_indicator_widget.dart`, по contracts/ui-states.md:
    - состояния: ничего / `Tor` / `Connecting…` / `Connecting…` + `Tor`;
    - только токены;
    - подпись для экранного диктора; область касания 48×48;
    - нажатие → нижний лист на узкой ширине, диалог на широкой, с `connectionInfo*`; строка о локальной сети — только на iOS и macOS.

  Тесты:
  - виджет-тесты в `test/presentation/widgets/state/app_connection_indicator_widget_test.dart`, в том числе один в локали `uk` (SC-006);
  - блок-тест;
  - голдены виджета: четыре состояния, светлая и тёмная тема;
  - проверки доступности рядом с `test/presentation/widgets/accessibility_test.dart`.
- [X] T042 [US6] Разместить индикатор:
  - на узкой ширине: в верхней панели списка чатов перед аватаром аккаунта (`lib/presentation/pages/chats_list_page/chats_list_page.dart`) и в верхней панели переписки перед действием приглашения (`lib/presentation/pages/chat_thread_page/chat_thread_page.dart`);
  - на широкой ширине: необязательный `trailing` у `AppWindowTitlebarWidget` (`lib/presentation/widgets/shell/app_window_titlebar_widget.dart`), его заполняет `TabBarShell` (`lib/presentation/widgets/shell/tab_bar_shell_widget.dart`).

  Тесты в `app_window_titlebar_widget_test.dart` и в тесте оболочки. Голдены страниц:
  - 5.1 и 5.2, мобильные, с `online(tor)` и `connecting(tor)`;
  - оболочка, десктоп, с теми же двумя состояниями.
- [X] T043 [US6] Управлять баннерами через `ConnectionStatusService` вместо `!phase.isCurrent` в `ChatsListBloc`, `ChatThreadBloc` (сброс очереди отправки по-прежнему срабатывает на переходе «фаза стала текущей») и `ChatCardBloc`. Обновить их тесты и фейки. Баннер «No connection» показывается только при `offline`.
- [X] T044 [US6] Показывать `connectionTorObsolete` полосой-уведомлением на 5.1 (обе ширины) при `torObsolete`. Тесты и голдены: мобильный и десктопный.

**Checkpoint**: `make gate` и `make golden-verify` зелёные; все истории работают независимо.

---

## Phase 10: Polish & Cross-Cutting Concerns

- [X] T045 [P] Обновить блюпринты в `docs/blueprints/mobile/`:
  - `14-networking-and-auth.md`: выбор пути, транспорт Tor, мост, жизненный цикл, смены сети;
  - `04-data-layer.md`: подключение к onion в §7а о пиннинге;
  - `02-dependency-injection.md`: новые регистрации и разделение по окружениям;
  - `01-stack-and-tooling.md`: тулчейн Rust, native assets, пакет в workspace;
  - `09-build-and-secrets-infra.md`: Rust как условие сборки, NDK, rustup для compile-check в CI.
- [X] T046 [P] Обновить дизайн-документы:
  - `docs/design/spec/` (5.1, 5.2, приглашение устройства, заголовок окна оболочки; таблица решений);
  - `docs/design/system/nox-mobile-screens/screens/5-1-chats.md`, `5-2-thread.md`, `7-8-devices.md`;
  - `docs/design/system/nox-desktop-screens/screens/01-chats.md`, `09-devices.md`.

  Содержание: состояния и размещение индикатора, пометка «только дома» на приглашении, полоса об устаревшем Tor-клиенте.
- [X] T047 [P] Обновить `CLAUDE.md` (заметки о реализации: транспорт Tor, выбор пути, эпоха по отпечатку, ключ доступа, условия сборки) и `docs/client-backend/roadmap-tor.md` (статус этапа 2).
- [X] T048 Прогнать сквозные сценарии quickstart на macOS, симуляторе iOS и эмуляторе Android; сервер — локальный `noxd` с Tor. Записать время подъёма и память в `research.md`, «Замер», и отметить все расхождения.
- [X] T049 Прогнать гейты: `make gate`, `make golden-verify`, `make tor-test`. Гейт Go не затрагивается: изменений в Go нет.
- [X] T050 Не допускать onion-адрес и ключи в логи (FR-013, SC-008, конституция, Принцип I):
  - Проверить каждый вызов `logRepository` в `lib/data/remote/socket/`, `lib/data/remote/pinned_http_client.dart`, `lib/data/sync/connection/` и `lib/data/service/tor/`.
  - Хосты, оканчивающиеся на `.onion`, пишутся в лог как `[onion]`; ключи и секреты не пишутся никогда.
  - Тест в `test/data/sync/connection/log_redaction_test.dart`: перехватить вывод `LogRepository` при прогоне селектора с Tor, спаривании по ссылке v2 и сбое моста; убедиться, что в нём нет `.onion` и ключевого материала в base64.
- [X] T051 [P] Подготовить CI к нативному пакету — на тот момент, когда приостановленные workflow снова включат:
  - `.github/workflows/compile-check.yml`: установить rustup с тулчейном из `packages/nox_tor/rust/rust-toolchain.toml`; для Android — ещё и NDK 28.2 до сборки. Заданию для Linux ничего не нужно.
  - `.github/workflows/ci.yml`: заданию гейта на macOS тоже нужен rustup, потому что `flutter test` запускает хук.
- [X] T052 Перенести в описание PR проверки владельца на устройствах (quickstart, «Проверки на устройстве»): запрос доступа к локальной сети и фоновый режим на iOS, мобильная сеть вне дома, сборка и подъём Tor на Windows.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (1)** — без зависимостей.
- **US7 Замер (2)** — после Setup. **Запирает всё последующее** (+25 МБ).
- **Foundational (3)** — после гейта. Блокирует все истории.
- **US1 (4)** — после Foundational. US2 и US3 строятся на селекторе из US1.
- **US2 (5), US3 (6)** — после US1; друг от друга не зависят.
- **US4 (7), US5 (8)** — после Foundational и US1 (используют селектор); друг от друга не зависят.
- **US6 (9)** — после Foundational (`ConnectionStatusService`); может идти параллельно с US2–US5.
- **Polish (10)** — после историй.

### Within Each User Story

Тесты идут вместе с каждой задачей, в том же изменении. Модели — раньше сервисов, сервисы — раньше UI. Гейты (`make gate` + `make golden-verify`) прогоняются перед каждым коммитом, который затрагивает Dart.

### Parallel Opportunities

- T004 и T005 в Setup.
- T008 в Phase 2 — рядом с T006 и T007, файлы разные.
- T013, T014 и T017 в Foundational.
- T024 в US1 (независимый файл).
- T034 в US4.
- T040 в US6.
- T045, T046, T047 и T051 в Polish.

## Parallel Example: User Story 6

```text
Task: "T040 Добавить ключи соединения в app_en.arb и app_uk.arb"
Task (после T040): "T041 Реализовать ConnectionIndicatorBloc и AppConnectionIndicatorWidget"
Task (после T041): "T042 Разместить индикатор в списке чатов, в переписке и в заголовке окна"
Task (независимо от T041): "T043 Управлять баннерами через ConnectionStatusService"
```

## Implementation Strategy

### MVP First

Setup → гейт замера → Foundational → US1. Это даёт переписку через Tor вне дома с `nox.forceTor` на macOS.

### Incremental Delivery

1. US2 + US3: путь возвращается домой, а адреса меняются безопасно.
2. US4 + US5: спаривание из другой сети; жизненный цикл ключа.
3. US6: видимое состояние связи.
4. Polish: документы, сквозные прогоны и проверки владельца на устройствах.

Каждая фаза заканчивается зелёными гейтами и собственным коммитом.

## Notes

- Windows с этой машины не собирается: `cargo check` для MSVC падает на заголовках C. Проверка Windows — в T052, за владельцем.
- Проверки, возможные только на устройстве (фоновый режим iOS, запрос доступа к локальной сети, настоящая мобильная сеть), перечислены для владельца в T052.
- Коммит — после каждой фазы. С красными гейтами не коммитить никогда.

## Phase 11: Convergence

- [X] T053 Сократить время подключения через Tor: если onion-соединение не открылось примерно за 15 с, запускать второй набор параллельно и брать первый открывшийся; поднимать Tor одновременно с проверкой прямых адресов, когда прошлое соединение шло через Tor; после спаривания не ждать 20 с приветствия по только что зарегистрированному ключу (`lib/data/remote/socket/nox_socket_client.dart`, `lib/data/sync/connection/connection_path_selector.dart`, `lib/data/sync/live_identity_handshake.dart`); замерить зондами до и после per SC-001 (partial)
- [ ] T054 Замерить на телефонах iOS и Android по мобильной сети вне дома: первый запуск Tor-клиента — не дольше 60 с в 9 попытках из 10, повторные — не дольше 30 с; числа записать в `research.md`, раздел «Замер» per SC-001 (partial)
- [ ] T055 *(перенесена после слияния PR #28 — решение владельца 2026-10-04: проверки на Windows отдельной задачей)* Собрать приложение на Windows (`fvm flutter build windows --debug`), замерить модуль (прибавка к размеру, первый и повторный подъём, память), проверить, что подъём не зависает на 15 % (Arti #2726), и прогнать сценарии 1–3 из `quickstart.md`; числа записать в `research.md` per FR-031, FR-034, SC-009 (partial)
- [ ] T056 Проверить на iPhone и на macOS 15+: запрос доступа к локальной сети с текстом `NSLocalNetworkUsageDescription`, прямой путь дома после разрешения, путь через Tor и подсказку о доступе при отказе per FR-032 (partial)
- [ ] T057 Проверить на iPhone возврат из фона: дома связь восстанавливается не дольше 5 с, вне дома — не дольше 30 с; отдельно вне дома после 10+ минут в фоне, когда iOS забирает сокет моста и мост получает новый per SC-010 (partial)
- [X] T058 Расширить сквозной зонд `test/live/tor_live_probe.dart`: отправить и получить вложение через Tor — загрузка и скачивание байтов через мост с проверкой отпечатка per US1/AC2, FR-009 (partial)
- [X] T059 Привести `plan.md` к коду: одноразовый ключ ссылки v2 хранится только в памяти, а не в `flutter_secure_storage`; в зависимостях крейта — ещё `tor-rtcompat`, `futures`, `subtle`, `getrandom` и `zeroize` per plan: storage decision (contradicts)
- [X] T060 Через `/speckit-clarify` уточнить краевой случай «Отозванное устройство»: вне дома отзыв неотличим от ключа, который ещё не разошёлся по сети, — Tor перестаёт пробоваться после 5 минут отказов, а выход случается при первом прямом приветствии дома per Edge Cases: отозванное устройство (partial)
