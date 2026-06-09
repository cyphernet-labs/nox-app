import 'package:injectable/injectable.dart';
import 'package:logger/logger.dart';
import 'package:nox_app/domain/repository/log_repository.dart';

/// Single logging channel implementation (logger package). No raw print in lib/.
@LazySingleton(as: LogRepository)
class LoggerLogRepository implements LogRepository {
  final Logger _logger = Logger(printer: SimplePrinter(printTime: true));

  @override
  void debug({Object? target, required String message}) {
    _logger.d('${_tag(target)}$message');
  }

  @override
  void error({Object? target, required Object error, StackTrace? stackTrace}) {
    _logger.e('${_tag(target)}$error', error: error, stackTrace: stackTrace);
  }

  String _tag(Object? target) => target == null ? '' : '[${target.runtimeType}] ';
}
