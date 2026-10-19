# Контракт: C ABI модуля `nox_tor` — RustSecureBox и изменения канала

Дополняет `specs/044-secure-channel/contracts/ffi-channel.md`. Паника не пересекает границу: `catch_unwind` превращает её в `-3`.

## RustSecureBox для Dart

```c
// Новая пара: закрытый ключ в private_out[32], открытый в public_out[32].
int32_t nox_box_generate_keys(uint8_t *private_out, uint8_t *public_out);
// Новый челлендж в challenge_out[32] и открытый ключ private_key в public_out[32].
int32_t nox_box_get_challenge(const uint8_t *private_key, uint8_t *challenge_out, uint8_t *public_out);
// Подпись private_key над challenge в signature_out[64].
int32_t nox_box_sign_challenge(const uint8_t *private_key, const uint8_t *challenge, uint8_t *signature_out);
// 1 — подпись верна, 0 — неверна, <0 — ошибка.
int32_t nox_box_check_signature(const uint8_t *public_key, const uint8_t *challenge, const uint8_t *signature);
```

Коды: `0` — успех; `-1` — неверный аргумент, в том числе нулевой указатель; `-2` — нет случайных байтов; `-3` — внутренняя ошибка или паника. Вызовы синхронные и короткие, из любого потока.

Dart (`package:nox_tor/secure_box.dart`):

```dart
abstract interface class SecureBoxApi {
  SecureBoxKeyPair generateKeys();
  ({Uint8List challenge, Uint8List publicKey}) getChallenge(Uint8List privateKey);
  Uint8List signChallenge(Uint8List privateKey, Uint8List challenge);
  bool checkSignature(Uint8List publicKey, Uint8List challenge, Uint8List signature);
}
final class NativeSecureBoxApi implements SecureBoxApi { const NativeSecureBoxApi(); … }
final class SecureBoxException implements Exception { final int code; … }
```

Неверная длина аргумента — `ArgumentError` до вызова; отрицательный код — `SecureBoxException`. Буферы для нативного вызова выделяются через `calloc` и затираются до освобождения.

## Канал

```c
int64_t nox_chan_open(int32_t target_kind, const char *host, uint16_t port,
                      const uint8_t *device_private_key32, const uint8_t *server_key32,
                      uint32_t connect_timeout_ms, nox_chan_post_fn post, int64_t events_port);
```

- `device_private_key32` — закрытый ключ устройства от RustSecureBox (было: семя Ed25519). Модуль копирует его и затирает после обмена.
- `connect_timeout_ms` — срок на транспорт, TLS и `/auth` с `/auth2`.
- События и коды `CLOSED` не меняются: `WRONG_SERVER` (5) — ключ сервера не совпал с `server_key32`, `PROTOCOL` (4) — любая другая неудача проверки, `INTERNAL` (11) — ошибка RustSecureBox.
- Запрет нулевого семени уходит: заглушка принимает любой ключ, а настоящая реализация отвечает на неприемлемый ключ ошибкой.

Dart: параметр `deviceSeed` → `devicePrivateKey` в `NoxChannelApi.open`, `ChannelCore`, `ChannelHttpClient.bind`, `DirectProber.probe`, `ConnectionPathSelector.begin`.
