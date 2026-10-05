# Contract: швы приложения

Внутренние интерфейсы, которые меняет фича. Сигнатуры даны как ориентир для задач; комментарии в коде — английские, как везде.

## `FileRemoteDataSource` (data, шов 016)

```dart
abstract class FileRemoteDataSource {
  /// Declares a file, or continues the unfinished upload [fileId].
  Future<ResponseEntity<UploadTicketWireEntity>> uploadBegin({
    required String name,
    required int sizeBytes,
    required String mime,
    String? fileId,
  });

  /// Sends the file from [offset] to its end (possibly nothing). Gives up after
  /// the stall limit without progress; ended by [cancellation] (its message
  /// was thrown away) or by `cancelTransfers`.
  Future<void> putBytes({
    required String uploadPath,
    required File file,
    required int offset,
    TransferProgress? onProgress,
    TransferCancellation? cancellation,
  });

  Future<ResponseEntity<DownloadTicketWireEntity>> downloadBegin({required String fileId});

  /// Opens the bytes: from [offset] when [validator] is given, whole otherwise.
  /// The caller writes them; the reply says which of the two came.
  Future<FetchedBytes> openBytes({required String downloadPath, required int offset, String? validator});

  /// Ends every byte transfer under way (`ApiClient.cancelTransfers`); a
  /// transfer started afterwards is not touched.
  void cancelTransfers();
}

/// What a GET brought: `rest` from `offset` (206) or the `whole` file (200).
class FetchedBytes {
  final bool whole;
  final int total;          // the file's full size, from Content-Range or Content-Length
  final String? validator;  // Last-Modified
  final Stream<List<int>> bytes;
  final void Function() abandon;    // let the bytes go unread (a file of another size) and hand the transfer back
}
```

`FileTransferFailure`: `passRejected` (404), `sizeMismatch` (413, 400), `staleRange` (416, **новое**), `connection` (408, 409, транспорт, застой, отмена), `pathChanged` (**новое**: передача кончилась при другом `ApiClient.pathGeneration` — путь сменился под ней), `serverError` (**новое**: 5xx, статус вне §7, `200` без размера), `sourceUnreadable` (**новое**: исходник не открылся или отказал при чтении).

`UploadTicketWireEntity` — плюс `received: int?`.

## `FileRepository` (домен)

```dart
abstract class FileRepository {
  /// Uploads [path], continuing [from] when given. Calls [onUnfinished] once the
  /// server has named a resumable upload (or with null when it forgot it, or
  /// cannot resume), and waits for it BEFORE the first byte moves. Returns the
  /// server's id only once all bytes are there.
  Future<RepositoryResult<String>> upload({
    required String path,
    required String mime,
    UnfinishedUpload? from,
    Future<void> Function(UnfinishedUpload? upload)? onUnfinished,
    TransferFraction? onProgress,
    TransferCancellation? cancellation,
  });

  /// ONE attempt, resuming whatever an earlier one left; a change of path
  /// under it continues at once within the attempt. One attempt per file at a
  /// time; a second caller joins it.
  Future<RepositoryResult<String>> download({
    required String fileId,
    required String suggestedName,
    int? expectedSize,
    TransferFraction? onProgress,
  });

  Future<String?> localPathFor({required String fileId, required String suggestedName});

  /// Stops every transfer under way (logout, change of server); a download
  /// begun before writes nothing after it.
  Future<void> cancelTransfers();

  /// Drops every downloaded and half-downloaded byte.
  Future<void> clean();
}
```

Ошибки `upload`:
- `notFound` — исходного файла нет, он изменился или не открывается;
- `payloadTooLarge`;
- `invalidRequest` — `413` или `400`;
- `internal` — второй отказ токена подряд, 5xx или статус вне §7;
- `connection` — обрыв, застой, `408`, `409`, отмена, больше пяти смен пути подряд;
- коды провода из `uploadBegin`.

Ошибки `download`:
- `attachmentGone`, `notFound` — окончательно;
- `internal` — второй отказ токена подряд, 5xx, статус вне §7, `200` без размера, или размер не сошёлся в конце;
- `connection` — обрыв, застой, сброс, больше пяти смен пути подряд.

## `AttachmentDownloadService` (домен, новый)

```dart
abstract class AttachmentDownloadService {
  /// The bytes of [attachment] on this device: fetched, or joined when already
  /// on their way. Keeps at it through broken links (FR-010); resolves with the
  /// local path, or with what ended it - a terminal refusal, or a server that
  /// kept refusing. Records the path against [messageId] itself, so a caller
  /// that stopped listening (5.3 closed) loses nothing (FR-007a).
  Future<RepositoryResult<String>> fetch({String? messageId, required MessageAttachment attachment, TransferFraction? onProgress});

  /// Stops telling [onProgress] (5.3 closed); the download goes on.
  void stopListening(TransferFraction onProgress);

  /// Stops every download and waits for them to stop, at most 5 s (logout,
  /// change of server); refuses a fetch while it runs.
  Future<void> reset();
}
```

## `OutboxService` (data)

```dart
/// Throws a message away: the record goes, then the upload of its file under
/// way is cancelled, and a pass is asked for.
Future<void> discard({required String clientMessageId});
```

## `OutboxRepository` (домен)

```dart
/// Remembers - or, with null, forgets - the unfinished upload of this send.
Future<void> noteUpload({required String clientMessageId, required UnfinishedUpload? upload});
```

`attachFile(fileId)` теперь ещё и забывает ручку. `markPending` её сохраняет.

## Кто кого зовёт

```text
OutboxService ──upload(from, onUnfinished)──► FileRepository ──► FileRemoteDataSource ──► сокет + PUT
     └── noteUpload / attachFile ──► OutboxRepository

AttachmentPrefetchService ─┐
FileViewBloc (5.3) ────────┴─fetch──► AttachmentDownloadService ──download──► FileRepository ──► сокет + GET
                                           └── attachLocalFile ──► MessageRepository

LiveSessionStarter (смена мира), AuthRepositoryImpl (выход):
    AttachmentPrefetchService.reset() → AttachmentDownloadService.reset() → FileRepository.clean()   (последние два — в отдельных try)
LiveSessionStarter._adoptGreeting → ApiClient.initBase(новый адрес) → pathGeneration++ → cancelTransfers() — передачи старого пути
    кончаются как pathChanged и продолжаются репозиторием сразу
ChatThreadBloc (Discard) → OutboxService.discard → OutboxRepository.remove → TransferCancellation.cancel() → flush
```
