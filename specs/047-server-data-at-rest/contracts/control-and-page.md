# Контракт: пароль, бэкап и состояния служебной страницы

Служебная страница и `/control/*` — loopback, открытый HTTP, вне контракта v0. Правила защиты — те же, что у `Set` (045) и `noxd link` (046).

## Страница

| Состояние | Формы (`POST`, поля + `token`) |
|---|---|
| `setup` | `/password/setup` — `password`, `repeat` |
| `locked` | `/password/unlock` — `password` |
| `open` | `/password/change` — `current`, `password`, `repeat` |

Проверки: `Host` локальный, `Origin = http://<Host>`, токен формы. Ответ — `303` на `/` с `?error=<wrong|short|mismatch>` или без него.

## `/control/*` (команды)

Заголовок `X-Nox-Control: 1`, без `Origin`, локальный `Host`; тело — JSON; ответ — `200 {}` или `4xx {"error": "<wrong|short|mismatch|state|path>"}`: `wrong` — `403`, `short`, `mismatch`, `path` — `400`, `state` — `409`. Сбой сервера — `500 {"error": "internal"}`. У `path` и `internal` есть поле `message` — причина словами, без секретов.

| Путь | Тело | Состояние |
|---|---|---|
| `GET /control/state` | — | любое; ответ `{"state": "setup"\|"locked"\|"open"}` |
| `/control/unlock` | `{"password", "repeat"?}` | `setup` (с `repeat`), `locked` |
| `/control/password` | `{"current", "password"}` | `open` |
| `/control/backup` | `{"path"}` (абсолютный путь на этой машине) | `open` |

`/control/state` нужен `noxd unlock`, чтобы до ввода знать, спрашивать ли пароль дважды с предупреждением о забытом пароле или один раз. Ответ на `/control/unlock` приходит, когда основной порт уже слушает. `path` — путь, по которому сервер бэкап не пишет: не абсолютный, каталога нет, файл уже есть.

## Команды

```
noxd unlock   [-status-addr 127.0.0.1:8081]
noxd password [-status-addr 127.0.0.1:8081]
noxd backup <файл> [-status-addr 127.0.0.1:8081]
noxd restore <файл> -db <путь> [-files <каталог>]
```

Пароль — без эха в терминале, из стандартного ввода, если это не терминал: по строке на пароль, в порядке вопросов (`unlock` нового сервера — пароль и повтор; запертого — пароль; `password` — текущий, новый, повтор; `restore` — пароль). Ни пароль, ни ключи не выводятся. `-status-addr` — как у `noxd link`: флаг, `NOX_STATUS_ADDR`, `127.0.0.1:8081`; `noxd backup` делает путь абсолютным сам. `noxd restore` работает без сервера, `-db` обязателен; каталоги цели должны существовать.

## `/health`

`200 {"status":"locked"}` — заперт или ждёт пароль; `200 {"status":"ok"}` — открыт.

## Тексты (EN)

- Setup: `Set a password for this server` · `Password` · `Repeat password` · `Set password` · `If you forget this password, the server's data can't be opened by anyone, including you.`
- Locked: `This server is locked` · `Password` · `Unlock`
- Open: `Change password` · `Current password` · `New password` · `Repeat new password` · `Change`
- Errors: `Wrong password.` · `Use at least 12 characters.` · `The passwords don't match.`
