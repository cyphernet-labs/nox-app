# Контракт: сейф в модуле `nox_tor` (C ABI)

Синхронные вызовы; паника не пересекает границу; буферы результата освобождает `nox_chan_buf_free` (044). Коды: 0 — успех; −4 — подделка или чужой ключ; −7 — неверный аргумент (пустое имя, `last` не 0/1, ключ из одних нулей — прежний ключ остаётся); −9 — ключа нет; −11 — внутренняя ошибка. Порядок проверок: −7, затем −9, затем −4; буфер в `*out` — только при 0; пустой результат — `NULL` и длина 0.

**Ключи.** `nox_vault_set_key` хранит ключ локальной базы и сразу выводит ключ записей `HKDF-SHA256(ключ, без соли, info = "nox/devrec/v1")`; записи запечатываются только им. Ключ куска — `HKDF-SHA256(ключ, info = "nox/devfile/v1|" + name)`, где `name` — hex случайного 16-байтного id файла из его заголовка: имя не меняется, пока живут байты файла (переименование `.part` в готовый файл и перенос копии исходящего в кэш его не трогают). Кусок запечатывается только целым: тот же номер под тем же именем с другими байтами повторил бы nonce.

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
