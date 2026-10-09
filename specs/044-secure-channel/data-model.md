# Data Model: Защищённый канал

## Сервер

### `server_identity` (SQLite, `001_init.sql` правится на месте)

| Колонка | Было | Стало |
|---|---|---|
| `public_key` | base64 SPKI ключа ECDSA P-256 | base64 открытого ключа Ed25519 (32 байта) |
| `private_key` | base64 PKCS#8 ECDSA | base64 семени Ed25519 (32 байта) |
| `onion_seed` | без изменений (до 045) | — |

- Создаётся при первом старте, если людей нет; при людях без ключа — отказ старта (как сегодня).
- Технический сертификат TLS не хранится: собирается при каждом старте из одноразового ключа ECDSA P-256.

### Итог проверки на соединении (`internal/server`)

`channelPeer { key ed25519.PublicKey }` — несёт обёртка соединения; `ConnContext` кладёт его в контекст запроса. Обработчики ищут устройство по `key` (`devices.device_key` — тот же base64 открытого ключа, что и сегодня).

| Состояние | `/ws` | `/files` |
|---|---|---|
| ключ спаренного устройства | все команды после `session.hello` | с действующим токеном |
| незнакомый ключ | только `pair`; `session.hello` → `unauthenticated` | 401 |

## Приложение

### Хранилище сессии (`flutter_secure_storage`)

| Ключ | Было | Стало |
|---|---|---|
| `session.device_secret` | семя Ed25519 устройства | без изменений: семя передаётся модулю при каждом открытии канала |
| `session.server_fingerprint` | sha256 SPKI P-256 | **уходит** |
| `session.server_key` | — | **новый**: base64 открытого ключа сервера Ed25519 из ссылки |
| `session.server_address` | адрес из ссылки | без изменений |
| `session.server_addresses` | JSON адресов | без изменений (onion — по ключу сервиса, как сегодня) |

- Сессия без `session.server_key` при запуске считается старой: стирание и возврат к спариванию (FR-025).
- Эпоха мира — `key:<base64 ключа сервера>` вместо `fp:<отпечаток>`; старая эпоха `fp:` — смена мира (миграций нет).

### `PairingLink` (`lib/general/pairing/pairing_link.dart`)

| Поле | Тип |
|---|---|
| `version` | `int` (3) |
| `serverKey` | `Uint8List` (32) |
| `token` | `Uint8List` (16) |
| `addresses` | `List<LinkAddress>` — `ipv4`/`ipv6`/`name` (`host`, `port`) и `onion` (`servicePublicKey`, порт 443) |

Отказы разбора: `malformed`, `newerVersion` (ссылка новее приложения).

### Отказы канала (`ChannelFailure`)

`network`, `timeout`, `tls`, `protocol`, `wrongServer`, `torNotReady`, `torOnionInvalid`, `torOnionNotFound`, `torOnionUnreachable`, `torClientAuth`, `internal` — по контракту `ffi-channel.md`.

| Отказ | Прямой путь | Путь через Tor |
|---|---|---|
| `wrongServer` | адрес не мой → следующий путь молча | `serverMismatch`: сообщение «onion-адрес ведёт к другому серверу», попытки по нему стоп до смены адреса или `Try again` |
| `protocol`, `tls`, `network`, `timeout` | неудачная попытка, лестница повторов | то же |
| `tor*` | — | как сегодня в 040 |

### Сообщение проверки (оба конца)

`pk` (32) ‖ `sig(pk)` (64) ‖ `sig(B)` (64); `B` — экспортёр TLS 1.3 (RFC 9266). Векторы — `contracts/eidolon-vectors.json`.
