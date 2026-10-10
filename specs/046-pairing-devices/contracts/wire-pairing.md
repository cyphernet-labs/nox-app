# Контракт: спаривание с подтверждением (дельта §8A контракта v0)

Правится первым в `docs/client-backend/protocol/contract-draft.md`.

## Токены

| Вид | Кто выпускает | Срок | Подтверждение |
|---|---|---|---|
| ссылка с машины | служебная страница, `noxd link` | 10 минут, живая одна | не нужно |
| приглашение | спаренное устройство (`device.invite`) | 10 минут | `Allow` на выдавшем |

Ссылка с машины: человека нет — создаёт его (`created: true`); есть — присоединяет к нему (`created: false`). Claim-токен без срока уходит, как и понятие «владелец».

## `pair`

```json
{"id": 1, "cmd": "pair", "data": {"token": "<16 байт, base64url>", "platform": "windows"}}
```

Ответы:

- ссылка с машины — как сегодня: `{"identity": {"id": "u_…", "label": "…", "created": true | false}}`;
- приглашение — `{"status": "pending", "request_id": "r_…", "expires_at": 1790000600}`.

Повтор с тем же токеном и тем же ключом — тот же запрос: `pending` или уже записанный исход. Другой ключ — `invalid_token`.

## `pair.cancel`

```json
{"id": 2, "cmd": "pair.cancel", "data": {"token": "…"}}
```

Отзывает свой ждущий запрос: токен сгорает. Ответ `{}`; нет ждущего запроса этого ключа — тоже `{}`.

## Событие `pair.resolved` (новому устройству, `seq: 0`)

```json
{"seq": 0, "event": "pair.resolved", "data": {"outcome": "allowed", "identity": {"id": "u_…", "label": "Anna", "created": false}}}
```

`outcome`: `allowed` (с `identity`), `denied`, `expired`, `cancelled`. После `allowed` устройство здоровается, как после спаривания.

## Событие `device.pairRequested` (выдавшему устройству, `seq: 0`)

```json
{"seq": 0, "event": "device.pairRequested", "data": {"request_id": "r_…", "platform": "windows", "expires_at": 1790000600}}
```

Приходит на все соединения выдавшего устройства, а после каждого его приветствия — повтором для живых запросов.

## `device.approve`

```json
{"id": 9, "cmd": "device.approve", "data": {"request_id": "r_…", "allow": true}}
```

Ответ `{}`. Отказы: `not_found` — запроса нет, он не этого устройства или уже закрыт; `unauthenticated` — устройство отозвано.

## Событие `device.pairResolved` (выдавшему устройству, `seq: 0`)

```json
{"seq": 0, "event": "device.pairResolved", "data": {"request_id": "r_…"}}
```

Запрос закрыт любым исходом — диалог закрывается.

## Прочее

- Выдавшее устройство отозвано, пока запрос ждёт, — запрос `denied`.
- Срок запроса = срок приглашения; истекший — `expired` без чьего-либо действия.
- `device.invite` — без изменений провода (045: `onion`, `public` в ответе).
- Отзыв последнего устройства возвращает сервер к «устройств нет»; человек и переписка остаются.
