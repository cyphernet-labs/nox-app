# Contract: OutboxRepository + OutboxService

Провод фаза **не меняет**: ключ уже уходит на сервер как `client_message_id` в `message.send`. Контракт здесь — внутренний: граница между экраном и очередью.

## `OutboxRepository` — `lib/domain/repository/chat/outbox_repository.dart`

```dart
abstract class OutboxRepository {
  Future<RepositoryResult<OutboxEntry>> enqueue({
    required String chatId,
    String? text,
    MessageAttachment? attachment,
  });

  Stream<List<OutboxEntry>> watchQueue({String? chatId});

  Future<List<OutboxEntry>> pending();

  Future<void> recordFailure({
    required String clientMessageId,
    required String code,
    required bool terminal,
  });

  Future<void> markPending({required String clientMessageId});

  Future<void> remove({required String clientMessageId});

  Future<void> removeForChat({required String chatId});

  Future<void> clean();
}
```

### Обязательства

| Член | Обязательство |
|---|---|
| `enqueue` | Минтит `client_message_id` **сам** и персистит запись до возврата. Ключ — единственная гарантия отсутствия дублей, и звать его на стороне экрана значило бы терять его вместе с экраном. Назначает `ordinal` в транзакции. Возвращает записанную запись. |
| `watchQueue` | Отдаёт снимок при подписке, затем каждое изменение; всегда по возрастанию `ordinal`. Без `chatId` — вся очередь. |
| `pending` | Записи в статусе `pending`, по возрастанию `ordinal`, по всем чатам — вход слива. |
| `recordFailure` | Увеличивает `attempts` и запоминает код **при каждом** неуспехе; статус переводит в `error` только когда `terminal`. Один метод, а не два: повторяемый отказ обязан растить счётчик так же, как окончательный, иначе пауза повтора не от чего расти. |
| `markPending` | Возвращает в `pending` для ручного повтора; `attempts` **не** сбрасывает — история попыток и есть основание паузы. |
| `remove` | Удаляет принятую сервером запись. |
| `removeForChat` | Удаляет очередь одного чата (сброс отладочного сценария). |
| `clean` | Опустошает store; часть вайпа логаута. |

Методы, возвращающие `RepositoryResult`, не бросают (правило `execute`). Остальные — `Future<void>`/`Stream` — идут мимо этой гарантии, как и везде в проекте; их вызывающие обязаны это учитывать.

## `OutboxService` — `lib/data/sync/outbox_service.dart`

```dart
@LazySingleton(env: [Environment.dev, Environment.prod, Environment.test])
class OutboxService {
  void start();          // подписка на фазу сессии
  Future<void> flush();  // сериализованный проход по очереди
  Future<void> stop();   // снятие подписки и таймера (логаут)
}
```

### Обязательства

1. **Единственный отправитель.** Никто, кроме сервиса, не зовёт `MessageRepository.sendMessage`.
2. **Сериализация.** Одновременные `flush()` не идут внахлёст: вызов пристраивается в хвост текущего прохода цепочкой `Future _queue`.
3. **Порядок.** Проход идёт по `pending()` в порядке `ordinal`, по одной записи, ожидая ответ.
4. **Удаление после персиста.** Запись удаляется только после успешного возврата `sendMessage` — то есть после того, как сообщение уже лежит в `messages`. Обратный порядок дал бы окно, в котором сообщения нет нигде.
5. **Классификация отказа.** `connection`, `rateLimited`, `internal`, `unknown` — повторяемые: `recordFailure(terminal: false)`, проход прерывается и планируется повтор. Прочие — окончательные: `recordFailure(terminal: true)`, проход **продолжается** со следующей записи.
6. **Пауза растёт от записи, а не от прохода.** Задержка следующей попытки — `min(30s, 1s × 2^(attempts − 1))` с ±20% джиттера, где `attempts` берётся у головной записи очереди. Счётчик прохода не годится: он обнуляется вместе с процессом, то есть ровно тогда, когда фаза обязана помнить.
7. **Пауза сбрасывается** при новом переходе в `live`: смена состояния канала — новое основание для попытки.
8. **Тишина в логах.** Пишутся только `client_message_id` и код ошибки. Ни текста, ни метки, ни имени чата (Принцип I).

## Что это выполняет из контракта v0 §9

| Пункт | Как |
|---|---|
| 3 — ключ назначается при постановке и персистится с записью | `enqueue` минтит и пишет ключ в одной операции; ключ равен ключу записи |
| 8 — очередь живёт в data-слое и переживает рестарт | store `outbox` в Sembast; экран читает её, а не хранит |
