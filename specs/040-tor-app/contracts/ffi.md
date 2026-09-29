# Контракт моста Dart ↔ Rust: `packages/nox_tor`

Единственная граница между приложением и Tor-клиентом. C ABI, вызовы из Dart через `@Native` (asset id `package:nox_tor/src/nox_tor_bindings.dart`).

Правила для всех функций:
- **Не блокируют.** Вся работа идёт на tokio-runtime модуля в его собственном потоке. Функции только ставят задачу или читают снимок под коротким замком.
- **Безопасны из любого потока.**
- **Строки** — UTF-8 с нулём на конце.
- **Коды возврата**: `0` — успех; отрицательное значение — код из таблицы ниже, никогда не текст.
- **Ничего не логируют** с onion-адресом или ключом. Свои записи `tracing` модуль не выводит наружу.

## Функции

```c
// Starts the client from these directories: state persistent, cache rebuildable.
// Idempotent: a second call while running returns 0 and changes nothing.
int32_t nox_tor_start(const char *state_dir, const char *cache_dir);

// Stops everything: runtime, bridge, keys in memory. Idempotent.
// The directories stay; deleting them on logout is the app's job.
void nox_tor_stop(void);

// Sets the one target: onion host "<56 chars>.onion", port, and the 32-byte
// x25519 private key for client authorization. Replaces the previous target and
// key (remove + insert). Opens the bridge if it is not open; a new secret
// comes with it.
int32_t nox_tor_set_target(const char *onion_host, uint16_t port, const uint8_t *client_key32);

// Removes the target and its key; closes the bridge.
int32_t nox_tor_clear_target(void);

// true: DormantMode::Soft (app in background); false: Normal.
void nox_tor_set_dormant(bool dormant);

// Snapshot of the state (see the structure below).
int32_t nox_tor_status(NoxTorStatus *out);

// The current bridge secret: 32 bytes, valid until the next set_target/stop.
int32_t nox_tor_bridge_secret(uint8_t *out32);

// Onion address from a v3 public key (rend-spec-v3, SHA3-256): writes
// "<56>.onion\0" into out; out_len >= 63.
int32_t nox_tor_onion_from_pubkey(const uint8_t *pub32, char *out, size_t out_len);

// Version string, e.g. "arti 2.7.0"; static, must not be freed.
const char *nox_tor_version(void);

typedef struct {
  uint8_t  state;              // NoxTorState
  uint8_t  bootstrap_percent;  // 0..100
  uint8_t  error;              // NoxTorError of the most recent failure
  uint8_t  reserved;
  uint16_t port;               // bridge port on 127.0.0.1; 0 when there is no target
  uint16_t reserved2;
} NoxTorStatus;
```

## Коды

| `NoxTorState` | Значение |
|---|---|
| 0 | `stopped` |
| 1 | `bootstrapping` |
| 2 | `ready` |
| 3 | `dormant` |
| 4 | `failed` — повтор возможен |
| 5 | `obsolete` — сеть не принимает эту версию клиента; runtime остановлен, повтор бесполезен |

| `NoxTorError` / код возврата | Значение |
|---|---|
| 0 | нет |
| 1 / −1 | `missing_client_auth` — у цели нет ключа |
| 2 / −2 | `wrong_client_auth` — сервис не знает этот ключ: не зарегистрирован или устройство отозвано |
| 3 / −3 | `timeout` — подъём или соединение не уложились в бюджет |
| 4 / −4 | `network` |
| 5 / −5 | `internal` |
| 6 / −6 | `software_deprecated` — то же, что состояние `obsolete` |
| — / −7 | `invalid_argument` — неверная длина ключа, не onion-адрес, `out_len` мал |
| — / −8 | `not_started` |

## Мост байтов

Пока есть цель, модуль слушает `127.0.0.1:<port>`.

На каждое принятое соединение:
1. Прочитать ровно 32 байта за 5 с. Если они не равны секрету (сравнение за постоянное время), закрыть.
2. `TorClient::connect((onion_host, port))` с таймаутом 45 с. Отказ закрывает соединение и записывает `error` в снимок.
3. `copy_bidirectional` до закрытия любой стороны.

Других целей нет: адрес соединения задаёт только `set_target`.

## Защита от выхода Arti

Слой `tracing` модуля следит за событиями с целью `arti_client::protostatus` уровня WARN и выше. Такое событие:
1. ставит `state = obsolete`;
2. сворачивает runtime из управляющего потока (`shutdown_background`) до пятисекундного сна, после которого Arti вызвал бы `std::process::exit(1)`.

Запуск, который отказал с `ErrorKind::SoftwareDeprecated`, тоже даёт `obsolete`.

## Dart-обёртка (`package:nox_tor/nox_tor.dart`)

```dart
abstract final class NoxTor {
  static bool get isSupported;          // false on Linux and where the library is absent
  static void start({required String stateDir, required String cacheDir});
  static void stop();
  static void setTarget({required String onionHost, required int port, required Uint8List clientKey});
  static void clearTarget();
  static void setDormant(bool dormant);
  static NoxTorSnapshot status();
  static Uint8List bridgeSecret();
  static String onionFromPublicKey(Uint8List pub32);
  static String get version;
}
```

Приложение ходит к ней только через доменную службу `TorService` (`lib/domain/service/tor_service.dart`). Окружения `dev` и `prod` получают реализацию на `NoxTor`, окружение `test` — фейк. Виджетные и блок-тесты библиотеку не загружают.
