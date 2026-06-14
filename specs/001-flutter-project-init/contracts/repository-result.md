# Контракт: `RepositoryResult<T>`

> **Источник:** блюпринт `docs/blueprints/mobile/03-domain-layer.md` §1–§2; требование FR-014. Единый тип результата repo-слоя — примитив доступен в каркасе даже без реальных репозиториев фич.

## 1. Форма — data XOR exception

`RepositoryResult<T>` — `@freezed sealed`-класс с **взаимоисключающими** вариантами: либо данные, либо исключение, ровно один в наличии. **Только `.freezed.dart`** (без `.g.dart`, без `fromJson`) — тип живёт целиком внутри процесса.

```dart
// lib/domain/repository/base/repository_result.dart
@freezed
sealed class RepositoryResult<T> with _$RepositoryResult<T> {
  const RepositoryResult._();

  const factory RepositoryResult.success({required T data}) = RepositoryResultSuccess<T>;
  const factory RepositoryResult.error({required BaseRepositoryException exception}) = RepositoryResultError<T>;

  bool get hasData => this is RepositoryResultSuccess<T>;
  T? get data => switch (this) { RepositoryResultSuccess(:final data) => data, _ => null };
  BaseRepositoryException? get exception => switch (this) { RepositoryResultError(:final exception) => exception, _ => null };
}
```

Правила контракта:

- **Две именованные обязательные фабрики:** `RepositoryResult.success(data:)` / `RepositoryResult.error(exception:)`. «Partial»-состояние (оба поля заполнены) невозможно.
- **Публичные варианты** `RepositoryResultSuccess<T>` / `RepositoryResultError<T>` — на них можно `switch`'иться напрямую.
- `.exception` — **всегда** подтип `BaseRepositoryException` (домен-тип ошибок), **никогда** сырой `Exception` или фреймворковая ошибка. Типизированные `DaoException` / `ApiException` data-слоя мапятся в `RepositoryException` (пример/TBD: конкретный маппинг ApiException появляется с бэкендом, см. `04`).
- `hasData` — безопасная булева проверка; **`result.data!` без guard'а запрещён** (на error-пути бросает).

## 2. Потребление — `match<R>`

Канонический способ потребить результат — тримнутое расширение `match<R>` (только `onData` / `onError`, без `onPartial`/`onEmpty` — для двух взаимоисключающих вариантов они бессмысленны):

```dart
// lib/domain/repository/base/repository_result_handling.dart
extension RepositoryResultMatch<T> on RepositoryResult<T> {
  R match<R>({
    required R Function(T data) onData,
    required R Function(BaseRepositoryException exception) onError,
  }) => switch (this) {
        RepositoryResultSuccess(:final data) => onData(data),
        RepositoryResultError(:final exception) => onError(exception),
      };
}
```

`switch` по публичным вариантам исчерпывающий — компилятор гарантирует обе ветки без `?? unknown`-страховок.

## 3. Правило для repo-методов

Каждый метод репозитория возвращает **`Future<RepositoryResult<T>>`** или **`Stream<RepositoryResult<T>>`** — **никогда** голый `Future<T>`. Семантика префиксов (`watch*`/`fetch*`/`get*`/`create*`/`update*`/`delete*`/`clean`) — в `03` §4.1. В скелете единственный потребитель — `Item`-verification-harness (`ItemRepository.getItems` — network-only пагинированный список на mock-данных, FR-013); сам примитив `RepositoryResult` доступен всем будущим фичам.

## 4. Иерархия исключений

- `BaseRepositoryException` — пустой маркер (`abstract class BaseRepositoryException {}`), без JSON.
- `RepositoryException` — enum общих режимов отказа (`unknown`, `internal`, `authentication`, `connection`, `unauthenticated`, `notFound`), реализующий маркер.
- Feature-specific исключения — отдельные enum'ы, реализующие тот же маркер; все одинаково проходят через `match()`.

## Чеклист

- [ ] `RepositoryResult<T>` — `@freezed sealed`, варианты `RepositoryResultSuccess`/`RepositoryResultError`, фабрики `success(data:)`/`error(exception:)`, только `.freezed.dart`.
- [ ] `match<R>({onData, onError})` — исчерпывающий `switch` по публичным вариантам.
- [ ] Каждый repo-метод возвращает `RepositoryResult<T>` (или `Stream<...>`); нигде нет `result.data!` без `hasData`-guard'а.
- [ ] `.exception` всегда — `BaseRepositoryException`, не сырой `Exception`.
