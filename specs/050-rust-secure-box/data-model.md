# Data Model: RustSecureBox и проверка запросами /auth и /auth2

## Величины RustSecureBox

| Величина | Размер | Откуда | Где живёт |
|---|---|---|---|
| Закрытый ключ | 32 байта | `generate_keys` | устройство — сейф, `session.device_key.private`; сервер — `server_identity.private_key` |
| Открытый ключ | 32 байта | `generate_keys`, `get_challenge` | устройство — `session.device_key.public`; сервер — `server_identity.public_key`, ссылка спаривания, ответ на `/auth`; `devices.device_key`, `pair_requests.device_key` |
| Челлендж | 32 байта | `get_challenge` | только в памяти, на одно соединение |
| Подпись | 64 байта | `sign_challenge` | только на проводе |

Правила:

- Все функции без состояния; ключи передаёт вызывающий.
- `get_challenge(sk).pk` MUST быть равен `pk` из `generate_keys`, который выдал этот `sk`.
- `check_signature` — три исхода: верна, неверна, ошибка.

## Запись сейфа устройства `session.device_key`

```json
{"private": "<base64 32 байта>", "public": "<base64 32 байта>"}
```

- Создаётся при первом запросе ключа — на пути к первому спариванию — через `generate_keys`.
- `discardSignIn()` сохраняет её, `clear()` (выход, отставка сессии) удаляет.
- Пометка «только это устройство» (`SecureStoreOptions`, 048).
- Сессия отставляется, если есть идентификатор, а запись отсутствует или `get_challenge(private).pk ≠ public` (FR-019).
- Устаревшая запись `session.device_secret` (семя Ed25519, 032–049) удаляется `sweepLegacyKeys()`.

## Строка `server_identity` (схема не меняется)

| Столбец | Было | Стало |
|---|---|---|
| `public_key` | base64 открытого Ed25519 | base64 открытого ключа RustSecureBox |
| `private_key` | base64 семени Ed25519 | base64 закрытого ключа RustSecureBox |

Жизненный цикл:

```text
нет строки ──EnsureServerIdentity──► generate_keys → INSERT (если людей нет; иначе ошибка, как сегодня)
есть строка ──ServerKey──► PublicKey(sk) == public_key ? → ключ готов
                                     ≠                → rekeyServerIdentity (одна транзакция):
                                                        DELETE pair_requests; DELETE pair_tokens;
                                                        DELETE devices; UPDATE public_key
                                                        → предупреждение в журнал
```

`users`, `chats`, `messages`, `files`, `events`, `journal` при перевыпуске не трогаются.

## Состояние проверки соединения на сервере

Живёт в памяти `connauth.Respond`, то есть при одном соединении; нигде не записывается.

```text
         POST /auth (верно)                  POST /auth2 (подпись верна)
 [ждёт /auth] ─────────────────► [ждёт /auth2] ──────────────────────────► [пройдено] → http.Server
      │                               │
      │ /auth2 → 400                  │ /auth → 400 · /auth2 подпись неверна → 401
      │ другой путь → 401             │ другой путь → 401
      │ не POST на /auth|/auth2 → 405 │ не POST → 405
      ▼                               ▼
   [разрыв]                        [разрыв]          бюджет 30 с от приёма истёк → разрыв без ответа
```

Поля: `serverChallenge` (32), `deviceKey` (32) — заполняются на `/auth`. На `/auth2` `deviceKey` становится `channelPeer.key`.

## Состояние обмена в приложении (`auth.rs`)

```text
TLS готов → get_challenge(sk_d) → POST /auth → 200 + JSON
  → check_signature(pk_s, c_a, sig_s)  — неверна → PROTOCOL
  → pk_s == ключ из ссылки ?            — нет → WRONG_SERVER
  → sign_challenge(sk_d, c_s) → POST /auth2 → 200 → OPEN(pk_s) → поток в Dart
```

Любой не-200, EOF или неразборчивый ответ — `PROTOCOL`; ошибка RustSecureBox — `INTERNAL`; время — `TIMEOUT`.

## Векторы `rsb-vectors.json`

```json
{
  "implementation": "stub-v1",
  "probe": {"private_key": "0101…01", "public_key": "<hex>"},
  "keys": [{"private_key": "<hex>", "public_key": "<hex>"}],
  "signatures": [{"private_key": "<hex>", "challenge": "<hex>", "signature": "<hex>"}],
  "checks": [{"public_key": "<hex>", "challenge": "<hex>", "signature": "<hex>", "valid": true}]
}
```

Векторы описывают только однозначные ответы. Случайные величины проверяются свойствами (research R12).
