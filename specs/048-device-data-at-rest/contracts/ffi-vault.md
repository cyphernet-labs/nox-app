# Контракт: сейф в модуле `nox_tor` (C ABI)

Синхронные вызовы; паника не пересекает границу; буферы результата освобождает `nox_chan_buf_free` (044).

```c
// Ставит ключ локальной базы (32 байта). Возвращает 0 или −7.
int32_t nox_vault_set_key(const uint8_t *key32);
// Стирает ключ из памяти модуля.
void nox_vault_clear(void);
// Запечатывает запись: результат = nonce (12) ‖ шифротекст ‖ тег (16). −9 — ключа нет.
int32_t nox_vault_seal(const uint8_t *data, uintptr_t len, uint8_t **out, uintptr_t *out_len);
// Открывает запись. −4 — подделка или чужой ключ, −9 — ключа нет.
int32_t nox_vault_open(const uint8_t *data, uintptr_t len, uint8_t **out, uintptr_t *out_len);
// Кусок файла: ключ файла из имени (UTF-8), номер куска, признак последнего.
int32_t nox_vault_seal_chunk(const char *name, uint64_t index, int32_t last,
                             const uint8_t *data, uintptr_t len, uint8_t **out, uintptr_t *out_len);
int32_t nox_vault_open_chunk(const char *name, uint64_t index, int32_t last,
                             const uint8_t *data, uintptr_t len, uint8_t **out, uintptr_t *out_len);
```

Dart: `NoxVault` в `package:nox_tor/vault.dart` — `setKey`, `clear`, `seal`, `open`, `sealChunk`, `openChunk` (синхронно; ошибки — `VaultException`).
