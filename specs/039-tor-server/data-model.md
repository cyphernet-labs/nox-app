# Data Model: Сервер в сети Tor

**Feature**: [spec.md](./spec.md) · **Research**: [research.md](./research.md)

Схема живёт в одной миграции `client_backend/migrations/001_init.sql` и правится на месте (правило до первого релиза). Базы разработки пересоздаются: проверка отпечатка схемы при старте (`assertIdentitySchema`) скажет об этом сама.

## Хранимое

### `server_identity` — новый столбец `onion_seed`

| Столбец | Тип | Ограничение | Смысл |
|---|---|---|---|
| `onion_seed` | `TEXT NOT NULL` | `CHECK (onion_seed <> '')` | seed Ed25519 onion-сервиса, 32 байта, base64 — **закрытый** |

- Создаётся в той же транзакции, что и TLS-ключ (`EnsureServerIdentity`), и не меняется за жизнь хранилища (FR-008).
- Читается одной узкой функцией `OnionSeed` — по образцу `ServerSigner` — один раз при старте и передаётся супервизору tor. **Владелец seed — супервизор**: открытый ключ (`OnionPublicKey()`) и адрес (`Address()`) отдаёт он, а seed пакет `internal/tor` не покидает. `ServerIdentity`, которую получают страница статуса и `device.invite`, onion-полей не получает вовсе: одно лишнее поле там — и закрытая половина в шаге от утечки (FR-030).
- Раскрытый формат `ED25519-V3` для `ADD_ONION` собирается в памяти и нигде не хранится.

### `devices` — новый столбец `access_key`

| Столбец | Тип | Ограничение | Смысл |
|---|---|---|---|
| `access_key` | `TEXT` | `CHECK (access_key IS NULL OR access_key <> '')` | открытый ключ x25519 этого устройства, 32 байта, base64; `NULL` — ключа нет |

- Пишется в спаривании (необязательный `access_key`) и командой `device.setAccessKey`. Повторная запись заменяет значение: у устройства не больше одного ключа (FR-014).
- Ключ не может стоять у двух устройств — `CREATE UNIQUE INDEX idx_devices_access_key ON devices (access_key) WHERE access_key IS NOT NULL` — и не может совпадать с одноразовым ключом какого-либо приглашения, живого или нет: общий ключ пережил бы отзыв одного из устройств, а закрытая половина одноразового лежит в ссылке. Хранилище отказывает раньше индекса (`ErrAccessKeyTaken` → `invalid_request`); индекс делает такое состояние непредставимым.
- Исчезает вместе со строкой при отзыве: отзыв удаляет строку (FR-017), отдельного шага не нужно.
- Не входит в `store.Device` и не уходит в `device.list`. Публичные ключи устройств не показывают даже на странице статуса, и ключ доступа ничем не лучше.

### `pair_tokens` — новый столбец `access_key`

| Столбец | Тип | Ограничение | Смысл |
|---|---|---|---|
| `access_key` | `TEXT` | `CHECK (access_key IS NULL OR (kind = 'invite_device' AND access_key <> ''))` | открытая половина одноразового ключа доступа приглашения, base64 |

- Есть только у приглашения устройства, выданного с `onion: true`. Закрытая половина существует только в ссылке (FR-020).
- Приглашение выпускает только существующее устройство: человек берётся из строки устройства-выпускающего в том же `INSERT … SELECT`, и для отозванного устройства не пишется ничего (`ErrDeviceUnknown` → `unauthenticated`).
- Действует, пока `used_at IS NULL AND expires_at > now`. Использование, истечение и погашение — в том числе отзывом устройства (`RevokeDevice` выставляет `used_at` всем живым приглашениям человека) — выключают ключ без отдельного шага.

## Производное (не хранится)

### Активный список ключей

```sql
SELECT access_key FROM devices WHERE access_key IS NOT NULL
UNION ALL
SELECT access_key FROM pair_tokens
 WHERE kind = 'invite_device' AND access_key IS NOT NULL AND used_at IS NULL AND expires_at > ?
```

Вместе со списком читается ближайший момент истечения одноразового ключа — `MIN(expires_at)` по тем же условиям, — чтобы супервизор перепубликовал сервис ровно тогда, когда ключ перестаёт действовать. Одним чтением, в одной транзакции: две отдельные выборки могут разойтись вокруг идущего спаривания. Повторы в списке убираются: одинаковый ключ у двух записей — один `ClientAuthV3`.

`SetAccessKey` для устройства, которого уже нет, возвращает `ErrDeviceUnknown`; на проводе это `unauthenticated` — так же, как приветствие отозванного устройства.

### Адреса сервера (`addressSet`)

| Поле | Смысл |
|---|---|
| `version uint64` | номер снимка, только растёт |
| `direct []string` | `host:port`, до 16, без loopback и link-local, по предпочтению: 192.168/16, 10/8, 172.16/12, прочие IPv4, 100.64/10, IPv6 |
| `onion string` | `<56>.onion:443` или пусто |

Снимок пересчитывается наблюдателем и публикуется через `atomic.Pointer`. Первый считается синхронно до открытия слушателей. Равенство — поэлементное; порядок детерминирован (ранг диапазона, затем текст), поэтому перестановка интерфейсов не даёт ложного события. Имя хоста в адресе привязки разрешается с ограничением по времени, и неудачное разрешение оставляет прежний список: сбой DNS — не смена адреса. Версия растёт только при настоящем изменении.

