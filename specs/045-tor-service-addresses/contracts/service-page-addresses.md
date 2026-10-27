# Контракт: адреса на служебной странице

Служебная страница — loopback, открытый HTTP, вне контракта v0 (её разметку парсить нельзя). Здесь — правила формы, на которых держится безопасность записи.

## Что показывает

- Найденные адреса в локальной сети — список, только чтение.
- Публичный адрес и onion-адрес — каждый в своём поле со своей кнопкой `Set`; пустое поле и `Set` удаляют адрес.
- Предупреждение для каждого параметра запуска, который не применился: `-onion-addr is not a valid onion address. The server keeps <prior value or "no onion address">.` (аналогично для `-public-addr`).

## Запись

`POST /addresses`, `application/x-www-form-urlencoded`:

| Поле | Значение |
|---|---|
| `kind` | `public` или `onion` |
| `value` | адрес или пусто (удалить) |
| `token` | токен формы со страницы |

Проверки по порядку; первая не прошедшая — ответ без записи:

1. `Host` — локальный (`localhost`, `localhost.` или loopback-литерал), иначе `403`.
2. `Origin` есть и равен `http://<Host>`, иначе `403`.
3. `token` равен токену процесса (сравнение за постоянное время), иначе `403`.
4. `kind` известен, иначе `400`.
5. `value` пусто или проходит проверку формата: onion — версия 3, 56 знаков base32, `.onion`, контрольная сумма и байт версии; публичный — `host:port`, хост — IP или DNS-имя, порт 1–65535. Иначе — `303` на `/?invalid=<kind>`, ничего не записано.

Успех — запись в базу, новая версия снимка адресов, рассылка `server.addresses`, `303` на `/?saved=<kind>`. Значения в адрес перенаправления не попадают.

CSP страницы получает `form-action 'self'`.

## Тексты (EN)

- `Public address` · `Onion address` · `Set`
- `Saved. New links carry it, and connected devices get it now.`
- `That isn't a valid onion address. Nothing was changed.`
- `That isn't a valid address. Use host:port, like nox.example.org:8443. Nothing was changed.`
- `Found on this machine's networks`
