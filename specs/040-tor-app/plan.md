# Implementation Plan: приложение через Tor — дома напрямую, вне дома через встроенный Tor

**Branch**: `040-tor-app` | **Date**: 2026-10-03 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/040-tor-app/spec.md`

## Summary

Приложение учится ходить к своему серверу двумя путями и выбирает их само.

**Tor-клиент**:
- свой Rust-модуль на Arti 0.47.0 в пакете `packages/nox_tor`;
- собирается build-хуком native assets, мост — C ABI и `@Native`;
- поднимается, только когда прямой путь не ответил;
- держит ключ доступа к onion в памяти и отдаёт приложению локальный порт с секретом.

Через этот порт `PinnedHttpClient` строит TLS к onion-имени, поэтому проверка отпечатка остаётся той же, что на прямом пути.

**Выбор пути** (`ConnectionPathSelector`):
- сокет спрашивает его перед каждой попыткой;
- сначала проверяются прямые кандидаты — до 5 с, с проверкой отпечатка;
- затем Tor — подъём до 90 с, соединение до 45 с;
- из Tor есть возврат на прямой путь при смене сети и раз в 2 минуты.

**Хранение**:
- адреса сервера — из приветствия и события `server.addresses`;
- эпоха данных — по отпечатку, с миграцией без стирания;
- ключ доступа — в защищённом хранилище, регистрируется на сервере.

**Спаривание**: ссылка версии 2 и приглашение с onion.

**Интерфейс**:
- угол показывает только отклонения: бейдж `Tor`, `Connecting…`;
- баннер «No connection» сглажен;
- при устаревшем клиенте — просьба обновиться.

**Платформы**: iOS, Android, macOS, Windows; Linux — только прямой путь. Контракт и сервер не меняются.

Ход реализации: сначала замер модуля (FR-034, порог +25 МБ), затем встраивание.

## Technical Context

- **Language/Version**:
  - Dart 3.12 / Flutter 3.44.1 (FVM);
  - Rust 1.93.1, закреплённый `rust-toolchain.toml` пакета `nox_tor`.
- **Primary Dependencies**:
  - Rust: `arti-client =0.47.0`, `tor-hscrypto`, `tor-llcrypto`, `tor-keymgr`, `tor-config`, `tor-rtcompat` той же версии, `tokio`, `rustls` (ring), `futures`, `tracing`, `tracing-subscriber`, `sha3`, `data-encoding`, `subtle`, `getrandom`, `zeroize`.
  - Dart: `native_toolchain_rust 1.0.4+0`, `hooks`, `code_assets`, `ffi`, `cryptography` (уже есть, X25519).
  - Остальное — нынешний стек по блюпринту.
- **Storage**:
  - `flutter_secure_storage`: адреса, ключ доступа, признак регистрации;
  - одноразовый ключ ссылки v2 — только в памяти, на время одного спаривания (FR-021);
  - `SharedPreferences`: признак устаревшего клиента;
  - каталоги Tor: состояние — в поддержке приложения, кэш (~45 МБ) — в кэше платформы;
  - эпоха — в нынешнем `SyncDao`.
- **Testing**:
  - `flutter test` — модульные, блок- и виджет-тесты на DI-фейках;
  - голдены обеих ширин, светлая и тёмная тема;
  - `cargo test` в `packages/nox_tor/rust`; `dart test` — хук пакета;
  - сквозные сценарии — по `quickstart.md`, вне гейта.
- **Target Platform**: iOS 13+, Android API 24+, macOS 10.15+, Windows 10+; Linux — без Tor.
- **Project Type**: мобильное и десктопное приложение (один пакет `nox_app`) плюс локальный нативный пакет `packages/nox_tor`.
- **Performance Goals**: из спецификации.
  - SC-001: вне дома до 60 с при первом подъёме и до 30 с при повторном.
  - SC-002: Tor остановлен через 10 с после того, как заработал прямой путь.
  - SC-006: состояние в углу меняется за 2 с.
  - SC-010: возврат из фона.
- **Constraints**:
  - не больше 25 МБ к размеру загрузки на платформу;
  - Tor-клиент работает, только пока нужен;
  - onion-адрес и ключи — не в логах;
  - модуль не становится зависимостью будущего расширения уведомлений iOS.
- **Scale/Scope**:
  - Rust-крейт на 6–8 модулей;
  - 12 новых строк ARB в каждом языке;
  - около 25 файлов Dart;
  - 3 блока с баннером переводятся на новую службу;
  - 4 нативных файла платформ.

## Constitution Check

*GATE: проверено перед исследованием и заново после дизайна.*

| Принцип | Вывод |
|---|---|
| I. Приватность | ✅ Ключ доступа — только в защищённом хранилище и в памяти Arti, одноразовый ключ — только в памяти приложения и Arti; на диск Tor-клиента не ложатся. Onion-адрес не показывается и не логируется. Выход стирает ключи, адреса и каталоги Tor. Мост защищён секретом от других приложений устройства. |
| II. Спека и дизайн-корпус | ✅ Новое состояние в углу и пометка приглашения вносятся в `docs/design/spec/` и в оба корпуса экранов (5.1, 5.2, оболочка; desktop — заголовок окна) в той же фазе. Вне объёма ничего не добавлено. |
| III. Блюпринт | ✅ Слои соблюдены: интерфейсы в `domain`, реализации в `data`, блоки Freezed, DI injectable, `RepositoryResult`, `LogRepository`. Новая подсистема — нативный Tor-транспорт, путь, жизненный цикл — вписывается в блюпринты 14, 04, 02, 01 и 09 в той же фазе. Desktop-путь не отдельный fallback, а тот же код. |
| IV. Дизайн-система | ✅ Бейдж и текст — только токены и `ColorScheme` ([ui-states.md](./contracts/ui-states.md)). |
| V. Язык | ✅ Документы — русский; код, коммиты и микрокопия — английский; UI — EN и UK. |
| VI. Паритет | ✅ Индикатор на обеих ширинах; голдены mobile и desktop; Tor на четырёх платформах. Linux — намеренное расхождение, записанное в спеке (этап `tor-linux-app`). |
| VII. Контракт | ✅ Провод не меняется ([wire-usage.md](./contracts/wire-usage.md)). Приложение использует только описанное в контракте с 039. |

Технологический контекст конституции уже называет Rust языком клиентского криптоядра. Модуль Tor — отдельный крейт, не криптоядро (FR-033).

## Project Structure

### Documentation (this feature)

```text
specs/040-tor-app/
├── spec.md
├── plan.md              # this file
├── research.md          # decisions 1–14 + "Замер"
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── ffi.md           # Dart ↔ Rust bridge
│   ├── ui-states.md     # connection state, Tor badge, copy
│   └── wire-usage.md    # contract v0 usage (no changes)
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
packages/nox_tor/                         # new: workspace member
├── pubspec.yaml                          # resolution: workspace
├── hook/build.dart                       # RustBuilder; Linux → no assets; Android NDK API; deps on Cargo files
├── lib/nox_tor.dart                      # NoxTor wrapper
├── lib/src/nox_tor_bindings.dart         # @Native externals
├── test/hook_test.dart
└── rust/
    ├── Cargo.toml, Cargo.lock, rust-toolchain.toml
    └── src/lib.rs, engine.rs, bridge.rs, status.rs, obsolete.rs, onion.rs

