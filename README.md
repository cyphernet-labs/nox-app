# NOX

**NOX** — защищённый кроссплатформенный мессенджер на Flutter (Dart); ориентир — Signal.
У каждого человека свой клиентский сервер: он принадлежит ровно одному человеку и
обслуживает только его устройства, а все чаты человека видны на всех его устройствах и
больше нигде. Общение между разными людьми пойдёт через релей, протокол которого ещё не
спроектирован (Q13); граница сквозного шифрования — открытый вопрос Q1. Оба вопроса — в
реестре `docs/client-backend/open-questions.md`.

## Из чего состоит

- **Приложение** — `lib/`, один Dart-пакет `nox_app`, Clean Architecture по блюпринту
  `docs/blueprints/mobile/`. Данные живут в локальной базе Sembast (сначала кэш, потом
  сервер), исходящие сообщения и новые чаты ждут в очереди, которая переживает перезапуск.
  Локальная база и файлы на устройстве зашифрованы ключом из системного сейфа и в системные
  бэкапы не попадают.
- **Rust-модуль канала** — `packages/nox_tor`: каждое соединение приложения с клиентским
  сервером — TCP или поток Tor через встроенный клиент Arti, затем TLS 1.3 и проверка
  `POST /auth` → `POST /auth2`. Через Tor приложение идёт, только если человек включил
  `Use Tor`.
- **RustSecureBox** — `packages/rust_secure_box`: ключи и подписи проверки, одна библиотека
  у приложения и у сервера. Сейчас внутри заглушка — `packages/rust_secure_box/README.md`.
- **Клиентский сервер** — `client_backend/` (`noxd`): Go со встроенной SQLite, один
  статический бинарник; команды идут по `wss`, байты файлов — по `https`. База и вложения
  сервера зашифрованы, и после каждого запуска сервер заперт до пароля владельца.
  Onion-сервис публикует отдельная служба tor. Подробно — `client_backend/README.md`,
  установка на машину — `deploy/README.md`.
- **Контракт провода v0** — `docs/client-backend/protocol/contract-draft.md`: каждая команда,
  событие, поле и код ошибки обеих сторон.

Срез `Item` (`AppShell`/`ItemListPage` из фичи 001) не смонтирован и служит только проверкой
того, что слоистый вертикальный срез работает от экрана до данных.

## Целевые платформы

iOS · Android · macOS · Windows · Linux. **Web вне области применения.**

## Инструментарий

- Flutter `3.44.1`, зафиксирован через [FVM](https://fvm.app) (`.fvmrc`) — запускайте каждую
  команду через `fvm`.
- Rust: сборочный хук `packages/nox_tor` собирает Rust-модуль при каждой сборке и при каждом
  `flutter test`, на всех платформах. Нужен `rustup` с тулчейном из
  `packages/nox_tor/rust/rust-toolchain.toml` (`1.93.1`, все цели); для Android — ещё и NDK.
  На новой машине один раз выполните `rustup show active-toolchain` в
  `packages/nox_tor/rust`: два первых запуска хука, скачивая тулчейн одновременно, мешают
  друг другу.
- Go той версии, что в `client_backend/go.mod`, — для клиентского сервера.
- Один Dart-пакет `nox_app`, единый app id `com.cyphernetlabs.noxapp` на всех пяти платформах;
  флейвор — только compile-time define `--dart-define-from-file=config/<flavor>.json`,
  отдельных нативных id и подписи нет.
- Codegen в первую очередь: Freezed + json_serializable + injectable + flutter_gen (один
  прогон `build_runner`), локализация — `flutter gen-l10n`.

## Настройка

```bash
fvm install           # the pinned SDK
fvm flutter pub get
make generate         # build_runner, then gen-l10n
```

## Гейт кода

```bash
make gate             # generate → format → analyze → test (without golden and live tests)
make golden-verify    # goldens: locally, on Apple Silicon / macOS
make tor-test         # RustSecureBox and the channel module: cargo tests, the server's copy check, Dart tests
```

…или пошагово:

```bash
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter gen-l10n
fvm dart format -l 140 lib test packages/nox_tor/lib packages/nox_tor/test packages/nox_tor/hook
fvm flutter analyze                                   # zero-errors gate
fvm flutter test --exclude-tags "golden || live"
```

Клиентский сервер:

```bash
cd client_backend
gofmt -l .            # must print nothing
go vet ./...
go test -race ./...
```

## Запуск / сборка

Флейворы `stage` и `prod` задаются на этапе компиляции из `config/<flavor>.json` через
`--dart-define-from-file`, одинаково на всех пяти платформах. На `stage` приложение работает
с живым клиентским сервером: адрес и ключ сервера приходят ссылкой спаривания. На `prod` — с
моками поверх локальной базы. Сборка без define получает `prod`.

```bash
# mobile (iOS / Android)
fvm flutter run --dart-define-from-file=config/stage.json

# desktop (macOS / Windows / Linux)
fvm flutter run -d macos   --dart-define-from-file=config/stage.json
fvm flutter run -d windows --dart-define-from-file=config/stage.json
fvm flutter run -d linux   --dart-define-from-file=config/stage.json
```

Отладочные сборки — `mise run build:<android|ios|macos|windows|linux>:<stage|prod>`.

## Дополнительно

- Карта документации — `docs/README.md`
- Архитектурный блюпринт приложения — `docs/blueprints/mobile/` (индекс в его `README.md`)
- Техника NOX и модель угроз — NOX Architecture (ссылка — в `docs/artifacts.md`); темы и их
  статусы — трекер `docs/client-backend/roadmap-security.md`
- Руководство для контрибьюторов и агентов — `CLAUDE.md`, для сервера — `client_backend/CLAUDE.md`