### Отметка соединения

| Поле `client` | Под | Смысл |
|---|---|---|
| `greeted bool` | `s.mu` | ответ на приветствие уже в очереди — только такие соединения получают `server.addresses` |
| `addrVersion uint64` | `s.mu` | версия снимка, которую соединение уже получило — в ответе или событием |
| `viaOnion bool` | ставится один раз до чтения | соединение пришло через onion-вход |

`helloDone` для этого не годится: он принадлежит горутине чтения и ставится **до** ответа.

### Состояние Tor (`tor.Status`)

| Поле | Значения |
|---|---|
| `Enabled` | включён ли Tor флагом |
| `Phase` | `disabled` · `binary-missing` · `binary-too-old` · `binary-unusable` · `unavailable` · `starting` · `connecting` · `running` · `waiting-retry` |
| `Version` | строка версии tor или пусто |
| `Verdict` | `recommended` · `outdated` · `obsolete` · `unknown` |
| `Bootstrap` | процент подключения к сети, 0–100 |
| `Publication` | `not-published-no-keys` · `publishing` · `published` · `not-published-tor-down` · `not-published-keys-unreadable` |
| `LastError` | последняя ошибка без адресов и ключей; для остановки tor — по возможности последняя его строка уровня warn/err, если ей не больше минуты |
| `RetryIn` | пауза до следующего запуска в фазе `waiting-retry` |

В снимок не входят два флага супервизора и одно число страницы:

| Где | Что |
|---|---|
| `Supervisor.Offered()` | Tor включён, при последней проверке найден tor подходящей версии, ключей ≥ 1. Вердикт сети не влияет |
| `Supervisor.ReadyForInvite()` | фаза `running` и подключение 100% |
| страница статуса | сколько устройств с ключом доступа — читается из хранилища при каждом показе |

Неизменяемый снимок, публикуется супервизором через `atomic.Pointer` (research, решение 11).

Выключенный Tor — та же форма с `Enabled: false` от выключенной реализации (research, решение 17). Tor, который включён, но сервер не смог подготовить свою сторону (onion-вход не слушает, ключ onion не читается), — та же выключенная реализация, но со снимком `Enabled: true`, `Phase: unavailable` и причиной в `LastError`: страница не должна говорить «выключен» тому, кто его не выключал.

**Строки страницы** (английская микрокопия; ключи — значения полей):

| Поле | Значение | Строка |
|---|---|---|
| `Phase` | `disabled` | `Tor is turned off (-tor=false)` |
| | `binary-missing` | `tor not found — install tor 0.4.9 or newer` |
| | `binary-too-old` | `tor {version} is too old — install 0.4.9 or newer from the Tor Project's repository` |
| | `binary-unusable` | `tor was found but did not run` |
| | `unavailable` | `Tor could not be set up on this server` |
| | `starting` / `connecting` | `Connecting to the Tor network ({n}%)` |
| | `running` | `Connected to the Tor network` |
| | `waiting-retry` | `tor stopped — retrying in {d}` |
| `Verdict` | `recommended` | `recommended by the network` |
| | `outdated` | `outdated — update tor` (предупреждение) |
| | `obsolete` | `no longer accepted by the network — update tor` (предупреждение) |
| | `unknown` | `not known yet` |
| `Publication` | `published` | `Published` |
| | `publishing` | `Publishing…` |
| | `not-published-no-keys` | `Not published: no device has access yet` |
| | `not-published-tor-down` | `Not published: tor is not running` |
| | `not-published-keys-unreadable` | `Not published: the access keys could not be read` |

На странице «не забран» строка о Tor одна: `Tor: {строка фазы}`, а для `binary-unusable`, `unavailable`, `waiting-retry`, `starting` и `connecting` к ней в скобках добавляется `LastError` — сама строка этих фаз причину не называет (FR-027).

## Переходы состояний

### Супервизор tor

```
disabled                          ← флаг -tor=false; ничего не запускается

binary-missing / binary-too-old / binary-unusable ──(раз в 5 минут перепроверка)──→ starting

starting ──(управляющий порт поднят, AUTHENTICATE, TAKEOWNERSHIP)──→ connecting
connecting ──(bootstrap 100%)──→ running
running / connecting ──(tor завершился)──→ waiting-retry ──(пауза 1 с … 5 мин)──→ starting
любое ──(остановка сервера)──→ процесс tor завершён, супервизор вышел
```

### Публикация onion-сервиса (внутри `running`)

```
ключей нет ──────────────────────────────→ not-published-no-keys   (DEL_ONION и разрыв цепочек, если был)
ключи есть ──(ADD_ONION … Flags=V3Auth)──→ publishing
publishing ──(HS_DESC UPLOADED)──────────→ published
список ключей изменился ──(пауза 1 с, затем DEL_ONION + ADD_ONION)──→ publishing
какого-то прежнего ключа нет в новом списке ──→ через 5 с закрываются сервисные цепочки встречи (research, решение 15)
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
| `access_key` (pair, setAccessKey) | base64 std, ровно 32 байта, не точка малого порядка; не стоит у другого устройства и не выдан одноразовым ключом | `invalid_request` |
| `onion` (device.invite) | boolean; иное — как отсутствие | — |
| claim через onion | отказ до фиксации транзакции, токен не тратится | `invalid_token` |
