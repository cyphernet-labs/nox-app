# Data Model: Сервер в сети Tor

**Feature**: [spec.md](./spec.md) · **Research**: [research.md](./research.md)

Схема живёт в одной миграции `client_backend/migrations/001_init.sql` и правится на месте (правило до первого релиза). Базы разработки пересоздаются: проверка отпечатка схемы при старте (`assertIdentitySchema`) скажет об этом сама.

## Хранимое

### `server_identity` — новый столбец `onion_key`

| Столбец | Тип | Ограничение | Смысл |
|---|---|---|---|
| `onion_key` | `TEXT NOT NULL` | `CHECK (onion_key <> '')` | seed Ed25519 onion-сервиса, 32 байта, base64 |

- Создаётся в той же транзакции, что и TLS-ключ (`EnsureServerIdentity`), и не меняется за жизнь хранилища (FR-008).
- Читается одной узкой функцией — по образцу `ServerSigner`, и только супервизором tor. В `ServerIdentity`, которую получают страница статуса и `device.invite`, кладётся лишь производное: открытый ключ и адрес.
- Раскрытый формат `ED25519-V3` для `ADD_ONION` собирается в памяти и нигде не хранится.

### `devices` — новый столбец `access_key`

| Столбец | Тип | Ограничение | Смысл |
|---|---|---|---|
| `access_key` | `TEXT` | `CHECK (access_key IS NULL OR access_key <> '')` | открытый ключ x25519 этого устройства, 32 байта, base64; `NULL` — ключа нет |

- Пишется в спаривании (необязательный `access_key`) и командой `device.setAccessKey`. Повторная запись заменяет значение: у устройства не больше одного ключа (FR-014).
- Исчезает вместе со строкой при отзыве: отзыв удаляет строку (FR-017), отдельного шага не нужно.
- Не входит в `store.Device` и не уходит в `device.list`. Публичные ключи устройств не показывают даже на странице статуса, и ключ доступа ничем не лучше.

### `pair_tokens` — новый столбец `access_key`

| Столбец | Тип | Ограничение | Смысл |
|---|---|---|---|
| `access_key` | `TEXT` | `CHECK (access_key IS NULL OR (kind = 'invite_device' AND access_key <> ''))` | открытая половина одноразового ключа доступа приглашения, base64 |

- Есть только у приглашения устройства, выданного с `onion: true`. Закрытая половина существует только в ссылке (FR-020).
- Действует, пока `used_at IS NULL AND expires_at > now`. Использование, истечение и погашение — в том числе отзывом устройства (`RevokeDevice` выставляет `used_at` всем живым приглашениям человека) — выключают ключ без отдельного шага.

## Производное (не хранится)

### Активный список ключей

```sql
SELECT access_key FROM devices WHERE access_key IS NOT NULL
UNION ALL
SELECT access_key FROM pair_tokens
 WHERE kind = 'invite_device' AND access_key IS NOT NULL AND used_at IS NULL AND expires_at > ?
```

Вместе со списком читается ближайший момент истечения одноразового ключа — `MIN(expires_at)` по тем же условиям, — чтобы супервизор перепубликовал сервис ровно тогда, когда ключ перестаёт действовать. Одним чтением, в одной транзакции: две отдельные выборки могут разойтись вокруг идущего спаривания.

### Адреса сервера (`addressSet`)

| Поле | Смысл |
|---|---|
| `direct []string` | `host:port`, до 16, без loopback и link-local |
| `onion string` | `<56>.onion:443` или пусто |

Снимок пересчитывается наблюдателем и публикуется через `atomic.Pointer`. Равенство — поэлементное после сортировки прямых адресов: перестановка интерфейсов не должна давать ложного события.

### Состояние Tor (`tor.Status`)

| Поле | Значения |
|---|---|
| `Enabled` | включён ли Tor флагом |
| `Phase` | `disabled` · `binary-missing` · `binary-too-old` · `starting` · `connecting` · `running` · `waiting-retry` |
| `Version` | строка версии tor или пусто |
| `Verdict` | `recommended` · `outdated` · `obsolete` · `unknown` |
| `Bootstrap` | процент подключения к сети, 0–100 |
| `Publication` | `not-published-no-keys` · `publishing` · `published` · `not-published-tor-down` |
| `AccessDevices` | сколько устройств с ключом доступа — читается из хранилища для страницы |
| `LastError` | последняя ошибка без адресов и ключей |
| `Offered` | предлагается ли onion устройствам — источник для списка адресов |

Неизменяемый снимок, публикуется супервизором через `atomic.Pointer` (research, решение 11).

## Переходы состояний

### Супервизор tor

```
disabled                          ← флаг -tor=false; ничего не запускается

binary-missing / binary-too-old ──(раз в 5 минут перепроверка)──→ starting

starting ──(управляющий порт поднят, AUTHENTICATE, TAKEOWNERSHIP)──→ connecting
connecting ──(bootstrap 100%)──→ running
running / connecting ──(tor завершился)──→ waiting-retry ──(пауза 1 с … 5 мин)──→ starting
любое ──(остановка сервера)──→ процесс tor завершён, супервизор вышел
```

### Публикация onion-сервиса (внутри `running`)

```
ключей нет ──────────────────────────────→ not-published-no-keys   (DEL_ONION, если был)
ключи есть ──(ADD_ONION … Flags=V3Auth)──→ publishing
publishing ──(HS_DESC UPLOADED)──────────→ published
список ключей изменился ──(пауза 1 с, затем DEL_ONION + ADD_ONION)──→ publishing
ключ убран из списка ──→ вдобавок закрываются сервисные цепочки встречи (research, решение 15)
tor упал ──→ not-published-tor-down ──(перезапуск)──→ publishing
```

### Одноразовый ключ доступа

```
выдан (device.invite onion:true) ──→ активен
активен ──(pair этим токеном)──→ неактивен   ┐
активен ──(expires_at прошёл)──→ неактивен   ├─ каждый переход — перепубликация без него
активен ──(отзыв устройства человека)──→ неактивен ┘
```

## Проверки на входе

| Поле | Правило | Ошибка |
|---|---|---|
| `access_key` (pair, setAccessKey) | base64 std, ровно 32 байта | `invalid_request` |
| `onion` (device.invite) | boolean; иное — как отсутствие | — |
| claim через onion | отказ до фиксации транзакции, токен не тратится | `invalid_token` |
