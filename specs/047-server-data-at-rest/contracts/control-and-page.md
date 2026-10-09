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

Заголовок `X-Nox-Control: 1`, без `Origin`, локальный `Host`; тело — JSON; ответ — `200 {}` или `4xx {"error": "<wrong|short|mismatch|state>"}`.

| Путь | Тело | Состояние |
|---|---|---|
| `/control/unlock` | `{"password", "repeat"?}` | `setup` (с `repeat`), `locked` |
| `/control/password` | `{"current", "password"}` | `open` |
| `/control/backup` | `{"path"}` (абсолютный путь на этой машине) | `open` |

## Команды

```
noxd unlock   [-status-addr 127.0.0.1:8081]
noxd password [-status-addr 127.0.0.1:8081]
noxd backup <файл> [-status-addr 127.0.0.1:8081]
noxd restore <файл> -db <путь> [-files <каталог>]
```

Пароль — без эха в терминале, из стандартного ввода, если это не терминал. Ни пароль, ни ключи не выводятся.

## `/health`

`200 {"status":"locked"}` — заперт или ждёт пароль; `200 {"status":"ok"}` — открыт.

## Тексты (EN)

- Setup: `Set a password for this server` · `Password` · `Repeat password` · `Set password` · `If you forget this password, the server's data can't be opened by anyone, including you.`
- Locked: `This server is locked` · `Password` · `Unlock`
- Open: `Change password` · `Current password` · `New password` · `Repeat new password` · `Change`
- Errors: `Wrong password.` · `Use at least 12 characters.` · `The passwords don't match.`
