# Data Model: Tor отдельной службой — адреса сервера

## Сервер

### `server_identity` (`001_init.sql` правится на месте)

| Колонка | Было | Стало |
|---|---|---|
| `onion_seed` | семя ключа onion-сервиса | **уходит**: ключ onion-сервиса живёт в папке службы tor |
| `public_address` | — | `host:port` или `NULL` |
| `onion_address` | — | `<56>.onion` или `NULL` |
| `public_address_param` | — | последнее применённое значение `-public-addr`; `NULL` — параметра не было |
| `onion_address_param` | — | последнее применённое значение `-onion-addr`; `NULL` — параметра не было |

- `devices.access_key` и `idx_devices_access_key` уходят.
- Запись адреса — одна транзакция писателя: значение и, если пишет параметр, `*_param`.

### Снимок адресов (`internal/server/addresses.go`)

`addressSet{Version, Direct []string, Public string, Onion string}` — `Direct` находит сервер (как сегодня), `Public` и `Onion` читаются из базы при старте и после `Set`. Новая версия снимка будит рассыльщика `server.addresses`.

### Предупреждения старта

Список «параметр — причина» в памяти процесса: собирается при применении параметров, показывается на служебной странице до следующего старта.

### Токен формы

32 случайных байта на процесс, в скрытом поле формы `Set`; сверяется за постоянное время.

## Приложение

### `ServerAddresses` (сейф, ключ `session.server_addresses`, JSON)

| Поле | Тип | Что |
|---|---|---|
| `direct` | `List<String>` | найденные сервером адреса в локальной сети |
| `public` | `String?` | публичный адрес от сервера |
| `onion` | `String?` | onion-адрес от сервера (`<56>.onion:443`) |
| `manualAddress` | `String?` | ручная правка поля «адрес сервера» |
| `manualOnion` | `String?` | ручная правка onion-адреса |
| `useTor` | `bool` | галочка `Use Tor`, по умолчанию `false` |
| `lastGood` | `String?` | последний работавший прямой адрес (как сегодня) |
| `viaTorLast` | `bool` | последнее приветствие шло через Tor (как сегодня) |

**Правила.**

- Адрес поля = `manualAddress ?? public ?? session.server_address` (первый прямой адрес ссылки); onion = `manualOnion ?? onion`.
- Пришедшее от сервера непустое значение (`public`, `onion`) сбрасывает ручную правку того же поля; пустое или отсутствующее — ручную правку оставляет, а значение от сервера стирает.
- Кандидаты напрямую: `lastGood`, `manualAddress`, `public`, `direct`, `session.server_address` — без повторов.
- Спаривание пишет: `session.server_address` — первый прямой адрес ссылки; поля экрана подключения — как ручную правку, если человек их изменил; `useTor` — как отмечено.
- Выход стирает всё.

### Уходит

`session.access_key`, `session.access_key_registered`, `AccessKeyRepository`, `AccessKeyRegistrar`, `TorError.missingClientAuth`/`wrongClientAuth`.

### `ConnectionProblem`

`invalidOnion`, `onionNotFound`, `onionUnreachable`, `otherServer`, `torNetwork`, `turnOnTor` — причина последнего неудачного раунда выбора пути; сбрасывается удачным приветствием. Откуда берётся — research R12; тексты — `contracts/connection-ui.md`.

### Состояния экранов

| Экран | Состояние |
|---|---|
| Экран подключения (`ConnectBloc`) | поля и их ошибки формата, `useTor`, `connecting`, причина неудачи, исход спаривания (как у входа: отказ токена, срок) |
| «Связь» (`ConnectionSettingsBloc`) | действующие значения, правка, `canSave`, `useTor`, причина, если связи нет |
| 5.1, 5.2, 5.4 | `problem` рядом с `isOffline` / `isServerMismatch` |
