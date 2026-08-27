# Quickstart: локальная проверка фичи 023

Валидационный сценарий «полный чат-сценарий работает end-to-end» (DoD фазы). Он же — основа секции смоука Д в README сервера. Предпосылки и сборка — как в фазе 022 (`go build -o noxd .`, websocat). Цель по SC-006: ≤10 минут от чистой сборки.

Замечание из 022: вывод websocat направляй в терминал или файл — при `stdout → /dev/null` на macOS он рвёт соединение после первого кадра.

## Подготовка

```bash
cd client_backend
go build -o noxd . && ./noxd -addr 127.0.0.1:8080 -db /tmp/nox-smoke-023.db
```

Терминалы 1 (Anna) и 2 (Bob): `websocat ws://127.0.0.1:8080/ws`, в каждом `session.hello` со своим `label`. Anna создаёт два чата и пишет в первый (между шагами — пауза ~1 с: активность секундной гранулярности, в одной секунде порядок решает `chat_id`):

```bash
{"id":2,"cmd":"chat.create","data":{"name":"Kitchen"}}
{"id":3,"cmd":"chat.create","data":{"name":"Общий"}}          # <- CID2 из ответа
{"id":4,"cmd":"message.send","data":{"chat_id":"<CID1>","client_message_id":"a1","body":{"type":"text","text":"first"}}}
```

## Смоук Д — полный чат-сценарий (истории 1–3)

**Список и поиск (история 1):**

```bash
{"id":10,"cmd":"chats.list","data":{"page":1,"page_size":10}}
# ← оба чата; Kitchen первым (последняя активность — сообщение a1), has_more:false
{"id":11,"cmd":"chats.list","data":{"page":1,"page_size":10,"query":"общ"}}
# ← только "Общий" (регистронезависимо, кириллица)
{"id":12,"cmd":"chat.get","data":{"chat_id":"<CID2>"}}
# ← полная карточка
```

**История с догрузкой назад (история 2):** Anna шлёт в `<CID1>` ещё 4–5 сообщений (`a2`…), затем:

```bash
{"id":20,"cmd":"messages.list","data":{"chat_id":"<CID1>","limit":3}}
# ← 3 самых свежих по возрастанию seq, has_more:true; запомнить минимальный seq (= S)
{"id":21,"cmd":"messages.list","data":{"chat_id":"<CID1>","before_seq":S,"limit":10}}
# ← все более старые, has_more:false; вместе — вся история без дублей и пропусков
```

В выдаче Anna её сообщения несут `client_message_id`; тот же запрос от Bob — без этого поля.

**Переименование вживую (история 3), Bob держит соединение открытым:**

```bash
{"id":30,"cmd":"chat.nameAvailable","data":{"name":"Общий"}}                             # ← available:false
{"id":31,"cmd":"chat.nameAvailable","data":{"name":"Общий","exclude_chat_id":"<CID2>"}}  # ← available:true
{"id":32,"cmd":"chat.rename","data":{"chat_id":"<CID2>","name":"Новый общий"}}
# ← ok с картой; у Bob мгновенно (<1 c) кадр {"seq":N,"event":"chat.updated",...}
{"id":33,"cmd":"chats.list","data":{"page":1,"page_size":10}}
# ← порядок НЕ изменился: Kitchen по-прежнему первым (rename не активность)
```

**Дедуп при повторе:** повторить `message.send` с уже использованным `client_message_id` → эхо идентично, события нет, `messages.list` показывает сообщение один раз.

**Реплей:** убить Bob, переименовать ещё раз, переподключить Bob c `since` → `chat.updated` приходит в досылке в порядке журнала.

## Негативные проверки

```bash
{"id":40,"cmd":"chats.list","data":{"page":0,"page_size":10}}        # → invalid_request
{"id":41,"cmd":"chats.list","data":{"page":1,"page_size":500}}       # → ok, максимум 100 строк (клампинг)
{"id":42,"cmd":"chat.get","data":{"chat_id":"c_missing"}}            # → not_found
{"id":43,"cmd":"chat.rename","data":{"chat_id":"<CID2>","name":"KITCHEN"}}  # → name_taken (регистронезависимо)
{"id":44,"cmd":"messages.list","data":{"chat_id":"<CID1>","limit":0}}       # → invalid_request
{"id":45,"cmd":"chat.rename","data":{"chat_id":"<CID2>","name":"Новый общий"}}  # то же имя → ok, события у Bob НЕТ
```

## Автоматическая валидация

```bash
cd client_backend
gofmt -l .            # пусто
go vet ./...
go test -race ./...   # зелёные, включая новые chats_test.go / history_test.go
```