lib/
├── domain/model/connection/              # ServerAddresses, ConnectionPath, ConnectionStatus, TorStatus
├── domain/model/device/device_invite.dart
├── domain/repository/connection/         # ServerAddressesRepository, AccessKeyRepository
├── domain/service/                       # tor_service.dart, connection_status_service.dart, app_lifecycle_service.dart
├── data/service/tor/                     # native_tor_service.dart (dev/prod), fake_tor_service.dart (test), tor_capability.dart
├── data/service/app_lifecycle_service_impl.dart
├── data/repository/connection/           # *_impl.dart over secure storage
├── data/sync/connection/                 # connection_path_selector.dart, direct_prober.dart,
│                                         # access_key_registrar.dart, connection_status_service_impl.dart
├── data/remote/pinned_http_client.dart   # onion dial through the bridge
├── data/remote/socket/                   # target provider, addresses, server.addresses, connect timeout
├── data/sync/live_session_starter.dart   # epoch fp:, migration, path selection
├── data/repository/app/                  # sessions (new keys in clear/discardSignIn), logout (Tor wipe)
├── general/pairing/pairing_link.dart     # version 2
├── presentation/widgets/state/app_connection_indicator_widget.dart (+ bloc/)
├── presentation/pages/chats_list_page/, chat_thread_page/, chat_card_page/  # banners from the new service; indicator
├── presentation/widgets/shell/           # titlebar trailing, TabBarShell
├── presentation/pages/devices_page/      # "home network only" note
└── l10n/app_en.arb, app_uk.arb           # +12 keys

ios/Runner/Info.plist, macos/Runner/Info.plist          # NSLocalNetworkUsageDescription
macos/Runner/Release.entitlements                        # network.server
android/app/src/main/AndroidManifest.xml                 # INTERNET explicitly
Makefile                                                 # format includes packages/nox_tor; tor-test

docs/blueprints/mobile/{01,02,04,09,14}*.md, docs/design/spec/ + both screen corpora, CLAUDE.md,
docs/client-backend/roadmap-tor.md
```

**Structure Decision**: один пакет приложения `nox_app` по блюпринту плюс локальный пакет `packages/nox_tor`, участник workspace. Он нужен потому, что build-хук принадлежит пакету, а Rust-сборке нужна своя граница. Это не второй пакет приложения: в нём нет ни экранов, ни логики продукта, только мост к Tor-клиенту.

## Complexity Tracking

| Отступление | Зачем | Почему не проще |
|---|---|---|
| Второй язык и тулчейн в клиенте — Rust 1.93.1 | Tor-клиент с ключами доступа к onion есть только в Arti (решение владельца №9); конституция уже называет Rust языком клиентского ядра | Готовый Flutter-плагин не умеет ключи доступа; C tor — другой язык и своя сборка под четыре платформы |
| Локальный пакет `packages/nox_tor` в workspace | Build-хук живёт в пакете; Rust-сборка изолирована от `nox_app` | Хук в самом `nox_app` смешал бы сборку нативного кода с приложением, а Linux-ветку было бы сложнее держать пустой |
| `flutter test` компилирует крейт (холодный прогон около 2,5 мин, тёплый около 2 с) | Так работают хуки native assets — для хоста при каждом тесте | `flutter_rust_bridge` этого избегает, но падает на Gradle 9.1 и тащит хрупкую обвязку платформ |
| Debug-ключ `nox.forceTor` | Проверить путь через Tor на машине, где сервер достижим напрямую | Без него Tor-путь проверяется только на реальном устройстве вне дома; в release ключ не действует |
| Перехват выхода Arti — слой `tracing` и остановка runtime | Arti вызывает `std::process::exit(1)`, когда сеть объявляет протоколы обязательными, — это убило бы приложение | Отключить нельзя с Arti 2.4.0 (#1932); форк Arti дороже |
