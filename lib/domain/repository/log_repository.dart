/// Single logging channel for the whole app. Raw print/debugPrint is banned
/// in lib/ (FR-011); everything goes through this interface.
abstract class LogRepository {
  void debug({Object? target, required String message});

  void error({Object? target, required Object error, StackTrace? stackTrace});
}
