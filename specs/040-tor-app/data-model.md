# Data Model: приложение через Tor (фаза 040)

Всё — на устройстве; сервер и контракт не меняются. Хранилища — те же, что сегодня:
- `flutter_secure_storage` — для всего, что выдаёт сервер или открывает дорогу к нему;
- `SharedPreferences` — для открытых флагов.

Логи не содержат ни onion-адреса, ни ключей (FR-013).

## Защищённое хранилище — новые записи

| Ключ | Значение | Пишется | Стирается |
|---|---|---|---|
| `session.server_addresses` | JSON `{"direct": ["host:port", …], "onion": "<56>.onion:443" \| null, "last_good": "host:port" \| null}` | ответ на приветствие (`addresses`), событие `server.addresses`, успешное соединение (`last_good`) | `clear()`, `discardSignIn()` |
| `session.access_key` | base64 32 байт — закрытый ключ X25519 устройства | при первом обращении, если его нет; заново при отказе сервера | `clear()`; **не** `discardSignIn()` — как и ключ устройства, он принадлежит установке |
| `session.access_key_registered` | `"1"` или нет записи | успешный `device.setAccessKey` | `clear()`, `discardSignIn()`, смена ключа |
| `session.invite_onion` | `<56>.onion:443` из ссылки v2 | спаривание по ссылке v2 | после ответа на `pair` или отказа, `clear()`, `discardSignIn()` |
| `session.invite_access_key` | base64 32 байт — закрытый одноразовый ключ из ссылки v2 | там же | там же (FR-021) |

`session.server_address` (адрес из ссылки) и `session.server_fingerprint` — без изменений. Адрес из ссылки остаётся исходным прямым кандидатом (FR-010).

Новые ключи явно перечисляются в `clear()` и `discardSignIn()`: `clear()` удаляет по имени и проверяет, что удалено.

## Открытые настройки (`SharedPreferences`)

| Ключ | Значение | Смысл |
|---|---|---|
| `tor.obsolete_build` | номер сборки приложения | сеть объявила встроенный клиент негодным в этой сборке. Tor не запускается, пока номер сборки не сменится (FR-026) |

## Эпоха локальных данных (`SyncDao`)

| Было | Стало |
|---|---|
| `live:<host:port>` | `fp:<отпечаток сервера>` |

**Переход**: если сохранённая эпоха начинается с `live:`, она переписывается на `fp:<отпечаток>` без стирания (FR-012). Если сохранена `fp:` с другим отпечатком, мир стирается, как сегодня при смене адреса.

## Доменные модели (`lib/domain/model/`)

### `ServerAddresses`

| Поле | Тип | Правило |
|---|---|---|
| `direct` | `List<String>` | `host:port`, IPv6 в скобках; 0–16 элементов, порядок сервера (предпочтения) |
| `onion` | `String?` | `<56 знаков>.onion:443`; `null` — сервер onion не предлагает |
| `lastGood` | `String?` | последний прямой адрес, ответивший правильным отпечатком |

Метод `candidates(linkAddress)` возвращает порядок попыток прямого пути: `lastGood`, затем `direct`, затем адрес ссылки, без повторов.

### `ConnectionPath`

`direct` · `tor`

### `ConnectionStatus`

| Поле | Тип | Смысл |
|---|---|---|
| `state` | `ConnectionState` | `connecting` · `catchingUp` · `online` · `offline` · `serverMismatch` · `unsupported` |
| `path` | `ConnectionPath?` | путь, которым связь идёт или поднимается; `null` — пока не выбран |
| `torObsolete` | `bool` | сеть Tor не принимает встроенный клиент |

Производные: `isOffline` (`state == offline`), `isServerMismatch`, `showsTorBadge` (`path == tor && state ∈ {connecting, catchingUp, online}`).

### `TorStatus` (от модуля)

| Поле | Тип | Смысл |
|---|---|---|
| `state` | `TorState` | `stopped` · `bootstrapping` · `ready` · `dormant` · `failed` · `obsolete` |
| `bootstrapPercent` | `int` | 0–100 |
| `error` | `TorError?` | `missingClientAuth` · `wrongClientAuth` · `timeout` · `network` · `internal` |
| `port` | `int?` | порт моста на `127.0.0.1`, пока цель задана |

### `DeviceInvite`

| Поле | Тип | Смысл |
|---|---|---|
| `link` | `String` | ссылка спаривания |
| `onion` | `bool` | ссылка версии 2 работает из любой сети; `false` — только в домашней сети |

### `PairingLink` (расширение)

Версия 2 — поля версии 1, затем:
- `onionPub` — 32 байта;
- `onionPort` — 2 байта;
- `oneTimePriv` — 32 байта.

Длины по контракту §8A: 122 байта для IPv4, 134 для IPv6, 119 + N для DNS-имени. Версия 1 разбирается как сегодня.

## Состояния выбора пути

```
start / сеть сменилась / возврат из фона
  └─→ connecting(path: null)
        ├─ прямой кандидат ответил верным отпечатком ──→ socket → catchingUp(direct) → online(direct)
        ├─ прямых нет, Tor доступен ──→ connecting(tor) → (подъём ≤ 90 с) → socket → catchingUp(tor) → online(tor)
        │       └─ отказ отпечатка на onion ──→ serverMismatch (терминально до перезапуска)
        └─ ничего ──→ offline (держится на повторах лестницы до первого успеха)

online(tor)
  ├─ сеть сменилась / прошло 2 мин ──→ проверка прямых кандидатов
  │       └─ ответил ──→ socket.switch(direct) → online(direct) → Tor stop (≤ 10 с)
  └─ разрыв ──→ connecting(…) по лестнице

online(direct)
  └─ сеть сменилась ──→ проверка текущего адреса → не отвечает → connecting(null)
```

«Tor доступен» значит одновременно:
- платформа поддерживает Tor (не Linux);
- onion-адрес известен — из списка или из ссылки v2;
- есть ключ: зарегистрированный свой или одноразовый из ссылки v2;
- `tor.obsolete_build` не равен текущей сборке.

## Проверки

| Что | Правило | Где |
|---|---|---|
| Прямой кандидат | TLS 1.3 + отпечаток листа + `GET /health` → 200, таймаут попытки 2,5 с, общий бюджет 5 с | `ConnectionPathSelector` |
| Ключ доступа | 32 байта X25519; сервер может отказать как негодному или чужому → новый ключ, не больше 3 раз за сессию | `AccessKeyRepository` |
| Секрет моста | ровно 32 байта, сравнение за постоянное время, иначе соединение закрывается | Rust `forwarder` |
| Цель моста | только onion-адрес, заданный приложением | Rust `forwarder` |
