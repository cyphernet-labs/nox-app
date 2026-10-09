# Контракт: C ABI канала (`packages/nox_tor`, модуль `channel`)

Дополняет контракт Tor `specs/040-tor-app/contracts/ffi.md`. Ни одна функция не блокирует; паника не пересекает границу (`catch_unwind`, код `internal`). Строки — UTF-8 с нулём на конце.

## Функции

```c
typedef void (*nox_chan_event_fn)(int64_t handle, int32_t kind, const uint8_t *data, uintptr_t len, int32_t code);

// Открывает канал. Возвращает дескриптор > 0 сразу или отрицательный код; итог — событием.
// target_kind: 0 — прямой (host — IP или имя, port), 1 — onion (host — "<56>.onion", port — 443).
// device_seed32 — семя Ed25519 устройства; server_key32 — ожидаемый ключ сервера.
// connect_timeout_ms — срок на транспорт + TLS + Eidolon.
int64_t nox_chan_open(int32_t target_kind, const char *host, uint16_t port,
                      const uint8_t *device_seed32, const uint8_t *server_key32,
                      uint32_t connect_timeout_ms, nox_chan_event_fn on_event);

// Ставит байты в очередь отправки (модуль копирует их). Возвращает размер очереди после записи
// или отрицательный код (канал закрыт, неверные аргументы).
int64_t nox_chan_write(int64_t handle, const uint8_t *data, uintptr_t len);

// Подтверждает, что Dart доставил столько входящих байтов получателю: модуль снова читает.
int32_t nox_chan_ack(int64_t handle, uintptr_t len);

// Закрывает отправку (TLS close_notify после очереди); чтение идёт до конца.
int32_t nox_chan_shutdown_write(int64_t handle);

// Рвёт канал сразу; после события CLOSED дескриптор недействителен.
int32_t nox_chan_close(int64_t handle);

// Освобождает буфер события DATA.
void nox_chan_buf_free(uint8_t *data, uintptr_t len);
```

`nox_chan_event_fn` создаётся в Dart через `NativeCallable.listener` и вызывается из потоков модуля; исполняется в цикле событий изолята.

**Onion (до 045).** Канал к onion идёт через клиента Arti, которого поднимает `nox_tor_start`. Ключ доступа к onion-сервису регистрирует, как и сегодня, `nox_tor_set_target(onion_host, port, client_key32)` — теперь только в хранилище ключей Arti, без моста; `nox_chan_open` ключа не принимает. Подключение к onion — с подстраховкой (второе подключение в новой группе изоляции через 15 с, общий срок 45 с), как у моста. Исход подключения к onion модуль пишет и в снимок состояния Tor (`nox_tor_status().error`), как писал мост: на нём держится правило «ключ не зарегистрирован после 5 минут отказов» (040).

**TLS.** Только TLS 1.3, ALPN `http/1.1`, без SNI, без возобновления сессий и без раннего отправления данных: каждое соединение — полное рукопожатие с подписью сервера, которую модуль проверяет.

## События

| `kind` | Имя | `data` / `code` |
|---|---|---|
| 1 | `OPEN` | `data` — ключ сервера (32 байта, копировать сразу; модуль освобождает сам после вызова) |
| 2 | `DATA` | входящие байты; владеет Dart — копирует и вызывает `nox_chan_buf_free` |
| 3 | `WRITABLE` | очередь отправки опустилась ниже половины окна |
| 4 | `DRAINED` | очередь отправки пуста |
| 5 | `EOF` | другая сторона закрыла отправку |
| 6 | `CLOSED` | канал закрыт; последнее событие дескриптора; `code` — 0 или вид отказа |

## Виды отказа (`code`)

| Код | Вид | Что значит |
|---|---|---|
| 0 | `none` | закрыт штатно |
| 1 | `network` | транспорт не установился или оборвался |
| 2 | `timeout` | не уложились в `connect_timeout_ms` |
| 3 | `tls` | рукопожатие TLS не прошло |
| 4 | `protocol` | сообщение проверки не той длины или с неверной подписью (так выглядит посредник) |
| 5 | `wrong_server` | ключ сервера не тот, что ожидался |
| 6 | `tor_not_ready` | Tor не поднят |
| 7 | `tor_onion_invalid` | onion-адрес испорчен |
| 8 | `tor_onion_not_found` | сервис не найден |
| 9 | `tor_onion_unreachable` | сервис есть, но не отвечает |
| 10 | `tor_client_auth` | ключ доступа Tor отклонён (до 045) |
| 11 | `internal` | сбой в модуле |
| −7 | `invalid_argument` | возврат функции: неверные аргументы |
| −9 | `closed` | возврат функции: канала уже нет |

## Окна

- **Входящие:** модуль держит не больше 1 МиБ неподтверждённых байтов; Dart подтверждает `nox_chan_ack`, когда передал байты получателю потока, и не подтверждает, пока поток на паузе.
- **Исходящие:** окно 1 МиБ; когда `nox_chan_write` вернул больше окна, Dart ставит источник `addStream` на паузу до `WRITABLE`; `flush` ждёт `DRAINED`.

## Dart-обёртка (`package:nox_tor/channel.dart`)

```dart
abstract interface class NoxChannelApi {
  /// Opens a channel; completes when it is verified (OPEN) or failed (CLOSED with a kind).
  Future<NoxChannel> open(ChannelTarget target, {required Uint8List deviceSeed, required Uint8List serverKey,
      required Duration timeout});
}

abstract interface class NoxChannel {
  Stream<Uint8List> get incoming;        // DATA; EOF closes the stream; ack on delivery
  int write(Uint8List bytes);            // queued size after the write
  Future<void> get writable;             // next WRITABLE
  Future<void> get drained;              // next DRAINED (immediately if the queue is empty)
  void shutdownWrite();
  void close();
  Future<ChannelFailure?> get closed;    // null — closed normally
}
```

`ChannelSocket` (`lib/data/remote/channel/channel_socket.dart`) реализует `dart:io` `Socket` поверх `NoxChannel`; `ChannelHttpClient` отдаёт `HttpClient` с `connectionFactory`, открывающей канал.
